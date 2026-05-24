# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

require_relative "http"

module PoliPage
  module Internal
    # Thin wrapper around `Net::HTTP`. The ONLY module that opens sockets
    # (sdk-ruby-plan.md §3.2). Translates network-level exceptions into the
    # `PoliPage::Error` hierarchy at the seam (§8 error mapping).
    class Transport
      Response = Data.define(:status, :headers, :body)

      VERBS = {
        get:    Net::HTTP::Get,
        post:   Net::HTTP::Post,
        delete: Net::HTTP::Delete
      }.freeze

      def initialize(base_url:, timeout:)
        @base_url = base_url
        @timeout  = timeout
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
        Net::HTTP.start(uri.host, uri.port,
                        use_ssl:       uri.scheme == "https",
                        open_timeout:  @timeout,
                        read_timeout:  @timeout,
                        write_timeout: @timeout) { |http| http.request(request) }
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
