# Changelog

All notable changes to `poli-page` (the Poli Page SDK for Ruby) are documented
here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Breaking releases (minor bumps while on 0.x) are summarized in
[MIGRATION.md](MIGRATION.md).

## [Unreleased]

Conformance with the Poli Page API contract v1.2.0
([poli-page/api-contract](https://github.com/poli-page/api-contract)). See
[MIGRATION.md](MIGRATION.md#from-0100-to-the-next-release-unreleased).

### Changed

- **BREAKING**: the keys inside `data:` and `metadata:` are no longer
  renamed. They are sent exactly as you write them, at every depth: before,
  every key was camelized (`data: { invoice_number: 1 }` reached the template
  as `invoiceNumber`). `DocumentDescriptor#metadata` is returned exactly as
  the API stored it, with its String keys: before, every key was snake_cased
  and symbolized (`{ "customerId" => "c" }` came back as
  `{ customer_id: "c" }`), and two keys such as `someKey` and `some_key`
  collided. The SDK's own names (`project`, `template`, the descriptor's
  readers, the thumbnail options…) keep their Ruby spelling. See
  [MIGRATION.md](MIGRATION.md#payload-keys-are-no-longer-renamed).
- **BREAKING**: `QUOTA_EXCEEDED` and `OVERAGE_CAP_EXCEEDED` (429) and
  `STORAGE_ACCESS_DENIED` (502) are no longer retried, even with a
  `Retry-After` header, and `retryable?` returns `false` for them (it
  returned `true` for any 429 or 5xx). They last until the monthly reset or
  until the bucket access is restored, so the SDK used to wait up to 30 s per
  retry for nothing. `RATE_LIMIT_EXCEEDED` and every other 429 and 5xx are
  still retried. Code that requeues on `retryable?` stops requeueing these
  three.
- **BREAKING**: `retryable?` is `false` for every `DOWNLOAD_FAILED`
  (`PoliPage::DownloadError`), whatever the storage status: it was `true`
  with a storage 5xx or 429. The SDK never retried the download itself, and
  still does not.
- **BREAKING**: the error predicates read `status` and `code`, as the SDK
  specification defines them, instead of the error class: `auth_error?` is
  `status` 401 or 403, `rate_limit_error?` 429, `validation_error?` 400, and
  `network_error?` is `code` `network_error` or `timeout`. For API errors
  only the never-retried codes above change. A `DownloadError` now follows
  the storage's status: a 401 or 403 is an auth error (an expired presigned
  URL gets 403), a 429 a rate-limit error and a 400 a validation error; all
  three were `false` before.
- **BREAKING**: SDK error messages are the exact texts of the SDK
  specification, the same in every Poli Page SDK:
  - `invalid_options`: `apiKey is required` (was `api_key is required`).
  - `network_error` (`ConnectionError`): `Network request failed` (was the
    HTTP library's exception text, which stays available as `cause`).
  - `timeout` (`TimeoutError`): `Request timed out after <ms>ms`, the
    client's `timeout` in milliseconds (was `request timed out after <s>s`).
    `TimeoutError#timeout` is still in seconds.
  - `DOWNLOAD_FAILED`: `Failed to download PDF: HTTP <status>` (was
    `Failed to download: <status> <reason phrase>`), and
    `Failed to download PDF: network error` when the download gets no
    complete answer (was the HTTP library's text, now `cause`).
  - An error answer whose body is not JSON: `HTTP <status>` (was
    `HTTP <status>: response body was not valid JSON`); the code is still
    `INTERNAL_ERROR` with the real status.
  - `DownloadError.new` takes `status:` and `cause:` and builds its message
    from them; `message:` is optional. `ConnectionError.new`'s `message:` is
    optional too.
- **BREAKING**: `format:` and `orientation:` are no longer checked before the
  request (SDK specification §5.4: the SDK validates nothing else
  client-side). A value outside `PoliPage::PageFormat::FORMATS` or
  `portrait`/`landscape` is sent as given, and the API answers it with
  `PoliPage::ValidationError` (`400 VALIDATION_ERROR`) instead of the SDK
  raising `PoliPage::InvalidOptionsError` (`invalid_options`, which the
  specification keeps for the constructor). `PageFormat.valid?` and
  `Orientation.valid?` stay for callers who check their own input.
- `render.document`, `render.pdf`, `render.pdf_stream` and `render_to_file`
  raise `PoliPage::InvalidOptionsError` with code
  `PROJECT_REQUIRED_FOR_DOCUMENT` and message `project is required` before
  any request when `project:` is nil or empty (it was sent, and the API
  answered `400`).
- `Retry-After` is read as integer seconds or an HTTP-date (IMF-fixdate,
  RFC 850 or asctime) only, clamped to 0–30 s; a date's delay keeps its
  sub-second rest instead of being rounded down to whole seconds. Any other
  value (`1.5`, `-1`, `soon`) falls back to the backoff. `Retry-After-Ms` is
  ignored, as before.
- The client's `timeout` is one deadline for each whole attempt: opening the
  connection (DNS, TCP, a proxy's `CONNECT`, the TLS handshake), the request
  and the answer, body included. Before, it applied to each phase and each
  socket operation on its own, so a slow connection followed by a slow TLS
  handshake, or an answer that kept sending a byte now and then, could
  outlive it while the error still named `timeout`. The connection phase is
  now bounded by the time left, and a per-attempt watchdog thread closes the
  connection at the deadline.
- An answer's whole body is read inside its attempt. A 2xx cut mid-body is a
  `network_error` (`Network request failed`, the read error as `cause`), and
  one that stalls past `timeout` a `timeout`; both are retried. A 2xx body
  shorter than its `Content-Length` used to be accepted, then failed as
  `INTERNAL_ERROR` ("response body was not valid JSON"). A render whose 2xx
  answer is cut was already stored by the API, so its retry can store a
  second document.
- An error answer whose body fails while it is read is handled as a body
  that is not JSON: `INTERNAL_ERROR`, `HTTP <status>`, the real status and
  `x-request-id`, the read error as `cause`, and retried by its status (a 503
  yes, a 400 no). It never takes a code from the bytes received so far.
- `on_response` fires once the 2xx body is read, and never for a 2xx whose
  body failed.
- `PoliPage::Error#initialize` takes `cause:`; `Error#cause` returns it even
  when the error is raised outside the `rescue` that caught the original.
  Network errors, timeouts and download failures carry the HTTP library's
  exception there.
- `documents.preview` returns its HTML as a UTF-8 string, read in the
  `charset` of its `Content-Type` (UTF-8 when there is none). It was binary,
  `ASCII-8BIT`, so any non-ASCII character compared unequal to a UTF-8
  string.
- A 2xx whose body is not a JSON object (not JSON, empty, absent, or another
  JSON value) still raises `INTERNAL_ERROR`, not retried, but now fires
  `on_error` first, like every error the SDK raises, and keeps the parser's
  error as `cause`. An absent body raised a raw `TypeError` and a JSON array a
  raw `NoMethodError`.
- `documents.thumbnails` ignores thumbnail fields the SDK does not know,
  instead of raising `ArgumentError`, so the API can add fields.

### Fixed

- A GET or DELETE (`documents.get`, `documents.preview`, `documents.delete`)
  and the presigned-URL download are never sent again behind the SDK's
  back. `Net::HTTP` resends an idempotent request once by itself
  (`max_retries`, default 1) after a dropped connection, a read error or a
  read timeout: that attempt was not counted by the SDK's `max_retries` nor
  reported to `on_request`, a timed-out attempt lasted twice the `timeout`
  its error named, and the download, which must not be retried, could be
  fetched twice. The SDK now sets `max_retries = 0` on every connection.
  `Net::HTTP` never resent a POST by itself.
- A dropped connection (`EOFError`, `IOError`, `Errno::EPIPE`, …) was not
  translated and escaped as the raw Ruby exception, outside the retry loop;
  it is now a retried `network_error`. A dropped or timed-out download is
  `DOWNLOAD_FAILED`.
- A retry wait is never shorter than its delay: when `sleep` returns early,
  the SDK sleeps again for the rest, on the monotonic clock.
- An error raised by the caller's `pdf_stream` block (for example
  `Errno::ENOSPC` from writing the chunk) propagates unchanged instead of
  being wrapped.
- Docs: the retries page no longer claims the API deduplicates on
  `Idempotency-Key`. It does not: the key is stable across the retries of one
  call, and a render retried after a late 5xx, a `timeout` or a
  `network_error` can store a second document. The errors docs no longer
  list `QUOTA_EXCEEDED`, `OVERAGE_CAP_EXCEEDED` and `STORAGE_ACCESS_DENIED`
  as retried.

### Added

- Known error code `TEMPLATE_UNSAFE` (400: the template, a partial or an SVG
  asset holds an injection attempt; the message names it; not retried), next
  to `TEMPLATE_ERROR`.
- `spec/contract` runs every SDK case of the API contract against a local
  mock server over real sockets; CI pins the contract by commit
  (`poli-page/api-contract` action) and Dependabot proposes each new version.
  Run it locally with `POLI_CONTRACT=<path to contract.json> bundle exec rspec`.

## [0.10.0] - 2026-10-27

Environments contract: an API key carries its environment (`pp_{env}_…`,
e.g. `pp_sandbox_…`, `pp_live_…`, `pp_staging_…`) and a render uses the
project's copy published in that environment. Breaking, with no deprecation
window.

### Removed

- **BREAKING**: **`render.preview`** and its **`PreviewResult`** type. The
  API removed `POST /v1/render/preview` (a call now gets `404`).
  `documents.preview(id)` stays.
- **BREAKING**: **Inline mode**: the `InlineModeInput` type and raw HTML in
  `template:`. `template:` is always a slug.
- **BREAKING**: The **`version:`** keyword of `render.document`,
  `render.pdf`, `render.pdf_stream` and `render_to_file`, and with it draft
  rendering by an API key. Passing `version:` now raises `ArgumentError`.
- **BREAKING**: The **`version`** field of `DocumentDescriptor`.
- **BREAKING**: From `PoliPage::ErrorCodes`: `VERSION_NOT_FOUND`,
  `INVALID_VERSION_FORMAT`, `VERSION_REQUIRED`, `INVALID_VERSION_FOR_KEY_ENV`,
  `MISSING_PROJECT_OR_TEMPLATE`, `GONE` (the API answers `410 DOCUMENT_GONE`)
  and `PAYMENT_REQUIRED` (payment grace is `403 ORGANIZATION_PAYMENT_GRACE`).

### Changed

- **BREAKING**: `ProjectModeInput` is renamed **`RenderInput`** and is the
  only input type.
- The render body is built from the seven documented fields only
  (`project`, `template`, `data`, `metadata`, `format`, `orientation`,
  `locale`); unset optional fields are omitted. The SDK never sends an
  environment: the API resolves it from the key.
- `DocumentDescriptor#environment` is any environment name (`sandbox`,
  `live`, `staging`, …), returned unchanged. Response fields the SDK does not
  know are ignored instead of failing the `Data.define` constructor.
- `documents.thumbnails(id)` takes optional options: `width:` is no longer
  required (API default 400) and `format:` accepts `"webp"` (API default
  `"jpeg"`). With no option set the body is `{}`. `ThumbnailOptions.new`
  takes every field as optional.
- **BREAKING**: `documents.thumbnails(id)` no longer pre-checks `width`,
  `format`, `quality` or `pages`: an out-of-bounds option raises
  `PoliPage::ValidationError` (the API's `400 VALIDATION_ERROR`) instead of
  `PoliPage::InvalidOptionsError` before the request.
- `documents.delete` is documented as idempotent: the API answers `204` again
  for an already-deleted document, so a re-delete returns `nil`.
- README, docs site and `examples/demo.rb` follow the environments contract:
  the quick start and the demo render `getting-started`/`welcome` with a
  `sandbox` key and no version, "Authentication & environments" carries the
  key table and the key regex, and previews point to the playground
  (<https://play.poli.page>). The demo checks a pasted key against the key
  regex only and its last step is `not-found` (`404 TEMPLATE_NOT_FOUND`).
- The nightly integration workflow no longer passes a template version; it
  renders `getting-started`/`welcome` with the `POLI_PAGE_API_KEY` secret (a
  `pp_sandbox_` key).
- `MIGRATION.md` has a "From 0.9.x to 0.10.0" entry.

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
