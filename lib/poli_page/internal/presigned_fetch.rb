# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module PoliPage
  module Internal
    # @api private
    #
    # Mixin used by `PoliPage::Client` for the unauthenticated presigned-URL
    # second hop (DocumentDescriptor#download_pdf, render.pdf, pdf_stream).
    # The presigned URL is signed by S3 and MUST NOT be retried by the SDK
    # (sdk-ruby-plan.md §5.5).
    #
    # Honors the same proxy/CA configuration as {PoliPage::Internal::Transport}
    # — reads `@proxy`, `@ca_file`, `@ca_path`, `@timeout` from the including
    # `Client` instance.
    module PresignedFetch
      # Fetch the entire body of `url`. Returns the raw bytes; raises
      # PoliPage::DownloadError on non-2xx or network failure.
      def fetch_bytes(url)
        uri = URI.parse(url)
        response = start_presigned(uri) { |http| http.request(Net::HTTP::Get.new(uri.request_uri)) }
        guard_presigned_status!(response)
        response.body
      rescue *PRESIGNED_NETWORK_ERRORS => e
        raise PoliPage::DownloadError.new(message: e.message)
      end

      # Stream the body of `url` to the block. Raises PoliPage::DownloadError
      # on non-2xx and PoliPage::InternalError on Content-Length: 0 (port of
      # Node `render.ts:128-130` `!response.body` guard).
      def stream_bytes(url, &block)
        uri = URI.parse(url)
        start_presigned(uri) do |http|
          http.request_get(uri.request_uri) { |response| yield_stream_chunks(response, &block) }
        end
      rescue *PRESIGNED_NETWORK_ERRORS => e
        raise PoliPage::DownloadError.new(message: e.message)
      end

      PRESIGNED_NETWORK_ERRORS = [
        SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
        Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError
      ].freeze
      private_constant :PRESIGNED_NETWORK_ERRORS

      private

      def start_presigned(uri, &)
        p_addr, p_port, p_user, p_pass = presigned_proxy_args
        opts = {
          use_ssl:      uri.scheme == "https",
          open_timeout: @timeout,
          read_timeout: @timeout
        }
        opts[:ca_file] = @ca_file if @ca_file
        opts[:ca_path] = @ca_path if @ca_path
        Net::HTTP.start(uri.host, uri.port, p_addr, p_port, p_user, p_pass, opts, &)
      end

      def presigned_proxy_args
        return [:ENV, nil, nil, nil] if @proxy.nil?

        pu = URI.parse(@proxy)
        [pu.host, pu.port, pu.user, pu.password]
      end

      def guard_presigned_status!(response)
        status = response.code.to_i
        return if (200..299).cover?(status)

        raise PoliPage::DownloadError.new(
          message: "Failed to download: #{status} #{response.message}",
          status:  status
        )
      end

      def yield_stream_chunks(response, &)
        guard_presigned_status!(response)
        status = response.code.to_i
        raise PoliPage::InternalError.new("response has no body", status: status) if response["Content-Length"] == "0"

        response.read_body(&)
      end
    end
  end
end
