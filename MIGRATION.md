# Migration Guide

This file documents breaking changes between major versions of `poli-page`
(the Poli Page SDK for Ruby). The SDK follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html): breaking changes
only ship in major version bumps and always come with an entry here.

## 1.0

The first stable release. No prior versions of `poli-page` were published to
RubyGems — treat `1.0.0` as the starting point.

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
