# frozen_string_literal: true

module PoliPage
  # The stored-document descriptor returned by `client.render.document` and
  # the `client.documents.*` methods. Carries every wire field plus an
  # SDK-attached `_client` back-reference used by `#download_pdf`.
  #
  # The `_client` field is hidden from `#to_h` and `#inspect` so it doesn't
  # leak into logs or marshalled representations (sdk-ruby-plan.md §3.4).
  DocumentDescriptor = Data.define(
    :document_id,
    :organization_id,
    :project_id,         # nullable on the wire
    :project_slug,
    :template_id,
    :template_slug,
    :environment,        # any environment name ("sandbox", "live", "staging", ...)
    :api_key_id,
    :format,
    :orientation,        # nullable
    :locale,             # nullable
    :page_count,
    :size_bytes,
    :created_at,         # ISO 8601 String — not parsed (no extra deps)
    :metadata,           # Hash with the API's String keys, exactly as stored; nil → {}
    :presigned_pdf_url,
    :expires_at,         # ISO 8601 String
    :_client             # SDK back-reference; not part of the wire shape
  ) do
    # Fetch the PDF bytes from `presigned_pdf_url`. The URL has a ~15-minute
    # TTL — if it expired, call `client.documents.get(document_id)` to
    # refresh and retry.
    #
    # @return [String] raw PDF bytes (binary-encoded)
    # @raise  [PoliPage::DownloadError] on non-2xx or network failure
    # @raise  [PoliPage::InternalError] if the descriptor lacks a client back-reference
    def download_pdf
      raise PoliPage::InternalError, "DocumentDescriptor missing client back-reference" if _client.nil?

      _client.fetch_bytes(presigned_pdf_url)
    end

    def to_h
      super.except(:_client)
    end

    def inspect
      "#<PoliPage::DocumentDescriptor document_id=#{document_id.inspect} ...>"
    end
  end

  class << DocumentDescriptor
    # Build a descriptor from a parsed `POST /v1/render` or
    # `GET /v1/documents/:id` body. Fields this SDK does not know are
    # ignored, so the API can add fields without breaking the strict
    # `Data.define` constructor.
    #
    # @api private
    # @param parsed [Hash{Symbol=>Object}] snake_case-symbol-keyed body
    # @param client [PoliPage::Client]
    # @return [PoliPage::DocumentDescriptor]
    def from_wire(parsed, client:)
      fields = parsed.slice(*members)
      fields[:metadata] ||= {}
      fields[:_client] = client
      new(**fields)
    end
  end
end
