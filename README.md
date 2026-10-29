# Poli Page SDK for Ruby

[![Gem](https://img.shields.io/gem/v/poli-page?style=flat&logo=ruby&logoColor=ffffff&label=Gem)](https://rubygems.org/gems/poli-page)
[![Downloads](https://img.shields.io/gem/dt/poli-page?style=flat&logo=ruby&logoColor=ffffff&label=Downloads)](https://rubygems.org/gems/poli-page)
[![Ci](https://img.shields.io/github/actions/workflow/status/poli-page/sdk-ruby/ci.yml?branch=main&style=flat&logo=githubactions&logoColor=ffffff&label=Ci)](https://github.com/poli-page/sdk-ruby/actions/workflows/ci.yml)
[![Codeql](https://img.shields.io/github/actions/workflow/status/poli-page/sdk-ruby/codeql.yml?branch=main&style=flat&logo=github&logoColor=ffffff&label=Codeql)](https://github.com/poli-page/sdk-ruby/actions/workflows/codeql.yml)
[![Coverage](https://img.shields.io/codecov/c/github/poli-page/sdk-ruby?style=flat&logo=codecov&logoColor=ffffff&label=Coverage)](https://codecov.io/gh/poli-page/sdk-ruby)
[![Ruby](https://img.shields.io/badge/Ruby-3.2%20%7C%203.3%20%7C%203.4-blue?style=flat&logo=ruby&logoColor=ffffff)](https://github.com/poli-page/sdk-ruby/blob/main/.github/workflows/ci.yml)
[![Types](https://img.shields.io/badge/Types-RBS-blue?style=flat&logo=ruby&logoColor=ffffff)](https://github.com/poli-page/sdk-ruby/tree/main/sig)
[![Style](https://img.shields.io/badge/Style-Rubocop-blue?style=flat&logo=ruby&logoColor=ffffff)](https://github.com/rubocop/rubocop)
[![Deps](https://img.shields.io/badge/Deps-up%20to%20date-brightgreen?style=flat&logo=ruby&logoColor=ffffff)](https://github.com/poli-page/sdk-ruby/network/dependencies)
[![Docs](https://img.shields.io/badge/Docs-online-brightgreen?style=flat&logo=readthedocs&logoColor=ffffff)](https://poli-page.github.io/sdk-ruby/)
[![License](https://img.shields.io/github/license/poli-page/sdk-ruby?style=flat&logo=gnu&logoColor=ffffff&label=License)](LICENSE)

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

The gem's one runtime dependency is `base64` (a bundled gem since Ruby
3.4, used to decode thumbnail data); everything else is the stdlib
(`net/http`, `json`, `uri`, `securerandom`, `logger`, `openssl`).

## Quick start

### Render a template by slug

Set `POLI_PAGE_API_KEY` to a `sandbox` key of a fresh organization
(`pp_sandbox_…`, see [Authentication & environments](#authentication--environments)),
then:

```ruby
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

pdf = client.render.pdf(
  project:  "getting-started",
  template: "welcome",
  data:     { name: "SDK Demo" }
)
# pdf is a binary-encoded String
```

Every organization gets a `getting-started` project, published into its
`sandbox` environment when the organization is created, with a `welcome`
template. A sandbox key renders it with no setup, so the snippet above runs
as-is on a fresh organization. It is a normal, editable project: in an
organization that renamed it, deleted it or removed it from `sandbox`, the
API answers `404 PROJECT_NOT_FOUND` or `404 PROJECT_NOT_IN_ENVIRONMENT`, so
use a fresh organization to follow along.

There is no version to pick: a render uses the project's copy published in
the API key's environment. For your own templates, publish the project to
the environment of the key you render with, then swap the slugs:

```ruby
pdf = client.render.pdf(
  project:  "billing",
  template: "invoice",
  data:     { invoiceNumber: "INV-001", total: 1280 }
)
```

To preview a template or render inline HTML while you design it, use the
playground: <https://play.poli.page>. The API and this SDK render published
templates only.

### Write a PDF to disk

```ruby
client.render_to_file(
  "./welcome.pdf",
  project: "getting-started", template: "welcome",
  data:    { name: "SDK Demo" }
)
```

`render_to_file` streams the response bytes directly to disk via
`render.pdf_stream` — bounded memory regardless of PDF size. Parent
directories are created on the fly.

### Try it locally — runnable demo

```sh
ruby examples/demo.rb
```

The demo renders `getting-started`/`welcome`, walks every public method
end-to-end and writes the results to `examples/output/`. First run prompts
for a `sandbox` key (`pp_sandbox_…`) and saves it to `.env` at the project
root. Subsequent runs are silent. The `POLI_PAGE_API_KEY` env var wins over
the file when set; `POLI_PAGE_BASE_URL` (optional) overrides the API host.

It walks nine steps: `render.pdf` → `render.pdf_stream` → `render_to_file`
→ `render.document` → `documents.get` → `documents.thumbnails` →
`documents.preview` → `documents.delete` → `not-found` (a render of a
template that does not exist, caught as `PoliPage::NotFoundError` with code
`TEMPLATE_NOT_FOUND`).

### Stream — for large PDFs or piping to S3 / HTTP responses

```ruby
File.open("invoice.pdf", "wb") do |io|
  client.render.pdf_stream(
    project: "billing", template: "invoice",
    data:    { invoiceNumber: "INV-001" }
  ) do |chunk|
    io.write(chunk)
  end
end
```

Without a block, `pdf_stream` returns an `Enumerator` that composes with
`Enumerable`:

```ruby
enum = client.render.pdf_stream(project: "billing", template: "invoice", data: data)
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
  data:     { invoiceNumber: "INV-001" },
  metadata: { customerId: "cust_123" }   # your own audit data
)
# doc.document_id, doc.page_count, doc.size_bytes, doc.presigned_pdf_url, ...
# doc.metadata is returned as stored: { "customerId" => "cust_123" }
# The keys of data: and metadata: are sent exactly as written (no renaming).

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

An API key belongs to exactly one environment of your organization, and its
text names that environment: a key is `pp_{env}_{32 lowercase hex}`, matching

```text
^pp_(?=[a-z][a-z0-9-]{0,19}_)[a-z][a-z0-9]*(?:-[a-z0-9]+)*_[0-9a-f]{32}$
```

The API resolves the environment from the key and renders the project's
copy published there; the SDK never sends an environment.

| Environment                           | Key            | Watermark | Counted |
| ------------------------------------- | -------------- | --------- | ------- |
| `sandbox` (every org)                 | `pp_sandbox_…` | yes       | no      |
| `live` (every org, deletable on Pro+) | `pp_live_…`    | no        | yes     |
| created on Pro+ (e.g. `staging`)      | `pp_staging_…` | no        | yes     |

"Counted" means the render counts toward the organization's monthly PDF
quota. `sandbox` renders are watermarked, are not counted, and their
documents expire 30 days after creation. There is no watermark option: a
template that wants a watermark outside `sandbox` uses the `poli-watermark`
class.

Standard and service keys share this one format. Every key hits the same
endpoint, `https://api.poli.page` by default or whatever you pass as
`base_url:` (see [Configuration](#configuration)). The SDK passes the key
through as a `Bearer` token and does not check its format.

## Methods

| Method                                          | Returns                            | Description                                         |
| ----------------------------------------------- | ---------------------------------- | --------------------------------------------------- |
| `client.render.pdf(**input)`                    | `String` (binary bytes)            | Render a PDF, return bytes                          |
| `client.render.pdf_stream(**input) { \|c\| … }` | `Enumerator` or yields chunks      | Render and stream the response                      |
| `client.render.document(**input)`               | `PoliPage::DocumentDescriptor`     | Render and return descriptor (skip auto-download)   |
| `client.documents.get(id)`                      | `PoliPage::DocumentDescriptor`     | Retrieve a stored document                          |
| `client.documents.preview(id)`                  | `PoliPage::DocumentPreviewResult`  | Stored document's paginated HTML                    |
| `client.documents.thumbnails(id, **opts)`       | `Array<PoliPage::Thumbnail>`       | Page thumbnails (JPEG/PNG/WebP, base64)             |
| `client.documents.delete(id)`                   | `nil`                              | Soft-delete a stored document (idempotent)          |
| `client.render_to_file(path, **input)`          | `nil`                              | Render and stream to disk                           |

## Configuration

| Option        | Type                       | Default                    | Description                                  |
| ------------- | -------------------------- | -------------------------- | -------------------------------------------- |
| `api_key:`    | `String`                   | (required)                 | API key of one environment (`pp_{env}_…`)    |
| `base_url:`   | `String`                   | `"https://api.poli.page"`  | API base URL                                 |
| `max_retries:`| `Integer`                  | `2`                        | Max retry attempts on retryable errors       |
| `retry_delay:`| `Numeric` (seconds)        | `0.5`                      | Base delay before the first retry            |
| `timeout:`    | `Numeric` (seconds)        | `60`                       | Per-attempt timeout, body included           |
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
  client.render.pdf(project: "billing", template: "invoice", data: data)
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
single `rescue PoliPage::Error => e` clause. They read `status` and `code`
(`auth_error?` is 401/403, `rate_limit_error?` 429, `validation_error?` 400,
`network_error?` `network_error`/`timeout`), so a `DownloadError` with a
storage 403 is an `auth_error?`:

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
  when "ORGANIZATION_PAYMENT_GRACE" then show_banner("Subscription has unpaid invoices.")
  when "ORGANIZATION_CANCELLED"     then show_banner("Subscription cancelled — service is read-only.")
  when "ORGANIZATION_PURGED"        then show_banner("Organization has been purged.")
  when "DOCUMENT_NOT_FOUND"         then render_404
  when "DOCUMENT_GONE"              then render_410   # deleted, or a sandbox document past 30 days
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

The SDK retries on **5xx**, **429**, **network errors**, and **timeouts**,
except `QUOTA_EXCEEDED`, `OVERAGE_CAP_EXCEEDED` and `STORAGE_ACCESS_DENIED`,
which wait cannot fix. The presigned-URL download is never retried.
Backoff is exponential (`retry_delay * 2**(attempt - 1)`) with jitter in
`[0.5, 1.5)`, replaced by `Retry-After` when the server provides it
(integer seconds or HTTP-date; clamped to 0–30 s). `timeout:` bounds each
attempt, body included, and every resend is one of these counted retries:
`Net::HTTP` never sends a request again on its own.

Every POST sends an auto-generated `Idempotency-Key` (UUID v4), the same on
every retry of one call; pass `idempotency_key:` to override. The API does
not deduplicate on it: a render retried after a late 5xx, a `timeout` or a
`network_error` can store a second document.

```ruby
client.render.pdf(project: "billing", template: "invoice",
                  data: data, idempotency_key: "render-INV-001-2026-05")
```

## Type system

The gem ships RBS signatures under `sig/`. Steep checks them against the
implementation in CI. The render methods take keyword arguments, so Ruby
checks them at call time — `Client#render.pdf` raises `ArgumentError`
before any request if `project:`, `template:`, or `data:` is omitted, or if
an unknown keyword (such as the removed `version:`) is passed.

For Sorbet users: `.rbi` shipping is a post-1.0 enhancement.

## Concurrency & thread-safety

A single `PoliPage::Client` instance is safe to share across threads.
Configuration is immutable after `#initialize`; each attempt opens its
own `Net::HTTP` connection (no pool or cache to size), plus a short-lived
thread that enforces `timeout:`.

```ruby
CLIENT = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY")).freeze

pdfs = ids.map do |id|
  Thread.new { CLIENT.render.pdf(project: "billing", template: "invoice", data: { invoiceNumber: id }) }
end.map(&:value)
```

Build the client once at boot. Don't construct a new client per request.

## Runtime support

- Ruby 3.2+ (CRuby/MRI).
- JRuby 9.4+ on a best-effort basis.
- Linux, macOS and Windows (see [Requirements](#requirements) for the CI matrix).

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
