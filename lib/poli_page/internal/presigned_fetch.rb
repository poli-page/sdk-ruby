# frozen_string_literal: true

require "net/http"
require "timeout"
require "uri"

require_relative "http"
require_relative "transport"
require_relative "watchdog"

module PoliPage
  module Internal
    # @api private
    #
    # Mixin used by `PoliPage::Client` for the unauthenticated presigned-URL
    # second hop (DocumentDescriptor#download_pdf, render.pdf, pdf_stream).
    # The presigned URL is signed by the storage and is never retried by the
    # SDK: the `Net::HTTP` it uses has `max_retries` 0, so it never sends the
    # GET twice either.
    #
    # Every failure is `PoliPage::DownloadError` (`DOWNLOAD_FAILED`): with the
    # storage status on a non-2xx answer, with the timeout message when the
    # client's `timeout` elapsed, and with the network message when no
    # complete answer came otherwise (a connection error, or a body cut short
    # of its `Content-Length`).
    #
    # The client's `timeout` (seconds) bounds the download:
    #
    # - {#fetch_bytes} (`download_pdf`, `render.pdf`): the whole download,
    #   from opening the connection to the last byte of the body.
    # - {#stream_bytes} (`render.pdf_stream`, `render_to_file`): an idle
    #   timeout. Opening the connection, the request, the answer's head and
    #   the first chunk of the body share one deadline; then each wait for
    #   the next chunk is bounded on its own (`Net::HTTP`'s `read_timeout`),
    #   so a large PDF read at the caller's pace is not cut off. Time spent
    #   in the caller's block is never counted.
    #
    # A failure is labelled a timeout only when one of those bounds fired:
    # `Net::HTTP`'s own `Net::OpenTimeout` / `Net::ReadTimeout` /
    # `Net::WriteTimeout`, or the {Watchdog} closing the connection at the
    # deadline. A `timeout` of zero or less has already passed, so the
    # download fails at once with the timeout message, as an API call does.
    #
    # Honors the same proxy/CA configuration as {PoliPage::Internal::Transport}
    # — reads `@proxy`, `@ca_file`, `@ca_path`, `@timeout` from the including
    # `Client` instance.
    module PresignedFetch
      # Fetch the entire body of `url`. Returns the raw bytes; raises
      # PoliPage::DownloadError on non-2xx, network failure or timeout.
      def fetch_bytes(url)
        uri = URI.parse(url)
        http = presigned_http(uri)
        download = new_download
        presigned_request(http, download) do
          watchdog = download[:watchdog] = Watchdog.new(presigned_time_left(download)) { http.finish }
          begin
            http.request(Net::HTTP::Get.new(uri.request_uri)) do |res|
              guard_presigned_status!(res)
              res.read_body
            end.body
          ensure
            watchdog.disarm
          end
        end
      end

      # Stream the body of `url` to the block. Raises PoliPage::DownloadError
      # on non-2xx, network failure or timeout (before the first chunk, or
      # between two chunks), and PoliPage::InternalError on Content-Length: 0
      # (port of Node `render.ts:128-130` `!response.body` guard). An error
      # raised by the block itself propagates unchanged.
      def stream_bytes(url, &block)
        uri = URI.parse(url)
        http = presigned_http(uri)
        download = new_download
        presigned_request(http, download) { stream_body(http, uri, download, block) }
        nil
      end

      private

      def new_download
        { deadline: HTTP.monotonic_now + @timeout, watchdog: nil, in_block: false, first_chunk_in: false }
      end

      # The first-byte watchdog bounds the request, the answer's head and the
      # wait for the first chunk of the body; it is disarmed when that chunk
      # arrives, and `read_timeout` then bounds each wait for the next one.
      # The `ensure` disarms it for an empty body or an error.
      def stream_body(http, uri, download, block)
        watchdog = download[:watchdog] = Watchdog.new(presigned_time_left(download)) { http.finish }
        begin
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            guard_stream!(response)
            response.read_body { |chunk| yield_chunk(download, block, chunk) }
          end
        ensure
          watchdog.disarm
        end
      end

      def yield_chunk(download, block, chunk)
        unless download[:first_chunk_in]
          download[:watchdog].disarm
          download[:first_chunk_in] = true
        end
        download[:in_block] = true
        block.call(chunk)
        download[:in_block] = false
      end

      # Opens the connection within the time left, runs the request, closes
      # the connection, and turns a failure of the download into a
      # `DownloadError`. A `PoliPage::Error` (a non-2xx status) and an error
      # raised by the caller's block go through unchanged.
      def presigned_request(http, download)
        Timeout.timeout(presigned_time_left(download), Net::OpenTimeout) { http.start }
        begin
          yield
        ensure
          http.finish if http.started?
        end
      rescue StandardError => e
        raise if e.is_a?(PoliPage::Error) || download[:in_block]

        raise_download_failure(e, download)
      end

      # Once the watchdog has closed the connection, whatever `Net::HTTP`
      # raises next is that timeout.
      def raise_download_failure(error, download)
        timed_out = download[:watchdog]&.fired? || Transport::SOCKET_TIMEOUTS.any? { |klass| error.is_a?(klass) }
        raise PoliPage::DownloadError.new(timeout: true, cause: error) if timed_out
        raise error unless Transport::NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }

        raise PoliPage::DownloadError.new(cause: error)
      end

      def presigned_time_left(download)
        left = download[:deadline] - HTTP.monotonic_now
        raise Net::OpenTimeout, "the download's timeout has passed" unless left.positive?

        left
      end

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
