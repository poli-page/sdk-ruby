# frozen_string_literal: true

module PoliPage
  module Internal
    # Internal constants. Convention-private; do not depend on these from
    # outside the gem (no semver protection).
    module Constants
      # API paths (relative to the configured base URL).
      PATH_RENDER          = "/v1/render"
      PATH_RENDER_PREVIEW  = "/v1/render/preview"
      PATH_DOCUMENTS       = "/v1/documents"

      # Defaults (in seconds where applicable — Ruby's `Kernel#sleep`,
      # `Net::HTTP#open_timeout`, etc. all use seconds).
      DEFAULT_BASE_URL     = "https://api.poli.page"
      DEFAULT_MAX_RETRIES  = 2
      DEFAULT_RETRY_DELAY  = 0.5      # Node: 500 ms.
      DEFAULT_TIMEOUT      = 60       # Node: 60_000 ms.
      RETRY_AFTER_CAP      = 30       # Node: 30_000 ms.

      # Header names (lowercase form — Net::HTTP normalises to lowercase on
      # the way back; matches the Node `x-request-id` convention).
      HEADER_AUTHORIZATION   = "Authorization"
      HEADER_ACCEPT          = "Accept"
      HEADER_CONTENT_TYPE    = "Content-Type"
      HEADER_USER_AGENT      = "User-Agent"
      HEADER_IDEMPOTENCY_KEY = "Idempotency-Key"
      HEADER_REQUEST_ID      = "x-request-id"
      HEADER_RETRY_AFTER     = "retry-after"

      # Document-preview response header carrying the page count
      # (mirrors Node `documents.ts:75-77`).
      HEADER_DOCUMENT_PAGE_COUNT = "x-document-page-count"
    end
  end
end
