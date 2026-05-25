# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

require_relative "http"

module PoliPage
  module Internal
    # @api private
    #
    # Thin wrapper around `Net::HTTP`. The ONLY module that opens sockets
    # (sdk-ruby-plan.md §3.2). Translates network-level exceptions into the
    # `PoliPage::Error` hierarchy at the seam (§8 error mapping).
    #
    # Honors `http_proxy`, `https_proxy`, and `no_proxy` environment variables
    # by default (via `Net::HTTP`'s `:ENV` proxy resolution). Pass `proxy:` to
    # force an explicit proxy URL or `ca_file:` / `ca_path:` to point at a
    # custom CA bundle (e.g., a corporate MITM TLS-terminating proxy).
    class Transport
      Response = Data.define(:status, :headers, :body)

      VERBS = {
        get:    Net::HTTP::Get,
        post:   Net::HTTP::Post,
        delete: Net::HTTP::Delete
      }.freeze

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
        build_response(perform_request(uri, build_request(method, uri, headers, body)))
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        raise PoliPage::TimeoutError.new(timeout: @timeout)
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
             Errno::EHOSTUNREACH, Errno::ENETUNREACH, OpenSSL::SSL::SSLError => e
        raise PoliPage::ConnectionError.new(message: e.message, cause: e)
      end

      private

      def perform_request(uri, request)
        p_addr, p_port, p_user, p_pass = proxy_args
        opts = {
          use_ssl:       uri.scheme == "https",
          open_timeout:  @timeout,
          read_timeout:  @timeout,
          write_timeout: @timeout
        }
        opts[:ca_file] = @ca_file if @ca_file
        opts[:ca_path] = @ca_path if @ca_path
        Net::HTTP.start(uri.host, uri.port, p_addr, p_port, p_user, p_pass, opts) do |http|
          http.request(request)
        end
      end

      # Default `:ENV` lets `Net::HTTP` resolve `http_proxy` / `https_proxy` /
      # `no_proxy` (via `URI#find_proxy`) per-request. Returning a tuple lets
      # us pass positionally without keyword/positional ambiguity.
      def proxy_args
        return [:ENV, nil, nil, nil] if @proxy.nil?

        pu = URI.parse(@proxy)
        [pu.host, pu.port, pu.user, pu.password]
      end

      def build_response(response)
        Response.new(
          status:  response.code.to_i,
          headers: response.to_hash.transform_values { |v| v.is_a?(Array) ? v.first : v },
          body:    response.body
        )
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
