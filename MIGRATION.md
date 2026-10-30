# Migration Guide

This file documents breaking changes between releases of `poli-page`
(the Poli Page SDK for Ruby). The SDK follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): while it is on
0.x, a breaking change bumps the minor version; from 1.0 on, only a major
version does. Every breaking release comes with an entry here.

## From 0.10.0 to 0.11.0

The SDK now follows the Poli Page API contract v1.3.0, the same retry policy,
error predicates and messages as every other Poli Page SDK. No method or
option is renamed. Code may need a change where it relied on the renaming
of `data` / `metadata` keys, and in error handling.

### Payload keys are no longer renamed

The SDK specification says `metadata` is sent as is and returned unchanged,
and `data` is the template's own data. The SDK used to camelize every key of
both on the way out and snake_case (and symbolize) every key of `metadata` on
the way back. It no longer touches them; only its own names (`project:`,
`template:`, `doc.page_count`, …) keep their Ruby spelling.

- **`data:`** — write the keys your template uses. If it reads
  `invoiceNumber` and you relied on the conversion, send `invoiceNumber`:

  ```ruby
  # before (converted to invoiceNumber on the wire)
  client.render.pdf(project: "billing", template: "invoice", data: { invoice_number: "INV-001" })

  # now (sent as written)
  client.render.pdf(project: "billing", template: "invoice", data: { invoiceNumber: "INV-001" })
  ```

- **`metadata:`** — sent as written too; send the keys you want stored.
  Reads use the API's String keys:

  ```ruby
  # before
  doc.metadata[:customer_id]

  # now
  doc.metadata["customerId"]
  ```

  Documents rendered before the upgrade keep the keys they were stored with
  (camelCase, since the old SDK converted them).

### Codes that are no longer retried

`QUOTA_EXCEEDED`, `OVERAGE_CAP_EXCEEDED` (429) and `STORAGE_ACCESS_DENIED`
(502) reach you after the first attempt, and `retryable?` is `false` for
them. `DOWNLOAD_FAILED` is never `retryable?`, whatever the storage status.
If you requeued on `retryable?`, these no longer requeue: surface the quota
and the bucket errors instead.

```ruby
rescue PoliPage::Error => e
  case e.code
  when "QUOTA_EXCEEDED", "OVERAGE_CAP_EXCEEDED" then show_banner("Monthly quota reached.")
  when "STORAGE_ACCESS_DENIED"                  then alert_ops("Bucket access revoked.")
  else raise unless e.retryable?
  end
end
```

### Predicates read `status` and `code`

`auth_error?` (401/403), `rate_limit_error?` (429), `validation_error?` (400)
and `network_error?` (`network_error`/`timeout`) no longer look at the class.
The answer only changes for `PoliPage::DownloadError`: a storage 403 (an
expired presigned URL) is now `auth_error?`. Rescuing by class works as
before.

### Messages

Matching on an SDK error's message needs updating; prefer `code`:

| Error | Before | Now |
| --- | --- | --- |
| `InvalidOptionsError` (no key) | `api_key is required` | `apiKey is required` |
| `ConnectionError` | the HTTP library's text | `Network request failed` (`cause` keeps the original) |
| `TimeoutError` | `request timed out after 60s` | `Request timed out after 60000ms` |
| `DownloadError` (status) | `Failed to download: 403 Forbidden` | `Failed to download PDF: HTTP 403` |
| `DownloadError` (no answer) | the HTTP library's text | `Failed to download PDF: network error` |
| non-JSON error body | `HTTP 502: response body was not valid JSON` | `HTTP 502` |

### `format:` and `orientation:` are checked by the API

An unknown `format:` or `orientation:` is no longer refused by the SDK
before the request: the API answers it with `400 VALIDATION_ERROR`.

```ruby
# before
rescue PoliPage::InvalidOptionsError   # "invalid format: ..."

# now
rescue PoliPage::ValidationError => e  # e.code == "VALIDATION_ERROR", e.status == 400
```

To refuse a bad value before any request, check it yourself with
`PoliPage::PageFormat.valid?(format)` and `PoliPage::Orientation.valid?(orientation)`.

### `project:` nil or empty

`render.*` and `render_to_file` raise `InvalidOptionsError` with code
`PROJECT_REQUIRED_FOR_DOCUMENT` before any request, instead of sending the
render and getting a `ValidationError` from the API.

## From 0.9.x to 0.10.0

0.10.0 follows the environments contract: an API key belongs to exactly one
environment of your organization, its text names that environment
(`pp_{env}_{32 lowercase hex}`: `pp_sandbox_…`, `pp_live_…`,
`pp_staging_…`), and a render uses the project's copy published in that
environment. Nobody used the new contract before this release, so every
removal ships at once with no deprecation window.

### API keys

The `pp_test_` and `pp_sa_` prefixes are gone; standard and service keys
share the one format above. Create a key in the environment you render in:
a `sandbox` key replaces a test key (watermarked, not counted toward the
monthly PDF quota, documents expire after 30 days), a `live` key renders
unwatermarked, counted documents. The SDK passes the key through unchanged
and never sends an environment.

### `version:` is removed

`render.pdf`, `render.pdf_stream`, `render.document` and `render_to_file`
no longer take `version:`; passing it raises `ArgumentError` (unknown
keyword) before any request. Publish the project to the key's environment
instead of pinning a version. `DocumentDescriptor#version` is removed too.

```ruby
# 0.9.x
client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: data)

# 0.10.0
client.render.pdf(project: "billing", template: "invoice", data: data)
```

### `render.preview` and inline HTML are removed

`render.preview`, `PreviewResult` and `InlineModeInput` are gone: the API
renders published templates only. Preview a template or render inline HTML
in the playground, <https://play.poli.page>. `documents.preview(id)`, the
stored HTML of a document you already rendered, stays.

### Types

| 0.9.x                                  | 0.10.0                                   |
| -------------------------------------- | ---------------------------------------- |
| `PoliPage::ProjectModeInput`           | `PoliPage::RenderInput`                  |
| `PoliPage::InlineModeInput`            | removed                                  |
| `PoliPage::PreviewResult`              | removed                                  |
| `DocumentDescriptor#version`           | removed                                  |
| `DocumentDescriptor#environment` (`"sandbox"` or `"live"`) | any environment name (`"sandbox"`, `"live"`, `"staging"`, …) |

### Error codes

| 0.9.x code                                                     | 0.10.0                                                        |
| -------------------------------------------------------------- | ------------------------------------------------------------- |
| `GONE`                                                         | `DOCUMENT_GONE` (410)                                         |
| `PAYMENT_REQUIRED`                                             | `ORGANIZATION_PAYMENT_GRACE` (403)                            |
| `VERSION_NOT_FOUND`, `INVALID_VERSION_FORMAT`, `VERSION_REQUIRED`, `INVALID_VERSION_FOR_KEY_ENV` | removed (there is no version); a project or template missing from the key's environment answers `PROJECT_NOT_IN_ENVIRONMENT` or `TEMPLATE_NOT_FOUND` (404) |
| `MISSING_PROJECT_OR_TEMPLATE`                                  | removed                                                       |

`PoliPage::ErrorCodes` gains `PROJECT_NOT_FOUND`, `PROJECT_NOT_IN_ENVIRONMENT`,
`TEMPLATE_NOT_FOUND`, `DOCUMENT_GONE`, `ENVIRONMENT_PROTECTED`,
`PUBLISH_IN_PROGRESS` and the other codes listed in the CHANGELOG. Code that
matches on `e.code` should switch to the new names; code that rescues by
class (`PoliPage::GoneError`, `PoliPage::NotFoundError`, …) keeps working.

### Stored documents

- `documents.thumbnails(id)` no longer checks its options on the client: an
  out-of-bounds `width`, `format`, `quality` or `pages` raises
  `PoliPage::ValidationError` (the API's `400 VALIDATION_ERROR`) instead of
  `PoliPage::InvalidOptionsError`. Every option is optional, and
  `format: "webp"` is accepted.
- `documents.delete(id)` is idempotent: deleting an already-deleted document
  returns `nil` instead of raising `PoliPage::GoneError`. A later
  `documents.get(id)` raises `PoliPage::GoneError` with code `DOCUMENT_GONE`.

## 0.9.0

The first release, published to RubyGems on 2026-06-18. The surface below is
0.9.x's; see [From 0.9.x to 0.10.0](#from-09x-to-0100) for what changed since.

### Surface

```ruby
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

# Render namespace
# render.pdf, render.pdf_stream, render.document → project mode only
# render.preview → accepts both project mode and inline HTML
client.render.pdf(project:, template:, version:, data:, ...)       # → String of bytes
client.render.pdf_stream(project:, template:, ...) { |chunk| ... } # → block or Enumerator
client.render.preview(template:, data:, ...)                       # → PreviewResult
client.render.document(project:, template:, ...)                   # → DocumentDescriptor

# Documents namespace
client.documents.get(id)                  # → DocumentDescriptor
client.documents.preview(id)              # → DocumentPreviewResult { html, page_count }
client.documents.thumbnails(id, **opts)   # → Array<Thumbnail>
client.documents.delete(id)               # → nil

# File helper (instance method on Client)
client.render_to_file(path, project:, template:, version:, data:, ...) # → nil
```

### Method casing

All SDK methods are snake_case (`render.pdf_stream`, `documents.thumbnails`).
Wire JSON uses camelCase; the SDK translates at the transport seam via
`PoliPage::Internal::Wire.to_wire` / `from_wire`. Callers always pass and
receive snake_case kwargs / `Data.define` accessors.

### Errors

Errors are dispatched by class:

```ruby
begin
  client.render.pdf(...)
rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError => e
  refresh_credentials(e)
rescue PoliPage::RateLimitError => e
  queue_for_later(e.request_id)
rescue PoliPage::Error => e
  raise
end
```

Predicate methods (`auth_error?`, `rate_limit_error?`, `validation_error?`,
`network_error?`, `retryable?`) are available on the base class for callers
who prefer `rescue PoliPage::Error => e` with branching.

### MSRV

`required_ruby_version = ">= 3.2"`. Bumps to the MSRV are MINOR-version
releases with a note in this file.
