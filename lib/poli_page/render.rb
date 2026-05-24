# frozen_string_literal: true

require_relative "models/preview_result"
require_relative "models/document_descriptor"

module PoliPage
  module Resources
    # `client.render` namespace. Each method captures a back-reference to the
    # parent `PoliPage::Client` and delegates HTTP execution through it
    # (sdk-ruby-plan.md §3.1).
    class Render
      def initialize(client)
        @client = client
      end

      # POST /v1/render/preview — render and return the HTML, total page
      # count, and the environment ("sandbox" / "live") inferred from the
      # API key. Accepts both project mode and inline mode (the only render-*
      # method that does).
      #
      # @return [PoliPage::PreviewResult]
      def preview(template:, data:, project: nil, version: nil, format: nil,
                  orientation: nil, locale: nil, metadata: nil,
                  idempotency_key: nil)
        body = { project: project, template: template, data: data, version: version,
                 format: format, orientation: orientation, locale: locale, metadata: metadata }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER_PREVIEW,
                                      body: body, idempotency_key: idempotency_key)
        PoliPage::PreviewResult.new(**parsed)
      end

      # POST /v1/render — render and store the document, returning a
      # `PoliPage::DocumentDescriptor` with the client back-reference attached
      # so that `#download_pdf` works. Project mode only.
      #
      # @return [PoliPage::DocumentDescriptor]
      def document(project:, template:, data:, version: nil, format: nil,
                   orientation: nil, locale: nil, metadata: nil,
                   idempotency_key: nil)
        body = { project: project, template: template, data: data, version: version,
                 format: format, orientation: orientation, locale: locale, metadata: metadata }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER,
                                      body: body, idempotency_key: idempotency_key)
        parsed[:metadata] ||= {}
        PoliPage::DocumentDescriptor.new(**parsed, _client: @client)
      end

      # Two-hop: render the document, then fetch the presigned PDF URL and
      # return the raw bytes (binary-encoded String). The presigned fetch
      # is unauthenticated and NOT subject to the retry policy.
      #
      # @return [String] raw PDF bytes
      # @raise  [PoliPage::DownloadError] on second-hop failure
      def pdf(project:, template:, data:, version: nil, format: nil,
              orientation: nil, locale: nil, metadata: nil, idempotency_key: nil)
        desc = document(project: project, template: template, data: data,
                        version: version, format: format, orientation: orientation,
                        locale: locale, metadata: metadata, idempotency_key: idempotency_key)
        desc.download_pdf
      end

      # Streaming form of `#pdf`. With a block, yields raw chunks (binary
      # bytes) as they arrive. Without a block, returns an `Enumerator` so
      # the caller can `.each`, `.first(n)`, pipe into `Enumerable` chains,
      # etc.
      #
      # @yieldparam chunk [String] raw bytes
      # @return           [Enumerator, nil]
      # @raise            [PoliPage::DownloadError]
      def pdf_stream(project:, template:, data:, version: nil, format: nil,
                     orientation: nil, locale: nil, metadata: nil, idempotency_key: nil, &block)
        unless block
          return Enumerator.new do |yielder|
            pdf_stream(project: project, template: template, data: data,
                       version: version, format: format, orientation: orientation,
                       locale: locale, metadata: metadata,
                       idempotency_key: idempotency_key) { |chunk| yielder << chunk }
          end
        end

        desc = document(project: project, template: template, data: data,
                        version: version, format: format, orientation: orientation,
                        locale: locale, metadata: metadata, idempotency_key: idempotency_key)
        @client.stream_bytes(desc.presigned_pdf_url, &block)
      end
    end
  end
end
