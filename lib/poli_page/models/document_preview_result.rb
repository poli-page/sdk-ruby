# frozen_string_literal: true

module PoliPage
  # Return value of `client.documents.preview`. Distinct from
  # `PoliPage::PreviewResult`: this carries `page_count` (NOT `total_pages`)
  # because the documents.preview endpoint exposes the page count via the
  # `X-Document-Page-Count` response header on a `text/html` body
  # (sdk-ruby-plan.md §13 Phase 4; mirrors Node `documents.ts:75-77`).
  DocumentPreviewResult = Data.define(:html, :page_count)
end
