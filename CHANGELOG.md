# Changelog

All notable changes to `poli-page` (the Poli Page SDK for Ruby) are documented
here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Breaking changes between major versions are summarized in
[MIGRATION.md](MIGRATION.md).

## [Unreleased]

Environments contract: an API key carries its environment (`pp_{env}_…`,
e.g. `pp_sandbox_…`, `pp_live_…`, `pp_staging_…`) and a render uses the
project's copy published in that environment. Breaking, with no deprecation
window.

### Removed

- **`render.preview`** and its **`PreviewResult`** type. The API removed
  `POST /v1/render/preview` (a call now gets `404`). `documents.preview(id)`
  stays.
- **Inline mode**: the `InlineModeInput` type and raw HTML in `template:`.
  `template:` is always a slug.
- The **`version:`** keyword of `render.document`, `render.pdf`,
  `render.pdf_stream` and `render_to_file`, and with it draft rendering by an
  API key. Passing `version:` now raises `ArgumentError`.
- The **`version`** field of `DocumentDescriptor`.
- From `PoliPage::ErrorCodes`: `VERSION_NOT_FOUND`, `INVALID_VERSION_FORMAT`,
  `VERSION_REQUIRED`, `INVALID_VERSION_FOR_KEY_ENV`,
  `MISSING_PROJECT_OR_TEMPLATE`, `GONE` (the API answers `410 DOCUMENT_GONE`)
  and `PAYMENT_REQUIRED` (payment grace is `403 ORGANIZATION_PAYMENT_GRACE`).

### Changed

- `ProjectModeInput` is renamed **`RenderInput`** and is the only input type.
- The render body is built from the seven documented fields only
  (`project`, `template`, `data`, `metadata`, `format`, `orientation`,
  `locale`); unset optional fields are omitted. The SDK never sends an
  environment: the API resolves it from the key.
- `DocumentDescriptor#environment` is any environment name (`sandbox`,
  `live`, `staging`, …), returned unchanged. Response fields the SDK does not
  know are ignored instead of failing the `Data.define` constructor.
- `documents.thumbnails(id)` takes optional options: `width:` is no longer
  required (API default 400), `format:` accepts `"webp"` (API default
  `"jpeg"`), and the SDK no longer pre-checks `width`, `format`, `quality` or
  `pages` (the API answers `400 VALIDATION_ERROR`). With no option set the
  body is `{}`. `ThumbnailOptions.new` takes every field as optional.
- `documents.delete` is documented as idempotent: the API answers `204` again
  for an already-deleted document, so a re-delete returns `nil`.

### Added

- `PoliPage::ErrorCodes`: `PUBLISH_IN_PROGRESS` (503, retried),
  `ENVIRONMENT_MISMATCH` (400), `PROJECT_NOT_IN_ENVIRONMENT` (404),
  `TEMPLATE_NOT_FOUND` (404), `DOCUMENT_GONE` (410), `ENVIRONMENT_PROTECTED`
  (403), `ORGANIZATION_PAYMENT_GRACE` (403), `EMPTY_DOCUMENT` (400),
  `STORAGE_ACCESS_DENIED` (502), `ORGANIZATION_MIGRATING` (503),
  `PROJECT_NOT_FOUND` (404), `TEMPLATE_ERROR` (400),
  `THUMBNAILS_NOT_AVAILABLE` (403), `RATE_LIMIT_EXCEEDED` (429),
  `RENDER_BODY_TOO_LARGE` (413), `DOCUMENT_TOO_LARGE` (413) and
  `RENDER_TIMEOUT` (504): 31 known API codes in all. The list stays open:
  `Error#code` is whatever string the API returns.
- A render held by a publish of the same project and environment gets
  `503 PUBLISH_IN_PROGRESS` with `Retry-After`; the existing retry policy
  retries it after that delay.

## [0.9.1] - 2026-06-22

### Fixed

- Declare `base64` as a runtime dependency. The SDK hands back base64-encoded
  thumbnail data (decoded by consumers with `Base64.decode64`) and ships an
  example that requires `base64`; on Ruby 3.4+, where `base64` is no longer a
  default gem, this surfaced as `LoadError -- base64` without the dependency.

## [0.9.0] - 2026-06-18

### Added — first release

- **`PoliPage::Client`** with `render` and `documents` namespaces, sync
  retry loop, hook firing, and thread-safe accessors.
- **`render.pdf`**, **`render.pdf_stream`** (block + Enumerator forms),
  **`render.preview`**, **`render.document`**.
- **`documents.get`**, **`documents.preview`**, **`documents.thumbnails`**,
  **`documents.delete`**.
- **`Client#render_to_file`** — streams the PDF straight to disk with
  bounded memory.
- **`DocumentDescriptor#download_pdf`** — fluent helper that fetches the
  PDF bytes from the descriptor's presigned URL.
- **Class hierarchy errors** rooted at `PoliPage::Error < StandardError`:
  `ValidationError` (400), `AuthenticationError` (401),
  `PermissionDeniedError` (403), `NotFoundError` (404), `GoneError` (410),
  `RateLimitError` (429), `APIError` (other 4xx/5xx),
  `InvalidOptionsError`, `ConnectionError`, `TimeoutError`,
  `DownloadError`, `InternalError`. Predicate helpers
  (`auth_error?`/`rate_limit_error?`/`validation_error?`/
  `network_error?`/`retryable?`) for users who prefer a single
  `rescue PoliPage::Error => e` clause.
- **`PoliPage::ErrorCodes`** module with the 21 known API code constants.
- **Auto retry** on 5xx, 429, network errors, and timeouts. Exponential
  backoff with jitter in `[0.5, 1.5)`; honours `Retry-After` (integer
  seconds or HTTP-date), capped at 30 s.
- **Auto-generated `Idempotency-Key`** (UUID v4) on every POST; override
  via per-call `idempotency_key:` kwarg.
- **Observability hooks**: `on_retry:` (receives `PoliPage::RetryEvent`)
  and `on_error:` (receives the `PoliPage::Error` directly). Hook
  exceptions never break the request.
- **Frozen `Data.define` value objects** for inputs and responses:
  `PreviewResult`, `DocumentDescriptor`, `DocumentPreviewResult`,
  `Thumbnail`, `ProjectModeInput`, `InlineModeInput`, `ThumbnailOptions`,
  `RetryEvent`.
- **`PageFormat::FORMATS`** and **`Orientation::ORIENTATIONS`** — frozen
  `Set`s of valid strings with `.valid?` predicates.
- **Zero runtime dependencies** — stdlib `Net::HTTP`, `JSON`, `URI`,
  `SecureRandom`, `Logger` only.
- **RBS signatures** under `sig/` for the public surface; checked via
  `bundle exec steep check` and `bundle exec rbs validate`.
- **YARD `@example` blocks** on every public method.
- **CI matrix**: Ruby 3.2 / 3.3 / 3.4 on Ubuntu, plus one job each on
  macOS and Windows with 3.4. RuboCop + Steep + RSpec + bundler-audit
  + gem build + install smoke.

### Requirements

Ruby >= 3.2.
