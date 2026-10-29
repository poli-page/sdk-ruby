# frozen_string_literal: true

module PoliPage
  module Internal
    # @api private
    #
    # Internal constants. Convention-private; do not depend on these from
    # outside the gem (no semver protection).
    module Constants
      # API paths (relative to the configured base URL).
      PATH_RENDER          = "/v1/render"
      PATH_DOCUMENTS       = "/v1/documents"

      # Defaults (in seconds where applicable — Ruby's `Kernel#sleep`,
      # `Net::HTTP#open_timeout`, etc. all use seconds).
      DEFAULT_BASE_URL     = "https://api.poli.page"
      DEFAULT_MAX_RETRIES  = 2
      DEFAULT_RETRY_DELAY  = 0.5      # Node: 500 ms.
      DEFAULT_TIMEOUT      = 60       # Node: 60_000 ms.
      RETRY_AFTER_CAP      = 30       # Node: 30_000 ms.

      # API codes the SDK never retries, whatever the status or `Retry-After`
      # (sdk-specification.md §9.1): they last until the monthly reset or until
      # the bucket access is restored.
      NON_RETRYABLE_CODES = %w[QUOTA_EXCEEDED OVERAGE_CAP_EXCEEDED STORAGE_ACCESS_DENIED].freeze

      # SDK error messages: exact texts of sdk-specification.md §8.3, the same
      # in every SDK (the API contract's `policy.sdkErrors` compares them).
      MESSAGE_INVALID_OPTIONS         = "apiKey is required"
      MESSAGE_NETWORK_ERROR           = "Network request failed"
      MESSAGE_TIMEOUT                 = "Request timed out after %<timeout_ms>dms"
      MESSAGE_DOWNLOAD_FAILED         = "Failed to download PDF: HTTP %<status>d"
      MESSAGE_DOWNLOAD_FAILED_NETWORK = "Failed to download PDF: network error"
      MESSAGE_PROJECT_REQUIRED        = "project is required"

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
