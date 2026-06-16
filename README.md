# Poli Page SDK for Ruby

[![Gem Version](https://badge.fury.io/rb/poli-page.svg)](https://rubygems.org/gems/poli-page)
[![CI](https://github.com/poli-page/sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/poli-page/sdk-ruby/actions/workflows/ci.yml)
[![CodeQL](https://github.com/poli-page/sdk-ruby/actions/workflows/codeql.yml/badge.svg)](https://github.com/poli-page/sdk-ruby/actions/workflows/codeql.yml)
[![codecov](https://codecov.io/gh/poli-page/sdk-ruby/branch/main/graph/badge.svg)](https://codecov.io/gh/poli-page/sdk-ruby)
[![Ruby](https://img.shields.io/badge/ruby-3.2%20%7C%203.3%20%7C%203.4-CC342D?logo=ruby&logoColor=white)](https://github.com/poli-page/sdk-ruby/blob/main/.github/workflows/ci.yml)
[![RBS](https://img.shields.io/badge/types-RBS-blue?logo=ruby&logoColor=white)](https://github.com/poli-page/sdk-ruby/tree/main/sig)
[![Docs](https://img.shields.io/badge/docs-online-brightgreen)](https://poli-page.github.io/sdk-ruby/)
[![License](https://img.shields.io/github/license/poli-page/sdk-ruby.svg)](LICENSE)

Official Ruby SDK for [Poli Page](https://poli.page) — render polished PDFs
from HTML templates via the Poli Page API.

→ **Documentation**: <https://poli-page.github.io/sdk-ruby/>

## Install

```ruby
# Gemfile
gem "poli-page"
```

```sh
bundle install
# or
gem install poli-page
```

Requires Ruby **>= 3.2**.

The gem has **zero runtime dependencies** — only the stdlib (`net/http`,
`json`, `uri`, `securerandom`, `logger`, `openssl`).

## Quick start

### Project mode — render a published template by slug

```ruby
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

pdf = client.render.pdf(
  project:  "getting-started",
  template: "welcome",
  version:  "1.0.0",
  data:     { name: "World" }
)
# pdf is a binary-encoded String
```

Every Poli Page org comes pre-provisioned with a `getting-started/welcome`
template, so the snippet above runs as-is the moment you have an API key —
no project setup needed. For your own templates, swap the slugs once
you've pushed a version with the `poli` CLI:

```ruby
pdf = client.render.pdf(
  project:  "billing",
  template: "invoice",
  version:  "1.0.0",
  data:     { invoice_number: "INV-001", total: 1280 }
)
```

### Preview inline HTML

`render.preview` accepts raw HTML for live editing and visual inspection
without producing a stored document. Use this for editor previews or
layout tests.

```ruby
result = client.render.preview(
  template: "<h1>Hello {{ name }}</h1>",
  data:     { name: "World" }
)
puts "Rendered #{result.total_pages} page(s) in #{result.environment} mode"
```

`render.pdf`, `render.pdf_stream`, and `render.document` **require project
mode** — `project` + `template`, optionally pinned to a specific
`version` (omit to render the current draft). Inline HTML is only
accepted by `render.preview`.

### Write a PDF to disk

```ruby
client.render_to_file(
  "./welcome.pdf",
  project: "getting-started", template: "welcome", version: "1.0.0",
  data:    { name: "World" }
)
```

`render_to_file` streams the response bytes directly to disk via
`render.pdf_stream` — bounded memory regardless of PDF size. Parent
directories are created on the fly.

### Try it locally — runnable demo

```sh
ruby examples/demo.rb
```

The demo walks every public method end-to-end and writes the results to
`examples/output/`. First run prompts for a `pp_test_*` key and saves it
to `.env` at the project root. Subsequent runs are silent. The `POLI_PAGE_API_KEY`
env var wins over the file when set.

### Stream — for large PDFs or piping to S3 / HTTP responses

```ruby
File.open("invoice.pdf", "wb") do |io|
  client.render.pdf_stream(
    project: "billing", template: "invoice", version: "1.0.0",
    data:    { invoice_number: "INV-001" }
  ) do |chunk|
    io.write(chunk)
  end
end
```

Without a block, `pdf_stream` returns an `Enumerator` that composes with
`Enumerable`:

```ruby
enum = client.render.pdf_stream(project: "billing", template: "invoice", version: "1.0.0", data: data)
enum.each { |chunk| s3.upload_part(part_number: n += 1, body: chunk) }
```

## Working with stored documents

Every render produces a stored document, accessible via `document_id` for
later download or thumbnails. `render.pdf` and `render.pdf_stream` are
conveniences that chain a presigned-URL fetch internally to return bytes;
`render.document` returns just the descriptor (skip the auto-download
when you'll fetch the bytes later).

```ruby
# 1. Render and store
doc = client.render.document(
  project:  "billing",
  template: "invoice",
  version:  "1.0.0",
  data:     { invoice_number: "INV-001" },
  metadata: { customer_id: "cust_123" }   # your own audit data
)
# doc.document_id, doc.page_count, doc.size_bytes, doc.presigned_pdf_url, doc.metadata, ...

# 2. Persist doc.document_id in your database
db.invoices.update(id: "INV-001", document_id: doc.document_id)

# 3. Later, fetch a fresh presigned URL + download
fresh = client.documents.get(doc.document_id)
pdf   = fresh.download_pdf

# 4. Generate thumbnails (Starter+ tier)
thumbs = client.documents.thumbnails(doc.document_id, width: 320, format: "png")

# 5. When done, soft-delete
client.documents.delete(doc.document_id)
```

The presigned URL has a 15-minute TTL. If `download_pdf` raises
`PoliPage::DownloadError` with `status: 403` from S3, call
`documents.get(id)` to refresh and retry.

## Authentication & environments

The mode is determined by the API key prefix:

- `pp_test_…` → sandbox mode (not billed, generous rate limits)
- `pp_live_…` → live mode (billed, production rate limits)
- `pp_sa_…`   → service-account keys; environment matches the SA's
                configuration (sandbox or live)

All prefixes hit the same endpoint (`https://api.poli.page`). The SDK
passes the key through as a `Bearer` token and never inspects the prefix —
pick whichever fits your deploy model.

## Methods

| Method                                          | Returns                            | Description                                         |
| ----------------------------------------------- | ---------------------------------- | --------------------------------------------------- |
| `client.render.pdf(**input)`                    | `String` (binary bytes)            | Render a PDF, return bytes                          |
| `client.render.pdf_stream(**input) { \|c\| … }` | `Enumerator` or yields chunks      | Render and stream the response                      |
| `client.render.preview(**input)`                | `PoliPage::PreviewResult`          | Paginated HTML preview                              |
| `client.render.document(**input)`               | `PoliPage::DocumentDescriptor`     | Render and return descriptor (skip auto-download)   |
| `client.documents.get(id)`                      | `PoliPage::DocumentDescriptor`     | Retrieve a stored document                          |
| `client.documents.preview(id)`                  | `PoliPage::DocumentPreviewResult`  | Stored document's paginated HTML                    |
| `client.documents.thumbnails(id, **opts)`       | `Array<PoliPage::Thumbnail>`       | Page thumbnails (PNG/JPEG, base64)                  |
| `client.documents.delete(id)`                   | `nil`                              | Soft-delete a stored document                       |
| `client.render_to_file(path, **input)`          | `nil`                              | Render and stream to disk                           |

## Configuration

| Option        | Type                       | Default                    | Description                                  |
| ------------- | -------------------------- | -------------------------- | -------------------------------------------- |
| `api_key:`    | `String`                   | (required)                 | `pp_test_*` or `pp_live_*` API key           |
| `base_url:`   | `String`                   | `"https://api.poli.page"`  | API base URL                                 |
| `max_retries:`| `Integer`                  | `2`                        | Max retry attempts on retryable errors       |
| `retry_delay:`| `Numeric` (seconds)        | `0.5`                      | Base delay before the first retry            |
| `timeout:`    | `Numeric` (seconds)        | `60`                       | Per-request timeout                          |
| `logger:`     | `Logger` (any duck type)   | `nil`                      | Hook errors and DEBUG events here            |
| `on_retry:`   | `#call(PoliPage::RetryEvent)`| `nil`                    | Called when a retry is scheduled             |
| `on_error:`   | `#call(PoliPage::Error)`   | `nil`                      | Called when a call terminates in error       |
| `proxy:`      | `String` (URL)             | `nil` (uses env)           | Override HTTP proxy; e.g. `"http://u:p@host:8080"` |
| `ca_file:`    | `String` (path)            | `nil`                      | Custom CA bundle (corp MITM, private PKI)    |
| `ca_path:`    | `String` (path)            | `nil`                      | Custom CA directory (hashed cert dir)        |

`http_proxy`, `https_proxy`, and `no_proxy` environment variables are
honored automatically by `Net::HTTP`'s `:ENV` proxy resolution — no
configuration needed in the common case. Pass `proxy:` to override.
For TLS verification against a private CA (e.g. behind a corporate
MITM-terminating proxy), point `ca_file:` at a PEM bundle.

## Error handling

Errors are dispatched by class — the rescue-friendly path:

```ruby
require "poli_page"

begin
  client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: data)
rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError => e
  refresh_credentials(e)
rescue PoliPage::RateLimitError => e
  queue_for_later(e.request_id)
rescue PoliPage::ValidationError => e
  logger.error("Bad input: #{e.message}")
rescue PoliPage::GoneError => e
  mark_document_gone(e.code)
rescue PoliPage::Error => e
  raise
end
```

Predicate helpers on the base class are kept for callers who prefer a
single `rescue PoliPage::Error => e` clause:

```ruby
rescue PoliPage::Error => e
  return refresh_credentials       if e.auth_error?
  return queue_for_later           if e.rate_limit_error?
  logger.error(e.code, e.status, e.request_id)
  raise unless e.retryable?        # SDK already retried up to max_retries
end
```

For lifecycle and billing failures, route the user to actionable messages
rather than treating them as opaque:

```ruby
rescue PoliPage::Error => e
  case e.code
  when "PAYMENT_REQUIRED"       then show_banner("Subscription has unpaid invoices.")
  when "ORGANIZATION_CANCELLED" then show_banner("Subscription cancelled — service is read-only.")
  when "ORGANIZATION_PURGED"    then show_banner("Organization has been purged.")
  when "DOCUMENT_NOT_FOUND"     then render_404
  when "GONE"                   then render_410   # document was soft-deleted
  else
    raise
  end
end
```

The full list of known API codes lives in `PoliPage::ErrorCodes` (see
`lib/poli_page/errors.rb`).

→ Full error reference: <https://poli-page.github.io/sdk-ruby/reference/errors/>

## Cancellation

Ruby has no async cancellation primitive comparable to `AbortSignal`.
Three mechanisms are available:

- **Per-request timeout** via the constructor's `timeout:` option — the
  most common case.
- **`Timeout.timeout` wrapping** for caller-side deadlines:
  ```ruby
  begin
    pdf = Timeout.timeout(10) { client.render.pdf(...) }
  rescue Timeout::Error
    # ... handle the deadline; the SDK does NOT translate this into PoliPage::TimeoutError
  end
  ```
- **`Thread#raise`** from a sibling thread for advanced cases; the SDK's
  blocking `sleep` between retries honours the interrupt.

For streaming methods, the block is the cancellation point: `break` or
`raise` out of the block to stop reading mid-stream.

## Observability

Two hooks fire at well-defined points. They're synchronous, optional, and
never break the request:

```ruby
client = PoliPage::Client.new(
  api_key:  ENV.fetch("POLI_PAGE_API_KEY"),
  logger:   Logger.new($stdout),
  on_retry: ->(event) { Statsd.increment("polipage.retry", tags: ["code:#{event.reason.code}"]) },
  on_error: ->(err)   { Sentry.capture_exception(err) }
)
```

Hook exceptions are swallowed — a broken metrics path never crashes a
render. The injected `logger:` works with any `Logger`-compatible object
(`lograge`, `ougai`, `semantic_logger`, etc.).

## Retries & idempotency

The SDK retries on **5xx**, **429**, **network errors**, and **timeouts**.
Backoff is exponential (`retry_delay * 2**(attempt - 1)`) with jitter in
`[0.5, 1.5)`, capped by `Retry-After` when the server provides it
(integer seconds or HTTP-date; capped at 30 s).

Every POST sends an auto-generated `Idempotency-Key` (UUID v4); pass
`idempotency_key:` to override.

```ruby
client.render.pdf(project: "billing", template: "invoice", version: "1.0.0",
                  data: data, idempotency_key: "render-INV-001-2026-05")
```

## Type system

The gem ships RBS signatures under `sig/`. Steep checks them against the
implementation in CI. Consumers can opt into project-mode validation via
required kwargs at runtime — `Client#render.pdf` raises `ArgumentError`
immediately if `project:`, `template:`, or `data:` are omitted.

For Sorbet users: `.rbi` shipping is a post-1.0 enhancement.

## Concurrency & thread-safety

A single `PoliPage::Client` instance is safe to share across threads.
Configuration is immutable after `#initialize`; each request opens its
own `Net::HTTP` connection.

```ruby
CLIENT = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY")).freeze

pdfs = ids.map do |id|
  Thread.new { CLIENT.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: { invoice_number: id }) }
end.map(&:value)
```

Build the client once at boot. Don't construct a new client per request.

## Runtime support

- Ruby 3.1+ (CRuby/MRI). Latest two minor releases tested in CI.
- JRuby 9.4+ on a best-effort basis.
- Linux and macOS in CI. Windows is supported but not exercised in CI.

## Requirements

Ruby **>= 3.2**. Tested in CI against 3.2, 3.3, and 3.4 on Ubuntu, plus
one job each on macOS and Windows with 3.4.

## Documentation & support

- Platform docs: [docs.poli.page](https://docs.poli.page)
- SDK documentation: [poli-page.github.io/sdk-ruby](https://poli-page.github.io/sdk-ruby/)
- Sign up & generate API keys: [app.poli.page](https://app.poli.page)
- Issues: [github.com/poli-page/sdk-ruby/issues](https://github.com/poli-page/sdk-ruby/issues)

## License

[MIT](LICENSE) © Poli Page
