# frozen_string_literal: true

require "uri"

require_relative "models/document_descriptor"
require_relative "models/document_preview_result"
require_relative "models/thumbnail"

module PoliPage
  module Resources
    # `client.documents` namespace (sdk-ruby-plan.md §13 Phase 4, port of
    # sdk-node/src/documents.ts).
    class Documents
      def initialize(client)
        @client = client
      end

      # GET /v1/documents/:id — returns a `DocumentDescriptor` with the
      # client back-reference attached so `#download_pdf` works.
      #
      # @return [PoliPage::DocumentDescriptor]
      def get(id)
        parsed = @client.execute_get(path_for(id))
        parsed[:metadata] ||= {}
        PoliPage::DocumentDescriptor.new(**parsed, _client: @client)
      end

      # GET /v1/documents/:id/preview — returns the stored paginated HTML
      # plus the page count carried by the `X-Document-Page-Count` response
      # header. The body is `text/html`, NOT a JSON envelope (mirrors Node
      # `documents.ts:75-77`).
      #
      # @return [PoliPage::DocumentPreviewResult]
      def preview(id)
        response = @client.execute_get_raw("#{path_for(id)}/preview")
        page_count_header = response.headers[Internal::Constants::HEADER_DOCUMENT_PAGE_COUNT]
        page_count = page_count_header.to_s.match?(/\A\d+\z/) ? page_count_header.to_i : 0
        PoliPage::DocumentPreviewResult.new(html: response.body.to_s, page_count: page_count)
      end

      # POST /v1/documents/:id/thumbnails — the deployed API expects the
      # options nested under a `thumbnails` key. The response envelope
      # `{ thumbnails: [...] }` is unwrapped here.
      #
      # @return [Array<PoliPage::Thumbnail>]
      def thumbnails(id, **options)
        body = { thumbnails: options.compact }
        parsed = @client.execute_post("#{path_for(id)}/thumbnails", body: body)
        parsed[:thumbnails].map { |t| PoliPage::Thumbnail.new(**t) }
      end

      # DELETE /v1/documents/:id — returns nil. Re-deleting an
      # already-deleted document surfaces as `PoliPage::GoneError` (HTTP
      # 410) — no special handling here.
      def delete(id)
        @client.execute_delete(path_for(id))
        nil
      end

      private

      # Ruby 3.2+ `URI.encode_uri_component` matches JS `encodeURIComponent`
      # (used by sdk-node). `CGI.escape` would form-encode spaces as `+`,
      # which the deployed API rejects in path segments.
      def path_for(id)
        "#{Internal::Constants::PATH_DOCUMENTS}/#{URI.encode_uri_component(id)}"
      end
    end
  end
end
