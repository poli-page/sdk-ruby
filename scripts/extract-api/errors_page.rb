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
    { code: "PoliPage::GoneError",             when: "HTTP 410 — resource existed but was deleted." },
    { code: "PoliPage::RateLimitError",        when: "HTTP 429 — per-key rate limit or monthly quota reached. Retryable." },
    { code: "PoliPage::APIError",              when: "Any other 4xx / 5xx the SDK does not map to a more specific class." }
  ].freeze

  # Mirrors the constants in PoliPage::ErrorCodes (lib/poli_page/errors.rb).
  API_AUTH = [
    { code: "MISSING_API_KEY",        when: "No API key in the request." },
    { code: "INVALID_API_KEY",        when: "The API key is malformed or revoked." }
  ].freeze

  API_BILLING = [
    { code: "PAYMENT_REQUIRED",        when: "Organization billing is past due." },
    { code: "FORBIDDEN",               when: "The key does not have access to the requested resource." },
    { code: "ORGANIZATION_CANCELLED",  when: "The organization has been cancelled." },
    { code: "ORGANIZATION_PURGED",     when: "The organization has been purged." }
  ].freeze

  API_NOT_FOUND = [
    { code: "NOT_FOUND",           when: "The project/template slug does not exist or is not published." },
    { code: "VERSION_NOT_FOUND",   when: "The pinned version does not exist for this template." },
    { code: "DOCUMENT_NOT_FOUND",  when: "No stored document matches the supplied id." },
    { code: "GONE",                when: "The resource existed but has been deleted." }
  ].freeze

  API_VALIDATION = [
    { code: "VALIDATION_ERROR",              when: "`data` does not satisfy the template schema." },
    { code: "MISSING_DATA",                  when: "Request body lacks the required `data` field." },
    { code: "MISSING_PROJECT_OR_TEMPLATE",   when: "Project mode call without both `project` and `template`." },
    { code: "MISSING_TEMPLATE_SLUG",         when: "Template slug is missing." },
    { code: "PROJECT_REQUIRED_FOR_DOCUMENT", when: "render.document was called without `project:`." },
    { code: "INVALID_VERSION_FORMAT",        when: "The `version` string is not a valid semver." },
    { code: "VERSION_REQUIRED",              when: "Live keys require a pinned `version`." },
    { code: "INVALID_VERSION_FOR_KEY_ENV",   when: "Sandbox key targeting a live-only version, or vice versa." }
  ].freeze

  API_RATE = [
    { code: "QUOTA_EXCEEDED",        when: "Per-key rate limit or monthly quota reached. Retryable." },
    { code: "OVERAGE_CAP_EXCEEDED",  when: "Hard overage cap reached. Not retryable." }
  ].freeze

  API_SERVER = [
    { code: "INTERNAL_ERROR", when: "The API returned 5xx. Retryable." }
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

      ## Billing and lifecycle codes

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
