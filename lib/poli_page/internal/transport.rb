# frozen_string_literal: true

require "net/http"
require "openssl"
require "timeout"
require "uri"
require "zlib"

require_relative "http"
require_relative "watchdog"

module PoliPage
  module Internal
    # @api private
    #
    # Thin wrapper around `Net::HTTP`. The ONLY module that opens sockets to
    # the API. Translates network-level exceptions into
    # the `PoliPage::Error` hierarchy at the seam (§8 error mapping).
    #
    # Each attempt opens its own connection and reads the whole answer, body
    # included, inside its `timeout`:
    #
    # - Opening the connection (DNS, TCP, a proxy's CONNECT, TLS) is bounded
    #   by the time left, then a {Watchdog} closes the connection when the
    #   attempt's deadline passes, so a server that drips its headers or body
    #   byte by byte cannot keep the attempt alive past `timeout`.
    #   `open_timeout`, `read_timeout` and `write_timeout` are set to it too.
    # - `max_retries` is 0: `Net::HTTP` would otherwise send a GET or DELETE a
    #   second time by itself after a read error or a timeout, an attempt the
    #   SDK neither counts nor reports. Every resend is the SDK's own retry.
    # - `ignore_eof` is false: a body shorter than its `Content-Length` is a
    #   dropped connection, not a short answer.
    #
    # Honors `http_proxy`, `https_proxy`, and `no_proxy` environment variables
    # by default (via `Net::HTTP`'s `:ENV` proxy resolution). Pass `proxy:` to
    # force an explicit proxy URL or `ca_file:` / `ca_path:` to point at a
    # custom CA bundle (e.g., a corporate MITM TLS-terminating proxy).
    class Transport
      # `body_error` is set when a non-2xx answer's status and headers arrived
      # but its body could not be read (sdk-specification.md §8.2); `body` is
      # nil then.
      Response = Data.define(:status, :headers, :body, :body_error)

      VERBS = {
        get:    Net::HTTP::Get,
        post:   Net::HTTP::Post,
        delete: Net::HTTP::Delete
      }.freeze

      # `Net::HTTP`'s own timeouts. Not `Timeout::Error` as a whole: a caller's
      # `Timeout.timeout` around an SDK call must reach the caller as is.
      SOCKET_TIMEOUTS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze

      # Exceptions that mean the connection failed or broke before a complete
      # answer arrived.
      NETWORK_ERRORS = [
        SystemCallError, IOError, SocketError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error, *SOCKET_TIMEOUTS
      ].freeze

      # A `Net::HTTP` for one connection to `uri`, with the SDK's settings: no
      # hidden resend (`max_retries` 0), a short body is an error
      # (`ignore_eof` false), `timeout` (seconds) on every socket operation.
      def self.build_http(uri, timeout:, proxy: nil, ca_file: nil, ca_path: nil)
        http = Net::HTTP.new(uri.host, uri.port, *proxy_args(proxy))
        http.max_retries = 0
        http.ignore_eof = false
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout
        configure_tls(http, uri, ca_file, ca_path)
        http
      end

      # Default `:ENV` lets `Net::HTTP` resolve `http_proxy` / `https_proxy` /
      # `no_proxy` (via `URI#find_proxy`) per-request.
      def self.proxy_args(proxy)
        return [:ENV, nil, nil, nil] if proxy.nil?

        pu = URI.parse(proxy)
        [pu.host, pu.port, pu.user, pu.password]
      end

      def self.configure_tls(http, uri, ca_file, ca_path)
        return unless uri.scheme == "https"

        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = ca_file if ca_file
        http.ca_path = ca_path if ca_path
      end
      private_class_method :proxy_args, :configure_tls

      def initialize(base_url:, timeout:, proxy: nil, ca_file: nil, ca_path: nil)
        @base_url = base_url
        @timeout  = timeout
        @proxy    = proxy
        @ca_file  = ca_file
        @ca_path  = ca_path
      end

      # @param method  [Symbol]               :get, :post, or :delete
      # @param path    [String]               e.g. "/v1/render"
      # @param headers [Hash{String=>String}]
      # @param body    [String, nil]          JSON-encoded body or nil
      # @return        [Response]
      # @raise         [PoliPage::TimeoutError, PoliPage::ConnectionError]
      def execute(method:, path:, headers:, body: nil)
        uri = URI.parse(HTTP.build_url(@base_url, path))
        request = build_request(method, uri, headers, body)
        run_attempt(uri, request, { deadline: HTTP.monotonic_now + @timeout, head: nil, watchdog: nil })
      end

      private

      def run_attempt(uri, request, attempt)
        perform(uri, request, attempt)
      rescue StandardError => e
        # Once the watchdog has closed the connection, whatever `Net::HTTP`
        # raises next is that timeout.
        raise unless network_error?(e) || attempt[:watchdog]&.fired?

        failed(e, attempt)
      end

      def perform(uri, request, attempt)
        http = self.class.build_http(uri, timeout: @timeout, proxy: @proxy, ca_file: @ca_file, ca_path: @ca_path)
        open_connection(http, attempt)
        begin
          response = within_deadline(http, attempt) do
            http.request(request) do |res|
              attempt[:head] = res
              res.read_body
            end
          end
          build_response(response)
        ensure
          http.finish if http.started?
        end
      end

      # Opens the connection (DNS and TCP, a proxy's CONNECT, the TLS
      # handshake) within what is left of the attempt's timeout. `Net::HTTP`
      # bounds each of those phases on its own, each with the full
      # `open_timeout` or `read_timeout`; the whole is bounded here the way
      # `Net::HTTP` bounds its TCP open, with `Timeout.timeout` raising
      # `Net::OpenTimeout`. No caller code runs inside it.
      def open_connection(http, attempt)
        Timeout.timeout(time_left(attempt), Net::OpenTimeout) { http.start }
      end

      # Runs the request under a {Watchdog} armed with what is left of the
      # attempt's timeout once the connection is open.
      def within_deadline(http, attempt, &)
        watchdog = attempt[:watchdog] = Watchdog.new(time_left(attempt)) { http.finish }
        begin
          yield
        ensure
          watchdog.disarm
        end
      end

      def time_left(attempt)
        left = attempt[:deadline] - HTTP.monotonic_now
        raise Net::OpenTimeout, "the attempt's timeout has passed" unless left.positive?

        left
      end

      def network_error?(error)
        NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }
      end

      # A non-2xx answer whose body failed is still an answer: its status and
      # `x-request-id` are kept (sdk-specification.md §8.2). Anything else is
      # a timeout, or a network error.
      def failed(error, attempt)
        head = attempt[:head]
        return body_failed(head, error) if head && !(200..299).cover?(head.code.to_i)
        if SOCKET_TIMEOUTS.any? { |klass| error.is_a?(klass) } || attempt[:watchdog]&.fired?
          raise PoliPage::TimeoutError.new(timeout: @timeout, cause: error)
        end

        raise PoliPage::ConnectionError.new(cause: error)
      end

      def body_failed(head, error)
        Response.new(status: head.code.to_i, headers: header_hash(head), body: nil, body_error: error)
      end

      def build_response(response)
        Response.new(status: response.code.to_i, headers: header_hash(response), body: response.body,
                     body_error: nil)
      end

      def header_hash(response)
        response.to_hash.transform_values { |v| v.is_a?(Array) ? v.first : v }
      end

      def build_request(method, uri, headers, body)
        verb_class = VERBS.fetch(method) { raise ArgumentError, "unsupported method: #{method.inspect}" }
        request = verb_class.new(uri.request_uri)
        headers.each { |k, v| request[k] = v }
        request.body = body if body && method == :post
        request
      end
    end
  end
end
