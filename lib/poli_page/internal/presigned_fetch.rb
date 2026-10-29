# frozen_string_literal: true

require "net/http"
require "uri"

require_relative "transport"

module PoliPage
  module Internal
    # @api private
    #
    # Mixin used by `PoliPage::Client` for the unauthenticated presigned-URL
    # second hop (DocumentDescriptor#download_pdf, render.pdf, pdf_stream).
    # The presigned URL is signed by S3 and MUST NOT be retried by the SDK
    # (sdk-specification.md §7.2, §9.1): the `Net::HTTP` it uses has
    # `max_retries` 0, so it never sends the GET twice either.
    #
    # Every failure is `PoliPage::DownloadError` (`DOWNLOAD_FAILED`): with the
    # storage status on a non-2xx answer, with the network message when no
    # complete answer came (a connection error, a dropped body or a timeout).
    #
    # Honors the same proxy/CA configuration as {PoliPage::Internal::Transport}
    # — reads `@proxy`, `@ca_file`, `@ca_path`, `@timeout` from the including
    # `Client` instance. `@timeout` bounds each socket operation (connect, and
    # every read), not the whole download, so a long `pdf_stream` is not cut.
    module PresignedFetch
      # Fetch the entire body of `url`. Returns the raw bytes; raises
      # PoliPage::DownloadError on non-2xx or network failure.
      def fetch_bytes(url)
        uri = URI.parse(url)
        http = presigned_http(uri)
        response = http.start do
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |res|
            guard_presigned_status!(res)
            res.read_body
          end
        end
        response.body
      rescue *Transport::NETWORK_ERRORS => e
        raise PoliPage::DownloadError.new(cause: e)
      end

      # Stream the body of `url` to the block. Raises PoliPage::DownloadError
      # on non-2xx or network failure and PoliPage::InternalError on
      # Content-Length: 0 (port of Node `render.ts:128-130` `!response.body`
      # guard). An error raised by the block itself propagates unchanged.
      def stream_bytes(url, &block)
        uri = URI.parse(url)
        http = presigned_http(uri)
        in_block = false
        http.start do
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            guard_stream!(response)
            response.read_body do |chunk|
              in_block = true
              block.call(chunk)
              in_block = false
            end
          end
        end
        nil
      rescue *Transport::NETWORK_ERRORS => e
        raise if in_block

        raise PoliPage::DownloadError.new(cause: e)
      end

      private

      def presigned_http(uri)
        Transport.build_http(uri, timeout: @timeout, proxy: @proxy, ca_file: @ca_file, ca_path: @ca_path)
      end

      def guard_presigned_status!(response)
        status = response.code.to_i
        return if (200..299).cover?(status)

        raise PoliPage::DownloadError.new(status: status)
      end

      def guard_stream!(response)
        guard_presigned_status!(response)
        return unless response["Content-Length"] == "0"

        raise PoliPage::InternalError.new("response has no body", status: response.code.to_i)
      end
    end
  end
end
