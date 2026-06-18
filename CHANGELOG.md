# Changelog

All notable changes to `poli-page` (the Poli Page SDK for Ruby) are documented
here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Breaking changes between major versions are summarized in
[MIGRATION.md](MIGRATION.md).

## [Unreleased]

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
