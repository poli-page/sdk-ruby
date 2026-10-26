# frozen_string_literal: true

module PoliPage
  # Return value of `client.documents.preview`: the stored HTML of an
  # already rendered document, with `page_count` read from the
  # `X-Document-Page-Count` response header on a `text/html` body
  # (sdk-ruby-plan.md §13 Phase 4; mirrors Node `documents.ts:75-77`).
  DocumentPreviewResult = Data.define(:html, :page_count)
end
