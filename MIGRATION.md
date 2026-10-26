# Migration Guide

This file documents breaking changes between releases of `poli-page`
(the Poli Page SDK for Ruby). The SDK follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): while it is on
0.x, a breaking change bumps the minor version; from 1.0 on, only a major
version does. Every breaking release comes with an entry here.

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
