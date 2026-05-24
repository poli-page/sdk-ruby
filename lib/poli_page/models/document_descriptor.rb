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
    :version,
    :environment,        # "sandbox" or "live"
    :api_key_id,
    :format,
    :orientation,        # nullable
    :locale,             # nullable
    :page_count,
    :size_bytes,
    :created_at,         # ISO 8601 String — not parsed (no extra deps)
    :metadata,           # Hash; SDK normalises nil → {} after from_wire
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
end
