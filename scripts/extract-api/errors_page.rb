# frozen_string_literal: true

require "json"

# Build `reference/errors.mdx` — every error class plus every known API
# error code, mirroring the structure in `lib/poli_page/errors.rb`.
module ErrorsPage
  module_function

  SDK_INTERNAL = [
    { code: "PoliPage::InvalidOptionsError", when: "Constructor or method options are missing or malformed. Raised before any HTTP call. Not retryable." },
    { code: "PoliPage::ConnectionError",     when: "TCP/TLS-layer failure reaching the API. Retryable." },
    { code: "PoliPage::TimeoutError",        when: "The request did not complete within the configured `timeout:`. Retryable." },
    { code: "PoliPage::DownloadError",       when: "Failure on the unauthenticated presigned-URL second-hop fetch. Not retried by the SDK." },
    { code: "PoliPage::InternalError",       when: "Unexpected response shape from the API (e.g., non-JSON body)." }
  ].freeze

  API_BY_STATUS = [
    { code: "PoliPage::ValidationError",       when: "HTTP 400 — request body or parameters rejected by the API." },
    { code: "PoliPage::AuthenticationError",   when: "HTTP 401 — missing or invalid API key." },
    { code: "PoliPage::PermissionDeniedError", when: "HTTP 403 — key lacks permission for the requested resource." },
    { code: "PoliPage::NotFoundError",         when: "HTTP 404 — project/template slug or document id does not exist." },
    { code: "PoliPage::GoneError",             when: "HTTP 410 — document deleted, or a sandbox document over 30 days old." },
    { code: "PoliPage::RateLimitError",        when: "HTTP 429 — per-key rate limit or monthly quota reached. Retryable." },
    { code: "PoliPage::APIError",              when: "Any other 4xx / 5xx the SDK does not map to a more specific class." }
  ].freeze

  # Mirrors the constants in PoliPage::ErrorCodes (lib/poli_page/errors.rb).
  API_AUTH = [
    { code: "MISSING_API_KEY",        when: "No API key in the request." },
    { code: "INVALID_API_KEY",        when: "The API key is malformed or revoked." }
  ].freeze

  API_BILLING = [
    { code: "ORGANIZATION_PAYMENT_GRACE", when: "The organization is in payment grace: read-only, writes are refused." },
    { code: "ORGANIZATION_CANCELLED",     when: "The organization has been cancelled: read-only until purge." },
    { code: "ORGANIZATION_PURGED",        when: "The organization has been purged (410)." },
    { code: "ORGANIZATION_MIGRATING",     when: "The organization's storage is being migrated (503). Retryable." },
    { code: "FORBIDDEN",                  when: "Document of another organization, or of another environment than the key's." },
    { code: "ENVIRONMENT_PROTECTED",      when: "documents.delete in a protected environment without role owner or admin." },
    { code: "THUMBNAILS_NOT_AVAILABLE",   when: "documents.thumbnails on the Free tier." }
  ].freeze

  API_NOT_FOUND = [
    { code: "NOT_FOUND",                  when: "Generic not found, e.g. a removed route." },
    { code: "PROJECT_NOT_FOUND",          when: "No project with this slug in the organization." },
    { code: "PROJECT_NOT_IN_ENVIRONMENT", when: "The project was never published in the key's environment, or was removed from it." },
    { code: "TEMPLATE_NOT_FOUND",         when: "The template is absent from the environment's published copy." },
    { code: "DOCUMENT_NOT_FOUND",         when: "No stored document matches the supplied id." },
    { code: "DOCUMENT_GONE",              when: "Deleted document, or sandbox document older than 30 days (410)." }
  ].freeze

  API_VALIDATION = [
    { code: "VALIDATION_ERROR",              when: "Body failed validation: an unknown field, or thumbnail options out of bounds." },
    { code: "MISSING_DATA",                  when: "Request body lacks the required `data` field." },
    { code: "MISSING_TEMPLATE_SLUG",         when: "Template slug is missing." },
    { code: "PROJECT_REQUIRED_FOR_DOCUMENT", when: "render.document was called without `project:`." },
    { code: "TEMPLATE_ERROR",                when: "The engine rejected the template or its data." },
    { code: "EMPTY_DOCUMENT",                when: "The render produced zero pages." },
    { code: "ENVIRONMENT_MISMATCH",          when: "A key caller named another environment. Cannot happen with this SDK." },
    { code: "RENDER_BODY_TOO_LARGE",         when: "Request body over 2 MB (413)." },
    { code: "DOCUMENT_TOO_LARGE",            when: "The document exceeds an engine cap (413)." }
  ].freeze

  API_RATE = [
    { code: "RATE_LIMIT_EXCEEDED",   when: "Over 120 render requests per 60 s for this key. Retryable." },
    { code: "QUOTA_EXCEEDED",        when: "Monthly quota reached. Retryable." },
    { code: "OVERAGE_CAP_EXCEEDED",  when: "Overage cap reached (paid tiers). Retryable." }
  ].freeze

  API_SERVER = [
    { code: "INTERNAL_ERROR",        when: "Unexpected server error. Retryable." },
    { code: "STORAGE_ACCESS_DENIED", when: "The organization's bring-your-own bucket refuses access (502). Retryable." },
    { code: "PUBLISH_IN_PROGRESS",   when: "The project is being published into this environment (503, with Retry-After). Retryable." },
    { code: "RENDER_TIMEOUT",        when: "The engine's time budget expired (504). Retryable." }
  ].freeze

  def build
    <<~MDX
      ---
      title: Errors
      description: Every error class raised by the SDK plus every known API error code.
      ---

      import ErrorTable from '@preset/components/ErrorTable.astro';

      Every failure raised by the SDK is an instance of `PoliPage::Error` (a `StandardError` subclass). Catch a specific subclass when you want narrow handling, or `rescue PoliPage::Error` to handle every SDK failure at once. The error's `#code` reader is the machine-readable string returned by the API.

      ## SDK-internal classes

      Raised before any HTTP call, or in response to a network-layer failure.

      <ErrorTable errors={#{JSON.generate(SDK_INTERNAL)}} />

      ## API error classes (by HTTP status)

      The transport classifies API responses into one of these subclasses based on HTTP status. The `#code` reader carries the machine-readable string from the response body.

      <ErrorTable errors={#{JSON.generate(API_BY_STATUS)}} />

      ## Authentication codes

      <ErrorTable errors={#{JSON.generate(API_AUTH)}} />

      ## Organization state and permission codes

      <ErrorTable errors={#{JSON.generate(API_BILLING)}} />

      ## Not-found codes

      <ErrorTable errors={#{JSON.generate(API_NOT_FOUND)}} />

      ## Validation codes

      <ErrorTable errors={#{JSON.generate(API_VALIDATION)}} />

      ## Rate and quota codes

      <ErrorTable errors={#{JSON.generate(API_RATE)}} />

      ## Server codes

      <ErrorTable errors={#{JSON.generate(API_SERVER)}} />
    MDX
  end
end
