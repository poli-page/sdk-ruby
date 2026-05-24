# Poli Page SDK for Ruby — Implementation Plan

**Created**: 2026-05-24
**Author**: handoff doc, not a spec — the spec lives at `/Users/mickael/Projects/sdk-node/sdk-specification.md` v1.3
**Reference impl**: `/Users/mickael/Projects/sdk-node` (`@poli-page/sdk` v1.0, shipped). Siblings: `/Users/mickael/Projects/sdk-python-plan.md`, `/Users/mickael/Projects/sdk-go-plan.md`, `/Users/mickael/Projects/sdk-php-plan.md`, `/Users/mickael/Projects/sdk-rust-plan.md`.
**Empirical API source of truth**: the CLI's api-client at `/Users/mickael/n/lib/node_modules/@poli-page/cli/dist/api-client.{js,d.ts}` — works end-to-end against `api-develop.poli.page`. When spec and deployed API disagree, the CLI's behavior wins.

This document is the briefing for a fresh Claude session in the new `sdk-ruby` repo. Everything a new conversation needs to start work — source-of-truth links, design decisions already made, the build order, and the open questions — is captured here.

---

## 0. TL;DR

We are shipping the Ruby sibling of `@poli-page/sdk`. The contract is fixed (`sdk-specification.md` v1.3); we are translating an already-shipped TypeScript reference implementation into idiomatic Ruby. The RubyGems package is `poli-page`; the require path is `poli_page` (RubyGems convention: kebab-case for the gem name, snake_case for the require path, same split as `rest-client` / `rest_client`).

The plan: **single gem, sync-only at v1.0** (Ruby has no mainstream async story — Threads + Ractors are the concurrency primitives; the `async` gem is interesting but not yet the ecosystem default). Built on **stdlib `Net::HTTP` only** — zero runtime dependencies (matches anthropic-sdk-ruby and modern stripe-ruby; avoids the Faraday-version-conflict footgun that bites Ruby SDK users). `JSON` from stdlib for serialization with a hand-rolled snake_case ↔ camelCase translator (~30 lines). `SecureRandom.uuid` from stdlib for idempotency keys. **Class-hierarchy errors** rooted at `PoliPage::Error < StandardError` (matches stripe-ruby / openai-ruby / anthropic-sdk-ruby conventions; pattern matching via `case ... in` works on the class). **Stdlib `Logger`** for observability with a `logger:` constructor kwarg and `POLI_PAGE_LOG` env var (matches stripe-ruby `Stripe.logger`). **WebMock + VCR** for tests; integration tests against `api-develop.poli.page` gated by env var. CI on GitHub Actions across **Ruby 3.2, 3.3, 3.4** on ubuntu, with single 3.4 jobs on macOS and Windows, with MSRV pinned at **3.2** (Ruby 3.2 introduced `Data.define` which we lean on for value objects; 3.2 reaches EOL in March 2026 but stays in matrix per engineering-guide §4.1 "at least one EOL version still in widespread use").

Manual local pre-flight via `scripts/release.sh` is the **primary publishing path** (per engineering guide §6.1). `gem push` runs from the maintainer's machine using a RubyGems API key stored in `~/.gem/credentials` (chmod 600), scoped to the `poli-page` gem via the RubyGems UI ("Edit profile → API keys → New API key → Scope: poli-page only"). MFA on the RubyGems account is mandatory for push since 2022. There is no Trusted Publishing equivalent for RubyGems yet (the [trusted-publisher RFC](https://github.com/rubygems/rfcs/pull/61) was in discussion at plan time); the per-gem scoped token is the credential boundary — same posture as the Go and PHP plans' "no auto-publish workflow". After publish, `rubydoc.info` auto-builds and hosts the YARD HTML for every published version (the Ruby equivalent of `pkg.go.dev` and `docs.rs` — zero config). We also publish YARD output to GitHub Pages on push to `main` for parity with the Node SDK's TypeDoc site.

Ship in **7 phases** (matches Go, PHP, Rust — no separate async phase; async is deferred to post-1.0). Target: feature-parity 1.0.0 release, behavior-identical to `@poli-page/sdk@1.0.0`. **"Behavior parity" specifically means: same retry policy (5xx+429+network+timeout, jitter `[0.5,1.5)`, Retry-After cap 30s), same error codes round-tripped verbatim, same `auth_error?` covering 401+403, same constructor validation, same hooks-never-break-the-request, same project-mode-only constraint on `render.pdf`/`render.pdf_stream`/`render.document`, same primitive-only `metadata` constraint, same thumbnails wire wrap/unwrap, same `documents.preview` text/html + `X-Document-Page-Count` parsing.**

---

## 1. Source-of-truth references

Read these in order before writing a single line of code:

1. **Multi-language spec** — `/Users/mickael/Projects/sdk-node/sdk-specification.md` (v1.3). Defines the contract every SDK must meet.
2. **SDK engineering guide** — `/Users/mickael/Projects/sdk-ruby/sdk-engineering-guide.md` (copy of sdk-node's). Cross-SDK policy: versioning, CHANGELOG/MIGRATION discipline, CI gates, language-version matrices, release flow, pre-push hooks. **Authoritative** — when this plan and the engineering guide disagree on conventions, the engineering guide wins.
3. **SDK roadmap** — `/Users/mickael/Projects/sdk-ruby/sdk-roadmap.md` (copy of sdk-node's). Multi-repo strategy across all SDKs. (Note: Ruby is not in the original 10-repo target; this SDK expands the fleet — when this plan ships, update the roadmap to add a Ruby row.)
4. **Node SDK source** — `/Users/mickael/Projects/sdk-node/src/`. Reference implementation. When the spec is silent, the Node SDK's behavior is canonical (spec §11).
5. **Node SDK tests** — `/Users/mickael/Projects/sdk-node/tests/`. Especially `tests/integration/` for what the deployed API actually returns, and `tests/error-codes.test.ts` for the full error matrix.
6. **Python sibling plan** — `/Users/mickael/Projects/sdk-python-plan.md` (or sdk-python/sdk-python-plan.md). Shares the sync-vs-async split rationale and the hook design; Ruby will follow the sync side of that split.
7. **Go sibling plan** — `/Users/mickael/Projects/sdk-go-plan.md`. Useful for the "stdlib HTTP, no third-party transport dep" architecture we mirror.
8. **PHP sibling plan** — `/Users/mickael/Projects/sdk-php-plan.md`. Most architecturally similar to Ruby (both sync, both dynamic, both class-hierarchy errors); mirror its structure section by section with Ruby substitutions.
9. **Rust sibling plan** — `/Users/mickael/Projects/sdk-rust-plan.md`. Most recent; the template this plan is modeled on.
10. **CLI api-client** — `/Users/mickael/n/lib/node_modules/@poli-page/cli/dist/api-client.{js,d.ts}`. Empirical source of truth for the deployed API. If the spec and the CLI disagree, the CLI is right.
11. **Node SDK README** — `/Users/mickael/Projects/sdk-node/README.md`. Mirror what the Ruby README needs to cover.

Anytime you're unsure about a behavior, check the Node SDK source. If the Node SDK behavior is wrong, that's a separate bug — fix it in `sdk-node` first, then port; don't diverge silently.

---

## 2. Naming and identity

Per spec §2 and roadmap §"10-repo target":

| Field | Value |
|---|---|
| **RubyGems package** | `poli-page` (kebab-case is RubyGems convention) |
| **Require path** | `require "poli_page"` (snake_case for the file; same convention as `rest-client` / `rest_client`) |
| **Top-level module** | `PoliPage` |
| **Client class** | `PoliPage::Client` (modular, like `Anthropic::Client` / `OpenAI::Client` / `Octokit::Client`) |
| **Method casing** | snake_case (Ruby idiom) — `client.render.pdf(...)`, `client.render.pdf_stream(...)`, `client.documents.thumbnails(...)`, etc. |
| **Error base** | `PoliPage::Error < StandardError`; subclasses per status — see §7 |
| **File helper** | `client.render_to_file(input, path:)` — instance method on `Client` (Ruby idiom is methods on objects, not free functions; alias as `PoliPage::Client#render_to_file`) |
| **Version constant** | `PoliPage::VERSION` in `lib/poli_page/version.rb`; surfaced at runtime via the same constant — no hand-maintained second copy in the gemspec |
| **User-Agent** | `poli-page-sdk-ruby/#{PoliPage::VERSION}` |

Field names on input hashes follow Ruby's snake_case (`project:`, `template:`, `idempotency_key:`). The wire JSON uses camelCase via `PoliPage::Internal::Wire.to_wire(payload)` and `from_wire(payload)` — hand-rolled (~30 LOC) converters in `lib/poli_page/internal/wire.rb`. The SDK has no runtime case-conversion DSL; conversion happens at the transport seam only.

**Why `PoliPage::Client` and not just `PoliPage`?** Ruby's convention for SDKs in 2026 is `Vendor::Client.new(...)` rather than `Vendor.new(...)` — it cleanly separates the namespace from the type. This matches `Anthropic::Client`, `OpenAI::Client`, `Stripe::APIResource` (Stripe's older `Stripe.api_key = ...` global pattern is now considered legacy). Side benefit: namespace pollution stays low — `PoliPage::ProjectModeInput`, `PoliPage::DocumentDescriptor`, etc. live next to `Client` without collision.

---

## 3. Architecture

### 3.1 Gem layout

```
sdk-ruby/
├── poli-page.gemspec                # gem metadata + runtime/dev deps + signing files list
├── Gemfile                          # `source "https://rubygems.org"; gemspec`
├── Gemfile.lock                     # COMMITTED — reproducible CI; consumers resolve their own
├── Rakefile                         # default task = rubocop + steep + rspec
├── .ruby-version                    # MRI pin (3.4.4 at plan time)
├── .rubocop.yml                     # extends rubocop-rspec; pinned target_ruby_version 3.2
├── .yardopts                        # YARD config: --markup markdown --no-private --output-dir doc
├── .rspec                           # --color --require spec_helper --format documentation
├── lib/
│   ├── poli_page.rb                 # top-level: require "poli_page/version" + core files, define module
│   ├── poli_page/
│   │   ├── version.rb               # PoliPage::VERSION = "1.0.0"
│   │   ├── client.rb                # PoliPage::Client (constructor, retries, hooks, render/documents accessors)
│   │   ├── render.rb                # PoliPage::Resources::Render (pdf, pdf_stream, preview, document)
│   │   ├── documents.rb             # PoliPage::Resources::Documents (get, preview, thumbnails, delete)
│   │   ├── errors.rb                # PoliPage::Error hierarchy + PoliPage::ErrorCodes module
│   │   ├── retry_event.rb           # PoliPage::RetryEvent value object (Data.define)
│   │   ├── render_to_file.rb        # module mixed into Client; defines #render_to_file
│   │   ├── inputs/
│   │   │   ├── project_mode_input.rb   # optional Data.define convenience wrapper
│   │   │   ├── inline_mode_input.rb    # optional Data.define convenience wrapper
│   │   │   └── thumbnail_options.rb
│   │   ├── models/
│   │   │   ├── document_descriptor.rb  # Data.define + #download_pdf method + client back-reference
│   │   │   ├── document_preview_result.rb
│   │   │   ├── preview_result.rb
│   │   │   ├── thumbnail.rb
│   │   │   ├── page_format.rb       # frozen Set of 12 valid format strings
│   │   │   └── orientation.rb       # frozen Set { "portrait", "landscape" }
│   │   └── internal/                # documented as :nodoc: in YARD; not part of the public API
│   │       ├── http.rb              # PURE module-level functions: build_url, build_headers, parse_error_body,
│   │       │                          compute_backoff, parse_retry_after. No I/O. Mirrors src/internal/http.ts.
│   │       ├── transport.rb         # Net::HTTP execution wrapper; the only place that touches the network
│   │       ├── wire.rb              # snake_case ↔ camelCase translation (recursive)
│   │       ├── uuid.rb              # SecureRandom.uuid wrapper (thin, in case we want to swap impls)
│   │       └── constants.rb         # API paths, defaults, header names, retry-after cap
├── sig/                             # RBS type signatures (shipped INSIDE the gem under `sig/`)
│   ├── poli_page.rbs
│   ├── poli_page/
│   │   ├── client.rbs
│   │   ├── render.rbs
│   │   ├── documents.rbs
│   │   ├── errors.rbs
│   │   ├── models.rbs
│   │   └── retry_event.rbs
├── spec/                            # RSpec
│   ├── spec_helper.rb               # WebMock.disable_net_connect!(allow: localhost); VCR config; SimpleCov
│   ├── support/
│   │   ├── api_stubs.rb             # canned response builders for WebMock
│   │   └── matchers.rb              # custom RSpec matchers (e.g. raise_poli_page_error)
│   ├── poli_page/
│   │   ├── client_spec.rb           # ports tests/index.test.ts (constructor validation, retry loop, hooks)
│   │   ├── render_spec.rb           # ports tests/render.test.ts
│   │   ├── documents_spec.rb        # ports tests/documents.test.ts
│   │   ├── errors_spec.rb           # ports tests/error.test.ts
│   │   ├── error_codes_spec.rb      # ports tests/error-codes.test.ts (full ~21-code matrix)
│   │   ├── retry_spec.rb            # backoff math, max attempts, Retry-After honoring, jitter bounds
│   │   ├── render_to_file_spec.rb   # ports tests/node.test.ts
│   │   └── internal/
│   │       ├── http_spec.rb         # ports tests/internal/http.test.ts (pure transport helpers)
│   │       └── wire_spec.rb         # snake_case ↔ camelCase round-trip
│   └── integration/                 # hits api-develop.poli.page; gated by POLI_PAGE_API_KEY env var
│       ├── render_spec.rb
│       └── documents_spec.rb
├── examples/                        # runnable demos (used as canonical references + manual smoke tests)
│   ├── demo.rb                      # end-to-end demo, runnable via `ruby examples/demo.rb`
│   ├── shared.rb                    # API key resolution from .env (port _shared.mjs)
│   └── templates/
│       └── invoice/                 # copied from sdk-node/demo/templates/ for cross-lang byte-diffability
├── .github/
│   ├── dependabot.yml               # bundler + github-actions ecosystems, weekly schedule (§16.6)
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── feature_request.yml
│   │   └── config.yml
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── CODEOWNERS
│   └── workflows/
│       ├── ci.yml                   # rubocop + steep + rspec + gem-build + install-smoke on 3.2/3.3/3.4
│       ├── integration.yml          # nightly + push-to-main; hits develop API
│       ├── docs.yml                 # YARD to GitHub Pages
│       └── codeql.yml               # CodeQL (Ruby is supported as of 2023)
├── scripts/
│   ├── release.sh                   # primary publishing path: lint + sig + spec + gem build + gem push + git tag (eng guide §6.1)
│   └── install-hooks.sh             # writes .git/hooks/pre-push (per engineering guide §8)
├── README.md
├── CHANGELOG.md                     # keepachangelog format, mirror sdk-node
├── MIGRATION.md                     # placeholder + v1.0 stub
├── SECURITY.md
├── CONTRIBUTING.md
├── LICENSE                          # MIT
├── sdk-engineering-guide.md         # COPY from sdk-node — authoritative cross-SDK policy
├── sdk-roadmap.md                   # COPY from sdk-node — multi-repo strategy
└── sdk-ruby-plan.md                 # this file
```

Reasoning: the **transport core** (URL/header building, response parsing, retry math, error classification) lives in `lib/poli_page/internal/http.rb` as module-level pure functions. The `Internal` namespace is documented `:nodoc:` (YARD hides it from generated docs) and the README declares it semver-exempt — but it is still technically reachable because Ruby has no real private-module primitive (no `pub(crate)` equivalent). We rely on convention and documentation, mirroring the Python plan's `_module` convention and the PHP plan's `Internal\` namespace.

The `PoliPage::Client` in `lib/poli_page/client.rb` orchestrates retries, fires hooks, and delegates HTTP execution to `PoliPage::Internal::Transport`. The `Render` and `Documents` resource classes hold a reference to the client and don't know about HTTP details. This mirrors Node's `internal/http.ts` (pure) + `index.ts` (orchestration) + `render.ts`/`documents.ts` (namespace impls) split. Same architecture, different idioms.

### 3.2 The transport seam

```ruby
# lib/poli_page/internal/transport.rb — convention-private; subject to change without semver bump

module PoliPage
  module Internal
    # Thin wrapper around Net::HTTP. The ONLY module that opens sockets.
    class Transport
      Response = Data.define(:status, :headers, :body)

      def initialize(base_url:, timeout:, logger: nil)
        @base_url = URI.parse(base_url)
        @timeout  = timeout
        @logger   = logger
      end

      # @param method   [Symbol]            :get, :post, :delete
      # @param path     [String]            "/v1/render"
      # @param headers  [Hash{String=>String}]
      # @param body     [String, nil]       JSON-encoded body or nil
      # @return         [Response]          status, headers, raw body bytes
      # @raise          [PoliPage::ConnectionError, PoliPage::TimeoutError]
      def execute(method:, path:, headers:, body: nil)
        uri = URI.join(@base_url, path)
        request = build_request(method, uri, headers, body)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: @timeout,
                                            read_timeout: @timeout,
                                            write_timeout: @timeout) do |http|
          response = http.request(request)
          Response.new(
            status: response.code.to_i,
            headers: response.to_hash.transform_values { |v| v.is_a?(Array) ? v.first : v },
            body: response.body
          )
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout
        raise PoliPage::TimeoutError.new(timeout: @timeout)
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError => e
        raise PoliPage::ConnectionError.new(message: e.message, cause: e)
      end

      # Streaming variant for the second hop of pdf/pdf_stream (the presigned-URL fetch).
      # Yields chunks to the block; not subject to the SDK's retry policy.
      def stream_get(url, &block)
        # ... uses Net::HTTP#request_get with a block that calls response.read_body { |chunk| block.call(chunk) }
      end

      private

      def build_request(method, uri, headers, body)
        klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
        req = klass.new(uri)
        headers.each { |k, v| req[k] = v }
        req.body = body if body
        req
      end
    end
  end
end
```

The transport opens a fresh `Net::HTTP` connection per call. This is **intentionally simpler than `Net::HTTP::Persistent` or a `connection_pool`** at v1.0: per-call connection setup is ~10–50 ms TCP+TLS handshake, negligible against PDF render latency (seconds). Adding persistent pooling later is a non-breaking 1.x minor — wrap the existing call in a pool with the same Transport interface.

**Tests swap the transport** by stubbing `Net::HTTP` directly via `WebMock` — no separate transport-injection seam needed because `WebMock` intercepts at the socket level. This is the Ruby-native equivalent of Python's `respx`, Go's `httptest.NewServer`, and Rust's `wiremock`.

**Per the n2 design memory cleaned up in the Node SDK**: design all four verbs (POST/GET/DELETE plus the unauthenticated S3 GET for downloads) from day one. The `execute` method is verb-agnostic via the `method:` kwarg; the wire-level work is the same regardless.

### 3.3 Public surface

Minimal construction (the recommended path):

```ruby
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

pdf = client.render.pdf(
  project: "billing",
  template: "invoice",
  version: "1.0.0",
  data: { invoice_number: "INV-001" }
)

File.binwrite("invoice.pdf", pdf)
```

For more configuration, pass extra kwargs:

```ruby
client = PoliPage::Client.new(
  api_key:     ENV.fetch("POLI_PAGE_API_KEY"),
  base_url:    "https://api.poli.page",
  max_retries: 3,
  retry_delay: 0.5,           # seconds (Ruby Time convention)
  timeout:     60,            # seconds
  logger:      Logger.new($stdout),
  on_retry:    ->(event) { metrics.increment("polipage.retry") },
  on_error:    ->(err)   { Sentry.capture_exception(err) }
)
```

Idiomatic error handling combines `rescue` and pattern matching:

```ruby
begin
  pdf = client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: data)
rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError => e
  refresh_credentials(e)
rescue PoliPage::RateLimitError => e
  queue_for_later(e.request_id)
rescue PoliPage::GoneError => e
  mark_document_gone(e.code)
rescue PoliPage::Error => e
  raise
end

# Or with pattern matching (Ruby 3.0+):
case err = client.render.pdf(...) rescue $!
in PoliPage::Error => e if e.auth_error?       then refresh_credentials(e)
in PoliPage::Error => e if e.rate_limit_error? then queue_for_later(e.request_id)
in PoliPage::GoneError                         then mark_document_gone(err.code)
end
```

For users wanting a typed input object instead of bare kwargs:

```ruby
input = PoliPage::ProjectModeInput.new(
  project: "billing",
  template: "invoice",
  version: "1.0.0",
  data: { invoice_number: "INV-001" }
)
pdf = client.render.pdf(**input.to_h)
```

`ProjectModeInput` and `InlineModeInput` are `Data.define`'d value objects (Ruby 3.2+) — immutable, frozen, equality-by-value. They are convenience constructors; the underlying methods accept bare kwargs.

The gem exports (under `PoliPage::`):

- `Client` — main client; sub-namespaces reachable as `client.render` and `client.documents`
- `Resources::Render`, `Resources::Documents` — namespace classes (instance methods)
- `ProjectModeInput`, `InlineModeInput`, `ThumbnailOptions` — `Data.define` value objects for typed inputs
- `DocumentDescriptor`, `DocumentPreviewResult`, `PreviewResult`, `Thumbnail` — `Data.define` value objects for responses
- `PageFormat`, `Orientation` — frozen `Set`s of valid string values (NOT enums — Ruby has no native enum; using strings is the most idiomatic and matches the wire format directly)
- `Error` (base) + subclasses (see §7) + `ErrorCodes` module with the known string constants
- `RetryEvent` — `Data.define` value object for the `on_retry` hook
- `VERSION` constant

`require "poli_page"` autoloads everything via `Zeitwerk` (if pulling Zeitwerk as a runtime dep is acceptable) OR via hand-written `require` statements in `lib/poli_page.rb` (the dependency-free path). **Decision**: hand-written requires. Zeitwerk would add a transitive runtime dep for marginal benefit on a SDK this size (~15 files in `lib/`). Match anthropic-sdk-ruby (no Zeitwerk) rather than Rails (Zeitwerk-native).

### 3.4 `DocumentDescriptor` and `download_pdf`

Mirrors Node's `attachDownloadPdf` (`render.ts:40-63` + `documents.ts:21-44`). The descriptor exposes a `#download_pdf` method:

```ruby
module PoliPage
  DocumentDescriptor = Data.define(
    :document_id,
    :organization_id,
    :project_id,         # nullable on wire → may be nil
    :project_slug,
    :template_id,
    :template_slug,
    :version,
    :environment,        # String: "sandbox" or "live"
    :api_key_id,
    :format,             # String: one of PoliPage::PageFormat values
    :orientation,        # String: "portrait" or "landscape", nullable
    :locale,
    :page_count,         # Integer
    :size_bytes,         # Integer
    :created_at,         # String (ISO 8601); not parsed — no extra dep on Time-parsing libs beyond stdlib
    :metadata,           # Hash{String => String|Numeric|Boolean}; always present, possibly empty
    :presigned_pdf_url,
    :expires_at,         # String (ISO 8601)
    :_client             # back-reference, attached by the SDK; not part of the wire shape
  ) do
    # Fetch the PDF bytes from `presigned_pdf_url`. The URL has a 15-minute TTL —
    # if it expired, call `client.documents.get(document_id)` to refresh and retry.
    #
    # @return [String] raw PDF bytes (binary-encoded)
    # @raise  [PoliPage::DownloadError] on non-2xx or network failure
    def download_pdf
      raise PoliPage::InternalError, "DocumentDescriptor missing client back-reference" if _client.nil?
      _client.__send__(:fetch_bytes, presigned_pdf_url)
    end

    # Hide the back-reference from inspect/to_h output.
    def to_h
      super.except(:_client)
    end

    def inspect
      "#<PoliPage::DocumentDescriptor document_id=#{document_id.inspect} ...>"
    end
  end
end
```

**Nullability**: every wire field that is `string | null` on the API is a nilable Ruby attribute. The `Data.define` constructor accepts `nil` for any field; consumers check with `if descriptor.project_id.nil?` or `descriptor.project_id&.upcase`. Ruby's nil handling is the cleanest primitive across all SDKs — no `Option<T>` / `Ptr<T>` ceremony needed.

**Metadata is always non-null**: a `Hash` with `default: nil`; the SDK normalizes `nil` to `{}` after `from_wire`. The server always echoes `{}`, but defense in depth.

**Client back-reference**: attached by the SDK in `render.document` and every `documents.*` method via `descriptor.with(_client: self)` (Data's `#with` returns a new frozen instance). `download_pdf` uses the parent's transport (so any logging/configuration applies) — but the request to the S3 URL is **unauthenticated** and **not subject to the SDK's retry policy**.

**Why `Data.define` and not `Struct.new` or a regular class?** `Data.define` (Ruby 3.2+) creates immutable value objects with `==` by value, frozen at construction, `#with` for non-mutating updates, and clean `#deconstruct_keys` support for pattern matching. It's the Ruby-3.2-native equivalent of Rust `#[derive(Debug, Clone)]` structs, Python frozen dataclasses, and PHP readonly classes. `Struct.new` is the older, mutable variant — avoid. `Data.define` is also faster (the bytecode emits inline accessors).

---

## 4. Concurrency model

**Sync-only at v1.0.** Ruby has no mainstream async story — the `async` gem is Fiber-based and gaining traction but not yet the ecosystem default (anthropic-sdk-ruby, stripe-ruby, openai-ruby, octokit are all sync-only as of 2026). Threading is the Ruby concurrency primitive for I/O-bound work.

- **`PoliPage::Client`** — sync; every method blocks the calling thread until the response is received (or an error is raised).
- **Thread safety**: a single `PoliPage::Client` instance MUST be safe to share across threads. The internal state is the configuration (read-only after `initialize`) and the transport. Each `Transport#execute` call opens its own `Net::HTTP` connection (no shared mutable state). The hooks (`on_retry`, `on_error`) are user-provided Procs — the SDK calls them, but their thread-safety is the caller's responsibility.
- **Concurrent rendering** is done by the caller via Ruby threads:
  ```ruby
  pdfs = ["INV-001", "INV-002", "INV-003"].map do |id|
    Thread.new { client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: { invoice_number: id }) }
  end.map(&:value)
  ```
  Document this pattern prominently in the README.
- **One-client-per-process pattern**: cloning the client is unnecessary in Ruby (objects are reference-shared by default). Build one client at app startup, pass it into request handlers / spawned threads. Document this in the README.
- **No GIL contention** for HTTP I/O: MRI's GIL releases during blocking syscalls, so concurrent HTTP calls scale linearly with thread count up to the network limit. JRuby and TruffleRuby have no GIL and parallelize natively.

**Async story (post-v1.0)**: the `async` gem from Samuel Williams could be supported via a separate `PoliPage::AsyncClient` in a 1.x minor — same surface area, different transport using `Async::HTTP::Internet`. Defer until user demand materializes. Document the deferred status in `MIGRATION.md`.

**Ractor support is explicitly NOT a goal.** Ractors require strict immutability; we use shared hooks (Procs) and a logger, both Ractor-incompatible. Users wanting Ractor isolation can build their own client per Ractor.

---

## 5. HTTP transport (Net::HTTP)

### 5.1 Dependency choice

**`Net::HTTP` from the Ruby stdlib is the only transport**. Reasoning:

- **Zero runtime dependencies** — no `Faraday`, `HTTP.rb`, `Excon`, or `HTTParty`. This is the Stripe / Anthropic / Octokit-modern posture: Ruby SDK users have been bitten too many times by Faraday major-version conflicts (Faraday 1.x → 2.x broke every adapter). Shipping with zero deps maximizes install-anywhere compatibility.
- **Stdlib is good enough**: `Net::HTTP` supports TLS via OpenSSL, persistent connections per-block, configurable timeouts, streaming response bodies (`response.read_body { |chunk| ... }`), and all four HTTP verbs we need. The API is dated (1996-vintage), but our internal `Transport` wrapper papers over the ergonomics.
- **Predictable supply chain**: stdlib is shipped with Ruby — no separate version to track, no advisory database lookups, no dep-tree explosion.

`poli-page.gemspec` runtime deps:

```ruby
Gem::Specification.new do |s|
  s.name          = "poli-page"
  s.version       = PoliPage::VERSION
  s.summary       = "Poli Page SDK for Ruby — render PDFs from HTML templates via the Poli Page API"
  s.description   = "Official Ruby client for Poli Page. Renders PDFs, previews, and thumbnails via the api.poli.page service."
  s.authors       = ["Poli Page"]
  s.email         = "support@poli.page"
  s.homepage      = "https://poli.page"
  s.license       = "MIT"
  s.required_ruby_version = ">= 3.2"

  s.metadata = {
    "homepage_uri"      => "https://poli.page",
    "source_code_uri"   => "https://github.com/poli-page/sdk-ruby",
    "changelog_uri"     => "https://github.com/poli-page/sdk-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://rubydoc.info/gems/poli-page",
    "bug_tracker_uri"   => "https://github.com/poli-page/sdk-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir["lib/**/*.rb"] + Dir["sig/**/*.rbs"] +
            %w[LICENSE README.md CHANGELOG.md MIGRATION.md SECURITY.md]
  s.require_paths = ["lib"]

  # NO RUNTIME DEPS. Stdlib only. (Net::HTTP, JSON, SecureRandom, Logger, URI, OpenSSL.)
end

# Dev deps live in the Gemfile, not the gemspec:
# rspec, webmock, vcr, rubocop, rubocop-rspec, yard, rbs, steep, simplecov
```

**No runtime deps** — assert this at gemspec parse time by failing CI if any non-stdlib gem is added to `spec.add_runtime_dependency`. (One-line `Rake` task that greps the gemspec.) Mirrors the Go SDK's "no third-party transport dep" posture.

### 5.2 Connection pooling

**No pooling at v1.0.** Each `Transport#execute` call invokes `Net::HTTP.start(...)` with a block, which opens a TCP+TLS connection, sends the request, reads the response, and closes the connection on block exit. Per-call setup is ~10–50 ms; render latency is seconds; pooling would shave noise off, not a real cost.

Adding `Net::HTTP::Persistent` (separate gem, ~500 LOC, mature) or `connection_pool` (separate gem, ~200 LOC, used by Sidekiq) is a non-breaking 1.x minor when profiling justifies it. Defer.

**Document the one-client-per-process pattern** in the README: building a new `Client` per request would re-allocate `Net::HTTP` instances unnecessarily. The current code reuses the `Client` instance across requests; even without pooling, this is the right pattern.

### 5.3 Headers (spec §9.1)

Every SDK-originated request includes:

| Header | Value |
|---|---|
| `Authorization` | `Bearer #{api_key}` |
| `Content-Type` | `application/json` (POST only — omit on GET/DELETE) |
| `Accept` | `application/json` (always — Node retired `application/pdf` direct responses; see `src/internal/http.ts:79`) |
| `User-Agent` | `poli-page-sdk-ruby/#{PoliPage::VERSION}` |
| `Idempotency-Key` | `SecureRandom.uuid` (POST only) — auto-generated unless caller supplies one via `idempotency_key:` |

Built by `PoliPage::Internal::HTTP.build_headers(method:, api_key:, idempotency_key:, user_agent:)` returning a `Hash{String => String}`. Tests verify the matrix per method.

### 5.4 Wire body translation

The SDK uses **explicit `to_wire` / `from_wire` helpers** rather than runtime metaprogramming. Hand-rolled, ~30 LOC, no dep:

```ruby
# lib/poli_page/internal/wire.rb

module PoliPage
  module Internal
    module Wire
      module_function

      # Recursively transform snake_case Hash keys to camelCase for outgoing JSON.
      def to_wire(value)
        case value
        when Hash  then value.transform_keys { |k| snake_to_camel(k.to_s) }.transform_values { |v| to_wire(v) }
        when Array then value.map { |v| to_wire(v) }
        else value
        end
      end

      # Recursively transform camelCase Hash keys to snake_case symbols for incoming JSON.
      def from_wire(value)
        case value
        when Hash  then value.each_with_object({}) { |(k, v), h| h[camel_to_snake(k.to_s).to_sym] = from_wire(v) }
        when Array then value.map { |v| from_wire(v) }
        else value
        end
      end

      def snake_to_camel(s)
        s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
      end

      def camel_to_snake(s)
        s.gsub(/([A-Z])/, '_\1').downcase
      end
    end
  end
end
```

Outbound flow:
1. User passes kwargs to `client.render.pdf(project:, template:, data:, ...)`.
2. Method body builds a snake_case hash (`{ project: ..., template: ..., data: ... }`).
3. `Internal::Wire.to_wire(body)` flips keys to camelCase.
4. `JSON.generate(...)` serializes to a String.
5. Transport sends.

Inbound flow:
1. Transport returns response body bytes.
2. `JSON.parse(...)` returns a `Hash{String => Object}` (camelCase keys).
3. `Internal::Wire.from_wire(parsed)` returns a `Hash{Symbol => Object}` (snake_case symbol keys).
4. Pass to the `Data.define` value object's constructor via `**parsed`.

**SDK-only fields stripped from the wire**: `idempotency_key:` and `timeout:` are read by the SDK and excluded from the body before `to_wire`:

```ruby
def pdf(project:, template:, data:, version: nil, format: nil, orientation: nil, locale: nil, metadata: nil,
        idempotency_key: nil, timeout: nil)
  body = { project: project, template: template, data: data,
           version: version, format: format, orientation: orientation,
           locale: locale, metadata: metadata }.compact   # drop nils so they don't serialize as JSON null
  @client.__send__(:execute_post, "/v1/render",
                   body: body,
                   idempotency_key: idempotency_key,
                   timeout: timeout)
end
```

`Hash#compact` is the Ruby idiom for the equivalent of Rust's `#[serde(skip_serializing_if = "Option::is_none")]` and Python's `exclude_none=True`.

**Thumbnails body wrapping** (deployed API quirk): `POST /v1/documents/:id/thumbnails` wants `{ "thumbnails": { ...options } }`. The SDK wraps in the `Documents#thumbnails` method body (matches Node `documents.ts:96`):

```ruby
def thumbnails(id, **options)
  body = { thumbnails: options.compact }
  response = @client.__send__(:execute_post, "/v1/documents/#{CGI.escape(id)}/thumbnails", body: body)
  response[:thumbnails].map { |t| Thumbnail.new(**t) }
end
```

**Thumbnails response unwrapping**: server returns `{ "thumbnails": [...] }`; the SDK accesses `[:thumbnails]` and returns just the `Array<Thumbnail>` (mirror Node `documents.ts:99`).

**Document ID path interpolation** MUST be URL-encoded via `CGI.escape(id)` (stdlib). Port the `encodeURIComponent` calls from Node `documents.ts`.

**Metadata constraint**: values are primitives only (`String`, `Integer`, `Float`, `TrueClass`, `FalseClass`). Enforced at runtime in `Client#execute_post` via a validator that walks the metadata hash and raises `PoliPage::InvalidOptionsError` (code `PROJECT_REQUIRED_FOR_DOCUMENT` matches Node — actually NO, the Node error code is `METADATA_INVALID_TYPE` or similar; double-check by porting `types.ts:31` and `tests/types.test-d.ts:62-68`).

### 5.5 Response handling

- All SDK endpoints return JSON, except `documents.preview` which returns `text/html`.
- 2xx JSON: `JSON.parse(body)`. Failures (malformed JSON) become `PoliPage::InternalError.new(code: "INTERNAL_ERROR", ...)`.
- 2xx text/html (`documents.preview` only): the body String is returned as-is (force binary → UTF-8 if needed via `body.force_encoding("UTF-8")`); parse `X-Document-Page-Count` via `headers["x-document-page-count"]&.to_i || 0` (Net::HTTP downcases header names; `String#to_i` returns 0 for non-numeric, port `documents.ts:75-77`).
- non-2xx: parse body via `Internal::HTTP.parse_error_body(body, status)`, raise the appropriate `PoliPage::Error` subclass.
- The presigned-PDF fetch (`download_pdf`, `pdf_stream` second hop) is a plain `Net::HTTP.get_response(URI(presigned_url))` — **not authenticated, not subject to the retry policy**. Failures map to `PoliPage::DownloadError`.

### 5.6 Streaming

`render.pdf_stream` accepts a block and yields raw chunks; without a block, returns an `Enumerator`:

```ruby
client.render.pdf_stream(project: "billing", template: "invoice", version: "1.0.0", data: data) do |chunk|
  io.write(chunk)
end

# Or:
enum = client.render.pdf_stream(project: "billing", template: "invoice", version: "1.0.0", data: data)
enum.each { |chunk| io.write(chunk) }
```

Implementation (port `render.ts`):

1. Call `render.document(...)` to get the descriptor (with `presigned_pdf_url`).
2. Use `Net::HTTP.start { |http| http.request_get(uri) { |response| response.read_body { |chunk| yield chunk } } }` for the GET against the presigned URL. On error → `PoliPage::DownloadError.new(code: "DOWNLOAD_FAILED", status: ...)`.
3. If response status is non-2xx → `PoliPage::DownloadError`.
4. If response has no body (`Content-Length: 0`) → `PoliPage::InternalError` (port the `!response.body` guard from `render.ts:128-130`).

The Enumerator form (`Enumerator.new { |y| pdf_stream(input) { |chunk| y << chunk } }`) is idiomatic Ruby — it composes with `Enumerable#each_with_index`, `#to_a`, `#first(n)`, etc.

**Documents methods do not accept per-call cancellation** — same posture as Node/Python/Go/PHP/Rust. The block-form is the cancellation point: the caller can `break` out of the block or `raise` from within to abort mid-stream; the SDK's `read_body` loop honors the exception.

---

## 6. Retries

Port `src/index.ts` `#runWithRetry` + `src/internal/http.ts` byte-for-byte:

- Retry on **5xx, 429, network errors, and timeouts**.
- Never retry other 4xx (400, 401, 403, 404, 410, etc.).
- `max_retries` default `2` (so up to 3 attempts total). `max_retries: 0` disables retries.
- `retry_delay` default `0.5` (seconds — Ruby Time idiom uses Float-seconds). Tests assert "500 ms" for parity with Node.
- Exponential backoff: `retry_delay * 2**(attempt - 1)`.
- **Jitter**: multiply by uniform random factor in `[0.5, 1.5)`. Implementation: `delay = base * (2**(attempt - 1)) * (0.5 + rand)` — `rand` returns a `[0.0, 1.0)` Float by default. NOT ±20%.
- **`Retry-After`**: when the response includes the header, use that value as-is (no jitter). Accepts integer seconds or HTTP-date. For HTTP-date use `Time.httpdate(value).rescue { nil }` (stdlib `time` library — requires `require "time"`; pre-loaded at gem boot in `lib/poli_page.rb`). **Capped at 30 seconds** (`RETRY_AFTER_CAP = 30`). Past dates clamp to `0`. Unparseable values are ignored (fall back to computed backoff).
- **The retry sleep is cancellable** via `Thread#raise` from another thread, or via `Timeout.timeout(deadline) { sleep delay }` if the user wraps the call externally. `Kernel#sleep` returns early when the thread receives a signal. Ruby has no async cancellation primitive comparable to Rust's future-drop or Python's `asyncio.CancelledError` — `Thread#raise` is the only mechanism, and it's a heavyweight escape hatch.

When retries are exhausted, fire `on_error` hook with the last error and re-raise.

**No new deps**: `Time.httpdate` is stdlib (`require "time"`). `rand` is in `Kernel`. `sleep` is in `Kernel`.

---

## 7. Errors

**Class hierarchy rooted at `PoliPage::Error < StandardError`.** Ruby's class system is the idiomatic dispatch mechanism (`rescue PoliPage::AuthenticationError`); the predicate methods on the base are kept for spec parity and for users who want a single rescue point.

```ruby
# lib/poli_page/errors.rb

module PoliPage
  # Base for all SDK-raised errors. Inherits from StandardError so `rescue => e` catches it
  # (whereas inheriting from Exception would skip the default rescue).
  class Error < StandardError
    attr_reader :code, :status, :request_id

    # @param message    [String]
    # @param code       [String]      machine-readable code (see ErrorCodes); never nil
    # @param status     [Integer, nil] HTTP status if from the API; nil for SDK-internal errors
    # @param request_id [String, nil]
    def initialize(message = nil, code:, status: nil, request_id: nil)
      super(message)
      @code       = code
      @status     = status
      @request_id = request_id
    end

    # Predicate helpers (spec §7.1).
    def auth_error?
      is_a?(AuthenticationError) || is_a?(PermissionDeniedError)   # 401 + 403
    end

    def rate_limit_error?
      is_a?(RateLimitError)
    end

    def validation_error?
      is_a?(ValidationError)
    end

    def network_error?
      is_a?(ConnectionError) || is_a?(TimeoutError)
    end

    def retryable?
      return true if network_error?
      return true if status && (status >= 500 || status == 429)
      false
    end
  end

  # --- API status errors — status is Integer, code from the wire ---

  class ValidationError      < Error; end   # 400
  class AuthenticationError  < Error; end   # 401
  class PermissionDeniedError < Error; end  # 403
  class NotFoundError        < Error; end   # 404
  class GoneError            < Error; end   # 410
  class RateLimitError       < Error; end   # 429
  class APIError             < Error; end   # catch-all for other 4xx/5xx

  # --- SDK-internal errors — status is nil ---

  class InvalidOptionsError < Error
    def initialize(message, code: "invalid_options")
      super(message, code: code, status: nil, request_id: nil)
    end
  end

  class ConnectionError < Error
    attr_reader :cause   # the underlying exception
    def initialize(message:, cause: nil)
      super(message, code: "network_error", status: nil, request_id: nil)
      @cause = cause
    end
  end

  class TimeoutError < Error
    attr_reader :timeout
    def initialize(timeout:)
      super("request timed out after #{timeout}s", code: "timeout", status: nil, request_id: nil)
      @timeout = timeout
    end
  end

  class DownloadError < Error
    def initialize(message:, status: nil)
      super(message, code: "DOWNLOAD_FAILED", status: status, request_id: nil)
    end
  end

  class InternalError < Error
    def initialize(message, status: nil)
      super(message, code: "INTERNAL_ERROR", status: status, request_id: nil)
    end
  end
end
```

The hierarchy is constructed exclusively via `PoliPage::Internal::HTTP.classify(status:, code:, message:, request_id:)` — a single classifier that maps `(status, code)` pairs to the most specific subclass. Tests assert the matrix.

### 7.1 Predicate helpers (kept for spec parity)

Spec §7.1 mandates these predicates. The Ruby-idiomatic path is `rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError`; the predicates are convenience methods documented as such.

(Definitions above in the `Error` base class.)

### 7.2 Reserved (SDK-internal) codes

`Error#status` returns `nil` for these (except `DownloadError` which may carry the S3 status):

| Subclass | `code` | Cause |
|---|---|---|
| `InvalidOptionsError` | `"invalid_options"` | Constructor / per-call validation (e.g., empty api_key, nested metadata object). |
| `ConnectionError` | `"network_error"` | DNS, connection refused, TLS, etc. (rescued from `SocketError`, `Errno::ECONNREFUSED`, etc.). |
| `TimeoutError` | `"timeout"` | Per-request deadline exceeded (rescued from `Net::OpenTimeout`, `Net::ReadTimeout`, `Net::WriteTimeout`). |
| `DownloadError` | `"DOWNLOAD_FAILED"` | Presigned-URL fetch (the S3 second-hop) failed. May have an S3 HTTP status or none. |
| `InternalError` | `"INTERNAL_ERROR"` | SDK-side: response body unparseable, missing body, JSON decode failure. May have status. |

### 7.3 Error-body parsing (port `parseErrorBody` exactly)

```ruby
# lib/poli_page/internal/http.rb (excerpt)

def self.parse_error_body(body, status)
  parsed = JSON.parse(body) rescue nil
  return ["INTERNAL_ERROR", "API error #{status}: response body was not valid JSON"] if parsed.nil?

  code    = parsed["code"] || parsed["message"] || parsed["error"] || "unknown_error"
  message = parsed["message"] || "API error (#{status}): #{code}"
  [code, message]
end
```

The fallback chain matters — port `tests/internal/http.test.ts:108-152` 1:1.

### 7.4 Known API codes (constants)

Pass-through verbatim per spec §7.2. Provide a `PoliPage::ErrorCodes` module:

```ruby
module PoliPage
  module ErrorCodes
    MISSING_API_KEY               = "MISSING_API_KEY"
    INVALID_API_KEY               = "INVALID_API_KEY"
    PAYMENT_REQUIRED              = "PAYMENT_REQUIRED"
    FORBIDDEN                     = "FORBIDDEN"
    ORGANIZATION_CANCELLED        = "ORGANIZATION_CANCELLED"
    ORGANIZATION_PURGED           = "ORGANIZATION_PURGED"
    NOT_FOUND                     = "NOT_FOUND"
    VERSION_NOT_FOUND             = "VERSION_NOT_FOUND"
    DOCUMENT_NOT_FOUND            = "DOCUMENT_NOT_FOUND"
    GONE                          = "GONE"
    VALIDATION_ERROR              = "VALIDATION_ERROR"
    MISSING_DATA                  = "MISSING_DATA"
    MISSING_PROJECT_OR_TEMPLATE   = "MISSING_PROJECT_OR_TEMPLATE"
    MISSING_TEMPLATE_SLUG         = "MISSING_TEMPLATE_SLUG"
    PROJECT_REQUIRED_FOR_DOCUMENT = "PROJECT_REQUIRED_FOR_DOCUMENT"
    INVALID_VERSION_FORMAT        = "INVALID_VERSION_FORMAT"
    VERSION_REQUIRED              = "VERSION_REQUIRED"
    INVALID_VERSION_FOR_KEY_ENV   = "INVALID_VERSION_FOR_KEY_ENV"
    QUOTA_EXCEEDED                = "QUOTA_EXCEEDED"
    OVERAGE_CAP_EXCEEDED          = "OVERAGE_CAP_EXCEEDED"
    INTERNAL_ERROR                = "INTERNAL_ERROR"
  end
end
```

Users may still see codes not in this list — the SDK passes whatever the API returns. Note: `STORAGE_REQUIRED` was retired from the deployed API and removed from the Node SDK's `ApiCode` union — do NOT export it as a constant.

---

## 8. Cancellation and timeouts

Ruby has no async cancellation primitive comparable to Rust's future-drop, Go's `context.Context`, or Python's `asyncio.CancelledError`. Three mechanisms are available; the SDK supports the first two and documents the third:

- **Per-request timeout**: `timeout:` constructor option default `60` (seconds) — applied to the whole attempt (network + parse). Per-call override via the per-method `timeout:` kwarg. Internally maps to `Net::HTTP#open_timeout`, `#read_timeout`, `#write_timeout`.
- **`Timeout.timeout` wrapping** (caller-side, stdlib): user can wrap any client call:
  ```ruby
  begin
    pdf = Timeout.timeout(10) { client.render.pdf(input) }
  rescue Timeout::Error
    # ... handle the deadline
  end
  ```
  We do not raise `PoliPage::TimeoutError` from `Timeout.timeout` — that's the caller's exception type, not ours. Document this in the README.
- **`Thread#raise` from another thread** (caller-side, advanced): user spawns the SDK call in a thread, then `thread.raise(PoliPage::AbortedError)` from another. The SDK does not provide this directly because it's a heavyweight pattern most callers don't need.

**Error mapping** (port the abort-vs-timeout distinction from Node `index.ts:209-218`):

- `Net::OpenTimeout` / `Net::ReadTimeout` / `Net::WriteTimeout` → `PoliPage::TimeoutError.new(timeout: ...)`. Retryable.
- `SocketError`, `Errno::ECONNREFUSED`, `Errno::ECONNRESET`, `Errno::ETIMEDOUT`, `OpenSSL::SSL::SSLError` → `PoliPage::ConnectionError.new(message:, cause:)`. Retryable.
- `Timeout::Error` from user-side `Timeout.timeout` wrapping → propagates as-is; the SDK does NOT translate it (the user opted in).
- `Interrupt` (Ctrl-C) / signal-raised exceptions → propagate as-is. The SDK never silences them.

**Documents methods do not accept per-call cancellation overrides.** They use the client-level `timeout:` as passed. Mirrors Node, which only puts `signal:` on `BaseRenderInput`.

**Mid-sleep cancellation**: `Kernel#sleep` returns early when the thread receives a signal (`Thread#raise`, `Process.kill(:USR1, pid)`, etc.). The retry-sleep loop is therefore interruptible by the standard Ruby mechanisms. Port Node's `#sleep` behavior at `index.ts:245-260` — Ruby's blocking sleep gives us partial cancellation without extra plumbing.

---

## 9. Type system (Ruby-specific)

### 9.1 Project-mode enforcement via required kwargs + RBS

Spec §4.1 requires "compile-time" enforcement that `render.pdf` / `pdf_stream` / `document` accept project mode only. Ruby has no compile time — the closest primitives:

1. **Required kwargs** (Ruby 2.0+): `def pdf(project:, template:, data:, ...)` raises `ArgumentError: missing keyword: :project` immediately at call time if omitted. This is Ruby's strongest single-language enforcement primitive — the call doesn't even reach the method body.
2. **RBS type signatures** (Ruby 3.0+ official): shipped in `sig/poli_page/render.rbs`; consumers using Steep or Sorbet (via `sorbet-rbs`) get static errors at type-check time.
3. **Runtime validation in the method body**: defense in depth — `raise PoliPage::InvalidOptionsError` if `project` is nil or empty string.

```ruby
module PoliPage
  module Resources
    class Render
      # render.pdf REQUIRES project mode. The required `project:` kwarg is the enforcement point.
      def pdf(project:, template:, data:, version: nil, format: nil, orientation: nil, locale: nil,
              metadata: nil, idempotency_key: nil, timeout: nil)
        validate_project_mode!(project: project, template: template)
        # ... send request ...
      end

      def pdf_stream(project:, template:, data:, version: nil, format: nil, orientation: nil, locale: nil,
                     metadata: nil, idempotency_key: nil, timeout: nil, &block)
        validate_project_mode!(project: project, template: template)
        # ... stream ...
      end

      def document(project:, template:, data:, version: nil, format: nil, orientation: nil, locale: nil,
                   metadata: nil, idempotency_key: nil, timeout: nil)
        validate_project_mode!(project: project, template: template)
        # ... send request, return DocumentDescriptor ...
      end

      # render.preview accepts BOTH modes; project: is optional.
      def preview(template:, data: nil, project: nil, version: nil, format: nil, orientation: nil,
                  locale: nil, metadata: nil, idempotency_key: nil, timeout: nil)
        # ... send request, return PreviewResult ...
      end

      private

      def validate_project_mode!(project:, template:)
        if project.nil? || project.to_s.empty?
          raise PoliPage::InvalidOptionsError.new(
            "project is required for render.pdf/pdf_stream/document — inline mode is only supported on render.preview",
            code: PoliPage::ErrorCodes::PROJECT_REQUIRED_FOR_DOCUMENT
          )
        end
        if template.nil? || template.to_s.empty?
          raise PoliPage::InvalidOptionsError.new(
            "template (slug) is required",
            code: PoliPage::ErrorCodes::MISSING_TEMPLATE_SLUG
          )
        end
      end
    end
  end
end
```

`client.render.pdf(template: "...", data: {})` raises `ArgumentError` immediately (Ruby itself) — the SDK doesn't even need to run code. With Steep/Sorbet, this is also a static type error from the RBS signatures.

**Type names mirror Node**: `ProjectModeInput`, `InlineModeInput` — same names as Python (§9.1), Go (§9.1), PHP (§9.1), and Rust (§9.1) so spec users navigating multiple languages find familiar identifiers.

### 9.2 Nullable wire fields → nil-by-default Ruby attributes

Every JSON `string | null` field maps to a nilable Ruby attribute on the `Data.define` value object. `nil` ↔ `null` translation is Ruby-native — `JSON.parse` returns Ruby `nil` for JSON `null`, and `JSON.generate(nil) == "null"`. Outbound: `Hash#compact` strips nils so the wire body doesn't include `"field": null` (saves bytes, matches Node's `omitempty` equivalent).

No `Option<T>` / `Optional[str]` / `Ptr<T>` helper needed — Ruby's `nil` is the language primitive.

### 9.3 Linters and static checks

- **`rubocop`** with `rubocop-rspec` plugin. Pinned major in the Gemfile. CI-enforced + pre-push hook.
- **`steep`** for static type-checking against RBS sigs. CI step; `bundle exec steep check`. Fails on any error.
- **`rbs validate`** to syntax-check the sig files themselves.
- **`yard --fail-on-warning`** for doc-comment hygiene.
- **`gem build --strict` + `gem-release`-style checks** to catch manifest issues at build time.

Configure `.rubocop.yml` with `TargetRubyVersion: 3.2` (the MSRV) so syntax-sugar rules don't flag valid code on the floor version.

### 9.4 YARD documentation requirements

Ruby's docs system uses YARD tags inside `#` comments above each definition.

- **Every public method and class must have a YARD doc comment.** Includes `@param`, `@return`, `@raise`, and `@example`.
- One-line summary, blank line, then longer description.
- `@example` blocks are NOT executed by default (unlike Rust's doctests). For executable examples, write a spec under `spec/examples/` that runs the README snippets through `eval`. (Optional; YARD's `@example` is checked for syntax-validity by `yard --fail-on-warning`.)
- `rubydoc.info` automatically builds and hosts YARD HTML for every published gem version — zero config beyond `.yardopts` in the repo root.
- For internal docs (the `Internal::` namespace), use `# @api private` to hide from public YARD output.

```ruby
# Render a PDF and return the bytes.
#
# This is two HTTP calls under the hood: POST /v1/render produces a stored document,
# then the SDK fetches the presigned PDF URL and returns the bytes.
#
# @param project           [String]  project slug
# @param template          [String]  template slug (project mode)
# @param data              [Hash]    template data
# @param version           [String, nil]  exact semver (e.g. "1.0.0") or "draft"; omitted = default per key type
# @param format            [String, nil]  one of PoliPage::PageFormat; default A4
# @param orientation       [String, nil]  "portrait" or "landscape"; default portrait
# @param locale            [String, nil]  BCP 47 (e.g. "en-US")
# @param metadata          [Hash{String=>String,Numeric,Boolean}, nil]
# @param idempotency_key   [String, nil]  caller-supplied UUID; auto-generated if nil
# @param timeout           [Numeric, nil] per-call timeout in seconds; overrides the client default
#
# @return [String] raw PDF bytes (binary-encoded String)
#
# @raise [PoliPage::ValidationError]
# @raise [PoliPage::AuthenticationError]
# @raise [PoliPage::RateLimitError]
# @raise [PoliPage::TimeoutError]
#
# @example
#   pdf = client.render.pdf(
#     project: "billing",
#     template: "invoice",
#     version: "1.0.0",
#     data:    { invoice_number: "INV-001" }
#   )
#   File.binwrite("invoice.pdf", pdf)
def pdf(project:, template:, data:, ...)
  # ...
end
```

---

## 10. Observability

Modern Ruby SDKs ship **stdlib `Logger` injection as the primary observability mechanism**, with SDK-level hooks reserved for retry/error decisions. We follow the same pattern (matches stripe-ruby `Stripe.logger`, anthropic-sdk-ruby `Anthropic::Client.new(logger:)`).

### 10.1 Logger integration

```ruby
client = PoliPage::Client.new(
  api_key: ENV.fetch("POLI_PAGE_API_KEY"),
  logger:  Logger.new($stdout).tap { |l| l.level = Logger::DEBUG }
)
```

- **Silent by default**: if `logger:` is nil, no events emit. No `puts` or `STDERR` writes anywhere in the SDK.
- **One DEBUG event per HTTP attempt** (method, url, attempt). One INFO event per response (status, duration_ms, request_id). One WARN event per retry. One ERROR event per terminal failure.
- **Log level via env var**: `POLI_PAGE_LOG=debug|info|warn|error` overrides the level on the injected logger (or, if no logger is set, configures a default `Logger.new($stderr)` at the requested level). Matches stripe-ruby's `STRIPE_LOG`.
- **Redaction**: never include the `Authorization` header value in any field, never include the api_key in any structured field. Body content is not logged.
- Works seamlessly with `lograge`, `ougai` (structured JSON logging), `semantic_logger`, etc. — any `Logger`-compatible object can be injected.

### 10.2 SDK-level hooks (`on_retry`, `on_error` only)

Set via constructor kwargs:

```ruby
client = PoliPage::Client.new(
  api_key:  ENV.fetch("POLI_PAGE_API_KEY"),
  on_retry: ->(event) { Statsd.increment("polipage.retry", tags: ["status:#{event.reason.status}"]) },
  on_error: ->(err)   { Sentry.capture_exception(err) }
)
```

Hooks are `Proc`/`Lambda` objects — synchronous callbacks. Users wanting async work in a hook can `Thread.new { ... }` inside the hook themselves.

**Hooks must never break the request** — every hook invocation is wrapped in `rescue StandardError`:

```ruby
def fire_hook(hook, event)
  return unless hook
  hook.call(event)
rescue StandardError => e
  # Swallow the hook's exception — hooks must not break the request. Mirrors Node #fireHook.
  @logger&.warn("polipage hook raised: #{e.class}: #{e.message}")
end
```

We deliberately rescue only `StandardError` (not `Exception`) so signals (`Interrupt`, `SystemExit`) propagate normally.

Port Node `index.ts:106-113`.

**Timing** (port Node `index.ts` firing points at lines 163, 168):

- `on_retry` fires before each retry sleep, with the delay and the error that triggered the retry.
- `on_error` fires once at terminal failure — retries exhausted, non-retryable error, or aborted.

`on_request` / `on_response` from earlier drafts are **dropped** — users who want request/response inspection inject a verbose `Logger` instead, or wrap the client in their own middleware-style layer.

**Event types**:

```ruby
RetryEvent = Data.define(:attempt, :delay, :reason)
#   attempt [Integer] 1-based; the attempt about to be made
#   delay   [Float]   sleep duration in seconds before this attempt
#   reason  [PoliPage::Error] error that triggered the retry
```

`on_error` receives the `PoliPage::Error` instance directly (no event wrapper), mirroring Node `onError?: (err: PoliPageError) => void`.

---

## 11. File helper (spec §2, §5.1 last paragraph)

```ruby
# lib/poli_page/render_to_file.rb

module PoliPage
  class Client
    # Render a PDF and stream the bytes to the given path.
    # Creates parent directories if missing. Overwrites existing files.
    # Behavior parity with Node's `renderToFile`.
    #
    # @param path     [String, Pathname]
    # @param kwargs   forwarded to {Resources::Render#pdf_stream}
    # @raise [PoliPage::InvalidOptionsError] on filesystem failure
    # @raise (any error raised by {Resources::Render#pdf_stream})
    def render_to_file(path, **kwargs)
      pathname = Pathname(path)
      FileUtils.mkdir_p(pathname.dirname) unless pathname.dirname.directory?

      File.open(pathname, "wb") do |io|
        render.pdf_stream(**kwargs) { |chunk| io.write(chunk) }
      end
      nil
    rescue Errno::EACCES, Errno::ENOSPC, Errno::EISDIR => e
      raise PoliPage::InvalidOptionsError.new(
        "failed to write to #{pathname}: #{e.class}: #{e.message}",
        code: "invalid_options"
      )
    end
  end
end
```

Method on `Client` (matches spec §2 — `render_to_file`). Streams chunks via `Net::HTTP#read_body`; bounded memory regardless of PDF size. `Pathname` is stdlib; works on Linux, macOS, Windows.

`path` accepts `String` or `Pathname` — `Pathname(path)` is the Ruby idiom for "coerce to path" (handles both).

---

## 12. Repository, build, and packaging

### 12.1 Repo

- Name: `sdk-ruby` under the `poli-page` org on GitHub.
- License: **MIT** (matches Node/Python/Go/PHP — Ruby ecosystem doesn't have the Rust-style dual-license norm).
- Default branch: `main`.
- Single gem, no monorepo at v1.0.

### 12.2 Layout

See §3.1.

### 12.3 gemspec essentials

```ruby
# poli-page.gemspec
require_relative "lib/poli_page/version"

Gem::Specification.new do |s|
  s.name          = "poli-page"
  s.version       = PoliPage::VERSION
  s.summary       = "Poli Page SDK for Ruby — render PDFs from HTML templates via the Poli Page API"
  s.description   = "Official Ruby client for Poli Page. Renders PDFs, previews, and thumbnails via api.poli.page."
  s.authors       = ["Poli Page"]
  s.email         = "support@poli.page"
  s.homepage      = "https://poli.page"
  s.license       = "MIT"
  s.required_ruby_version = ">= 3.2"

  s.metadata = {
    "homepage_uri"          => "https://poli.page",
    "source_code_uri"       => "https://github.com/poli-page/sdk-ruby",
    "changelog_uri"         => "https://github.com/poli-page/sdk-ruby/blob/main/CHANGELOG.md",
    "documentation_uri"     => "https://rubydoc.info/gems/poli-page",
    "bug_tracker_uri"       => "https://github.com/poli-page/sdk-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir["lib/**/*.rb"] + Dir["sig/**/*.rbs"] +
            %w[LICENSE README.md CHANGELOG.md MIGRATION.md SECURITY.md]
  s.require_paths = ["lib"]

  # NO runtime deps. Stdlib only.
end
```

**`Gemfile.lock` IS committed.** The Bundler convention for libraries used to be "don't commit `Gemfile.lock`" so consumers got fresh resolutions; the modern convention (since Bundler 2.0) is to commit it for reproducible contributor and CI builds. Consumers using the gem still get their own `Gemfile.lock` from their app. Match anthropic-sdk-ruby and stripe-ruby (both commit).

**`required_ruby_version = ">= 3.2"`** is the MSRV. Bumps to the MSRV are MINOR-version releases with a clear note in `MIGRATION.md` (engineering guide §3.3).

**`rubygems_mfa_required = "true"`** in the gemspec metadata enforces MFA for any push to this gem. Set once; RubyGems will reject pushes from non-MFA-protected accounts.

### 12.4 Distribution

Ruby gems are distributed via RubyGems.org (`rubygems.org`). `gem push` uploads the `.gem` artifact; the registry preserves it immutably and indexes the metadata. Users `gem install poli-page` (or add `gem "poli-page"` to their `Gemfile`); Bundler resolves from the index, downloads the `.gem`, installs into the project's bundle path.

The published artifact is the `.gem` file (a tar containing `data.tar.gz` + `metadata.gz`) — fully introspectable via `gem unpack poli-page-1.0.0.gem` and `gem spec poli-page-1.0.0.gem`. Users can inspect the source of any published version at `rubygems.org/gems/poli-page/versions/1.0.0` — same transparency model Go's `proxy.golang.org` and crates.io provide.

**`rubydoc.info` auto-builds** every published version's YARD output and hosts the HTML at `rubydoc.info/gems/poli-page/<version>` — zero config beyond `.yardopts` at the repo root. This is the canonical Ruby docs site; users land there from `gem server`, `bundle info poli-page --path`, and any link in the README / gemspec's `documentation_uri` field.

### 12.5 Release process (per engineering guide §6.1)

The **`scripts/release.sh` is the primary publishing path** — a maintainer-driven flow that gates the release on lint/test/confirm-prompt before `gem push` + tag push.

1. Bump `VERSION` in `lib/poli_page/version.rb`.
2. Update `CHANGELOG.md` (move `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD`).
3. If a MAJOR bump, add a section to `MIGRATION.md`.
4. Commit on `main` (`chore(release): vX.Y.Z`).
5. Run `scripts/release.sh` locally:
   - Assert on `main`, working tree clean, target `vX.Y.Z` tag does not yet exist
   - `bundle install --frozen`
   - `bundle exec rubocop`
   - `bundle exec rbs validate && bundle exec steep check`
   - `bundle exec rspec`
   - `bundle exec yard --fail-on-warning`
   - `bundle audit check --update`
   - Integration tests if `POLI_PAGE_API_KEY` set: `INTEGRATION=1 bundle exec rspec spec/integration`
   - `ruby examples/demo.rb` end-to-end smoke against develop
   - `gem build poli-page.gemspec` and inspect the contents + total size
   - prompt for confirmation
6. On confirmation: `gem push poli-page-X.Y.Z.gem` (reads token from `~/.gem/credentials`; MFA prompts via OTP).
7. Wait for the gem to appear on RubyGems (~30 seconds).
8. `git tag vX.Y.Z && git push origin vX.Y.Z`. (Tag push is **after** publish, not before — the tag commemorates the published version. Mirrors anthropic-sdk-ruby / stripe-ruby.)
9. `rubydoc.info` auto-builds within ~5 minutes; the GitHub Pages docs deploy on the push-to-main that triggered the release commit.
10. Optionally `gh release create vX.Y.Z --notes-from-tag` for the GitHub Release page.

**No automatic publish workflow.** RubyGems does not yet support OIDC / Trusted Publishing (the [RFC #61](https://github.com/rubygems/rfcs/pull/61) was in active design at plan time). The maintainer's local `~/.gem/credentials` is the credential boundary — same posture as Go's manual `git push origin vX.Y.Z`, PHP's manual tag push, and Rust's manual `cargo publish`. The engineering guide §6.4 "no auto-publish on tag push" rule is structurally satisfied because we don't push the tag until after the manual publish succeeds.

### 12.6 Release discipline (per engineering guide §3)

**SemVer 2.0.0** (§3.1). Pre-1.0 versions MAY break in minor bumps. From v1.0 onward: MAJOR for breaking changes to the contract or public API, MINOR for backwards-compatible additions, PATCH for bug fixes. Breaking-change detection: there's no `cargo public-api`-equivalent for Ruby, so we rely on (a) the test suite asserting current public surface and (b) human review of the changelog before each bump.

**CHANGELOG discipline** (§3.2). Update `CHANGELOG.md` in the **same commit** as the version bump. Use Keep a Changelog sections (`Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`). **Mark breaking changes with `**BREAKING**:`** — cross-SDK convention.

**MIGRATION.md authoring** (§3.3). Every MAJOR bump SHOULD add a section to `MIGRATION.md` describing what changed and how to adapt. MSRV bumps within a minor version also get a `MIGRATION.md` note.

**Prerelease channel** (§3.4). RubyGems uses semver prerelease suffixes natively (`1.0.0.rc.1`, `2.0.0.beta.0`). Note Ruby's convention uses `.` separators (not `-`), so `1.0.0.rc.1` not `1.0.0-rc.1`. `gem install poli-page` ignores prereleases by default; users opt in via `gem install poli-page --pre` (any prerelease) or pin explicitly via `gem "poli-page", "1.0.0.rc.1"` in the Gemfile. Promotion flow:

1. Bump `VERSION` to the prerelease form (e.g., `2.0.0.rc.1`). Move CHANGELOG entries under that heading.
2. Run `scripts/release.sh`. On confirmation, `gem push` uploads it as a prerelease (RubyGems detects the `.rc.` / `.beta.` / `.alpha.` suffix automatically).
3. Tag `v2.0.0.rc.1` and push the tag.
4. When ready, bump `VERSION` to the stable form (drop the suffix), move CHANGELOG entries to the stable heading, run `scripts/release.sh` again, push the stable tag.

Stable and prerelease tags MUST never point at the same commit — once a prerelease is promoted, the next prerelease starts a new pre-suffix sequence.

**License**: **MIT** (`LICENSE` file at repo root; `license = "MIT"` in the gemspec). This matches Node/Python/Go/PHP. Ruby ecosystem doesn't have the Rust-style dual MIT/Apache-2.0 norm; single MIT is the prevailing convention (stripe-ruby, octokit, anthropic-sdk-ruby, openai-ruby, sidekiq all ship MIT-only).

---

## 13. Build order (phases)

**7 phases**, matching Go, PHP, and Rust (no separate async-client phase — async is deferred post-1.0). Each phase ends in a green CI run and a usable artifact.

### Phase 0 — Repo init + tooling skeleton

- `poli-page.gemspec` with metadata, MSRV (3.2), MFA required, zero runtime deps.
- `lib/poli_page.rb` with `module PoliPage; end` and version require.
- `lib/poli_page/version.rb` with `VERSION = "0.0.1"` (the pre-1.0 placeholder).
- `Gemfile` pointing at the gemspec; dev deps: `rspec`, `webmock`, `vcr`, `rubocop`, `rubocop-rspec`, `yard`, `rbs`, `steep`, `simplecov`, `bundler-audit`.
- `Rakefile` with default task = `rubocop + steep + rspec`.
- `.rubocop.yml`, `.yardopts`, `.rspec`, `.ruby-version`.
- `spec/spec_helper.rb` with WebMock + SimpleCov + RSpec config.
- `spec/poli_page_spec.rb` with one assertion: `expect(PoliPage::VERSION).to be_a(String)`.
- `.github/workflows/ci.yml`: matrix ruby 3.2 / 3.3 / 3.4 on ubuntu-latest; one job each on macOS-latest and windows-latest with 3.4.
- `Gemfile.lock` committed.
- README skeleton.

Deliverable: green CI on an empty gem.

### Phase 1 — Transport core + error type

- `lib/poli_page/errors.rb`: `Error` base + subclasses (see §7) + predicates (including `auth_error?` covering 401+403, §7.1) + `ErrorCodes` module with all the constants (reserved per §7.2 + known API per §7.4; do NOT include `STORAGE_REQUIRED`).
- `lib/poli_page/internal/http.rb`: pure module functions matching Node `internal/http.ts`:
  - `build_url(base, path)`, `build_headers(method:, api_key:, idempotency_key:, user_agent:)`
  - `parse_error_body(body, status)` with the `code → message → error → 'unknown_error'` fallback chain
  - `compute_backoff(attempt:, base_delay:, retry_after: nil)` — retry_after as-is when given, else `base * 2**(attempt-1) * (0.5 + rand)`
  - `parse_retry_after(header_value)` — accepts integer seconds or HTTP-date via `Time.httpdate(...)`, capped at 30 s
  - `classify(status:, code:, message:, request_id:)` — returns the correct `PoliPage::Error` subclass instance
- `lib/poli_page/internal/uuid.rb`: thin wrapper over `SecureRandom.uuid` (one line; in its own module so future swap is easy).
- `lib/poli_page/internal/constants.rb`: API paths (`PATH_RENDER`, `PATH_DOCUMENT`, etc.), defaults (`DEFAULT_BASE_URL`, `DEFAULT_MAX_RETRIES`, `DEFAULT_RETRY_DELAY`, `DEFAULT_TIMEOUT`, `RETRY_AFTER_CAP`), header name constants.
- `lib/poli_page/internal/wire.rb`: `to_wire` + `from_wire` (§5.4).
- `lib/poli_page/internal/transport.rb`: `Net::HTTP` wrapper (§3.2) with exception translation.
- Unit specs porting `tests/internal/http.test.ts` 1:1 into `spec/poli_page/internal/http_spec.rb`.

Deliverable: 100% unit-tested pure transport core, byte-for-byte behavior parity with Node `internal/http.ts`.

### Phase 2 — Client + `render.preview`

- `lib/poli_page/client.rb`: `Client.new(api_key:, ...)`, `attr_reader :render, :documents`, retry loop wiring, hook firing, thread-safety.
- `lib/poli_page/render.rb`: `Resources::Render` class + `preview` method (simplest).
- `lib/poli_page/models/preview_result.rb`: `Data.define(:html, :total_pages, :environment)`.
- `lib/poli_page/inputs/project_mode_input.rb` + `inline_mode_input.rb`: convenience `Data.define` value objects.
- `lib/poli_page/models/page_format.rb`: `FORMATS = Set["A3", "A4", ...].freeze`.
- `lib/poli_page/models/orientation.rb`: `ORIENTATIONS = Set["portrait", "landscape"].freeze`.
- `spec/poli_page/render_spec.rb` with WebMock stubs.
- Integration spec (gated on `POLI_PAGE_API_KEY` env var + `INTEGRATION=1`) hitting `api-develop.poli.page`.

Deliverable: working `client.render.preview(...)` against develop.

### Phase 3 — `render.pdf`, `render.pdf_stream`, `render.document`

- `lib/poli_page/render.rb`: `pdf`, `pdf_stream` (block + Enumerator forms), `document` methods.
- Two-hop logic for `pdf`: POST `/v1/render` → GET `presigned_pdf_url`.
- Streaming via `Net::HTTP#request_get { |response| response.read_body { |chunk| yield chunk } }`.
- `lib/poli_page/models/document_descriptor.rb`: `Data.define` + `#download_pdf` method + client back-reference.
- Unit + integration specs.

Deliverable: full `render.*` namespace.

### Phase 4 — Documents namespace

- `lib/poli_page/documents.rb`: `get`, `preview`, `thumbnails`, `delete`.
- Wire-body wrap for thumbnails; response unwrap.
- `lib/poli_page/models/document_preview_result.rb`: `Data.define(:html, :page_count)` (note: `page_count`, NOT `total_pages`).
- `documents.preview` parses text/html body + `X-Document-Page-Count` header (mirror Node `8523e13` fix).
- URL-encoded path interpolation via `CGI.escape(id)`.
- Unit + integration specs.

Deliverable: full public surface complete.

### Phase 5 — File helper + examples

- `lib/poli_page/render_to_file.rb`: `Client#render_to_file(path, **kwargs)`.
- `examples/demo.rb`: runnable end-to-end demo.
- **Method order** (per `sdk-node/demo/README.md` "Notes for SDK porters"):
  `render.pdf` → `render.pdf_stream` → `render_to_file` → `render.preview` → `render.document` → `documents.get` → `documents.thumbnails` → `documents.preview` → `documents.delete` → trigger an error path at the bottom (bad key → `rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError => e` → print `e.code`, `e.status`, `e.request_id` + the predicate helpers).
- **Shared template**: copy `sdk-node/demo/templates/invoice/` into `examples/templates/invoice/` for cross-language byte-diffability.
- **API key resolution** in `examples/shared.rb` mirroring `_shared.mjs`:
  1. `ENV["POLI_PAGE_API_KEY"]` if set.
  2. Read `.env` at the workspace root (parsed manually — ~20 lines, no `dotenv` dep).
  3. Interactive prompt via `$stdin.gets` with the same instructional copy as the Node demo. Append to `.env` after successful entry so future runs are silent.
- Use `getting-started/welcome/1.0.0` as the default template.

Deliverable: `ruby examples/demo.rb` produces a PDF byte-equivalent to the Node demo's `render.pdf` output.

### Phase 6 — Docs + first RC tag

- `README.md`: full content mirroring `sdk-node/README.md` (Install → Quick start → Preview inline HTML → Write a PDF to disk → Try locally → Stream → Working with stored documents → Authentication → Methods table → Configuration → Error handling → Cancellation → Observability → Retries & idempotency → Type system → Runtime support → Requirements → Docs & support → License). Include code that runs against the current API.
- `CHANGELOG.md`: 1.0.0 entry.
- `MIGRATION.md`: placeholder + note that 1.0.0 is the first stable.
- `SECURITY.md`: copy from sdk-node.
- `CONTRIBUTING.md`: Ruby-specific (bundle install, bundle exec rubocop, bundle exec rspec, install-hooks.sh).
- Add YARD `@example` blocks to every public method.
- `sig/poli_page/*.rbs`: RBS sigs for the public surface.
- Bump `VERSION` to `"1.0.0.rc.1"`, move CHANGELOG entries.
- Run `scripts/release.sh` with version `1.0.0.rc.1`. Confirm at prompt; publish to RubyGems as prerelease.
- Push tag `v1.0.0.rc.1`. Verify `gem install poli-page --pre` works from a fresh machine. Verify `https://rubydoc.info/gems/poli-page/1.0.0.rc.1` builds and renders.

Deliverable: installable RC, rubydoc.info indexing verified.

### Phase 7 — v1.0.0

- After RC validation, bump `VERSION` to `"1.0.0"` in `lib/poli_page/version.rb`, move CHANGELOG `[Unreleased]` → `[1.0.0] - YYYY-MM-DD`, commit (`chore(release): v1.0.0`).
- Run `scripts/release.sh` locally (primary path per §16.3). Confirm at the prompt.
- After publish succeeds: push the `v1.0.0` git tag (`git push origin v1.0.0`).
- (Optional) `gh release create v1.0.0 --notes-from-tag` to create the GH Release page with changelog excerpt.
- Confirm `gem install poli-page` resolves `1.0.0` on a clean machine.
- Visit `https://rubydoc.info/gems/poli-page/1.0.0` and confirm YARD renders all public symbols.
- Update Node + Python + Go + PHP + Rust SDK READMEs to mention the Ruby sibling. Update `sdk-roadmap.md` to add a Ruby row.

Deliverable: 1.0.0 on RubyGems.

---

## 14. Testing strategy

### 14.1 Unit specs (`spec/poli_page/`)

- **`WebMock`** for HTTP mocking — intercepts at the `Net::HTTP` socket layer; no transport-injection seam needed.
- **`VCR`** for select integration-style tests that record/replay against develop (used sparingly; most unit tests use raw WebMock stubs).
- Cover every error code path.
- Test retry loop: backoff math, max attempts, Retry-After honoring (30-second cap, past dates, far-future dates, unparseable values), jitter bounds (`[0.5, 1.5)` factor over 200 samples — port `http.test.ts:83-93`).
- Test wire translation via round-trip on every input shape (snake_case kwargs → camelCase JSON → camelCase JSON response → snake_case Hash).
- Test the required-kwarg enforcement: `expect { client.render.pdf(template: "x", data: {}) }.to raise_error(ArgumentError, /missing keyword: :project/)`.
- Test `parse_error_body` fallback chain (`code → message → error → 'unknown_error'`) including HTML error pages and empty bodies — port `http.test.ts:108-152`.
- Test `auth_error?` returns `true` for both 401 (`AuthenticationError`) and 403 (`PermissionDeniedError`).
- Test every spec §7.2 code (currently ~21 entries) round-trips through to `err.code` verbatim with `request_id` propagated — port `tests/error-codes.test.ts` 1:1.
- Test thread safety: ten threads concurrently calling `client.render.preview(...)` with WebMock stubs, no shared-state corruption.

### 14.2 Integration specs (`spec/integration/`)

- Run with `INTEGRATION=1 bundle exec rspec spec/integration`.
- Each integration spec checks `ENV["POLI_PAGE_API_KEY"]` and `skip "set POLI_PAGE_API_KEY"` if missing.
- Hit `api-develop.poli.page` with a `pp_test_*` key.
- Cover the happy path of every method against the real API.
- Use `getting-started/welcome` as the test template.
- Tolerate `total_pages == 0` for short inline previews (mirror Node's `30cf4fd` fix).
- Run in CI on push to main + nightly; not on every PR (cost + flakiness).

### 14.3 YARD example syntax-check

- `bundle exec yard --fail-on-warning` parses all `@example` blocks for syntactic validity. Doesn't execute them, but catches typos.
- For a stricter version, add `spec/examples_spec.rb` that `eval`s each `@example` block in a sandbox — defer post-1.0 unless examples are routinely breaking.

### 14.4 RBS / Steep validation

- `bundle exec rbs validate` — syntax-checks the sig files.
- `bundle exec steep check` — type-checks `lib/` against `sig/`. Configured in `Steepfile`.
- A small consumer test under `spec/typecheck/` that uses Steep programmatically to verify that obviously-wrong calls (e.g., `client.render.pdf(template: "x")` without `project:`) report type errors. Equivalent in spirit to Rust's `trybuild`.

### 14.5 Test parity matrix

| Node test file | Ruby equivalent |
|---|---|
| `tests/render.test.ts` | `spec/poli_page/render_spec.rb` |
| `tests/documents.test.ts` | `spec/poli_page/documents_spec.rb` |
| `tests/error.test.ts` | `spec/poli_page/errors_spec.rb` |
| `tests/error-codes.test.ts` | `spec/poli_page/error_codes_spec.rb` |
| `tests/index.test.ts` | `spec/poli_page/client_spec.rb` |
| `tests/internal/http.test.ts` | `spec/poli_page/internal/http_spec.rb` |
| `tests/isomorphism.test.ts` | n/a (Ruby is one runtime; gem-build install-smoke covers the boundary) |
| `tests/node.test.ts` | `spec/poli_page/render_to_file_spec.rb` |
| `tests/types.test-d.ts` | `spec/typecheck/` (Steep-driven) |
| `tests/integration/*` | `spec/integration/*_spec.rb` (gated by `INTEGRATION=1`) |

---

## 15. Documentation

- **README.md**: port `sdk-node/README.md` section by section, swap idioms (TypeScript → Ruby). Keep the structure: Install → Quick start → Preview inline HTML → Write a PDF to disk → Try it locally → Stream → Working with stored documents → Authentication → Methods table → Configuration → Error handling → Cancellation → Observability → Retries & idempotency → Type system (RBS / Sorbet) → Runtime support → Requirements → Docs & support → License.
- **Methods table**: every public method with return type and one-line description.
- **Configuration table**: every constructor kwarg with type, default, description.
- **API reference site**: `rubydoc.info/gems/poli-page` auto-generates from YARD. Zero config beyond `.yardopts`. Link prominently from README.
- **GitHub Pages YARD deploy**: `.github/workflows/docs.yml` builds YARD on push to `main` and deploys to `docs.poli.page/reference/sdk/ruby/` (via Pages CNAME) for symmetry with the Node SDK's TypeDoc site.

---

## 16. CI/CD

### 16.1 ci.yml (every push + PR)

- Matrix: `{ ruby: ['3.2', '3.3', '3.4'], os: [ubuntu-latest] }` + one job each on `macos-latest` and `windows-latest` with `ruby '3.4'`. Matches engineering guide §4.1.
- Setup: `ruby/setup-ruby@<sha>` (de facto action for installing Ruby in GH Actions, pin to SHA per §16.6) with `bundler-cache: true`.
- Steps:
  1. `bundle install --frozen` (asserts `Gemfile.lock` is fresh)
  2. `bundle exec rubocop`
  3. `bundle exec rbs validate`
  4. `bundle exec steep check`
  5. `bundle exec yard --fail-on-warning`
  6. `bundle exec rspec spec` (unit suite; skips `spec/integration`)
  7. `bundle audit check --update`
  8. `gem build poli-page.gemspec`
  9. **Consumer-gem install smoke** (mirrors Node CI install-smoke):
     - `mkdir /tmp/smoke && cd /tmp/smoke`
     - `gem install $GITHUB_WORKSPACE/poli-page-*.gem --no-document`
     - `ruby -r poli_page -e 'PoliPage::Client.new(api_key: "test"); puts PoliPage::VERSION'`
     - Fails CI if the consumer require breaks.
- Integration tests are a separate workflow `integration.yml`, scheduled nightly and on push to main, gated by `secrets.POLI_PAGE_API_KEY` and `secrets.POLI_PAGE_BASE_URL` (defaulting to `https://api-develop.poli.page`). Honor `POLI_PAGE_TEST_PROJECT` / `POLI_PAGE_TEST_TEMPLATE` / `POLI_PAGE_TEST_VERSION` env vars (mirror the Node integration tests).
- **npm-script → bundle-task mapping** (for porters cross-referencing `sdk-node/package.json`):

  | Node script | Ruby equivalent |
  |---|---|
  | `lint` | `bundle exec rubocop` |
  | `format` | `bundle exec rubocop --autocorrect` |
  | `typecheck` | `bundle exec steep check` |
  | `test` | `bundle exec rspec spec` |
  | `test:types` | `bundle exec rspec spec/typecheck` |
  | `test:integration` | `INTEGRATION=1 bundle exec rspec spec/integration` |
  | `build` | `gem build poli-page.gemspec` |
  | `lint:pack` | `gem build poli-page.gemspec && gem unpack *.gem && diff -r ...` |
  | `size` | n/a (Ruby source is shipped as-is; small surface) |
  | `prepare` | `scripts/install-hooks.sh` writes `.git/hooks/pre-push` |

### 16.2 No release workflow (RubyGems-side)

There is no `release.yml`. RubyGems.org has no Trusted Publishing / OIDC support yet; `gem push` requires a long-lived API key. The key lives in the maintainer's `~/.gem/credentials` (chmod 600) and never enters CI. The release flow is `scripts/release.sh` → `gem push` → `git tag` → `git push origin <tag>` — all manual, all local. This matches Go / PHP / Rust postures.

If RubyGems ever ships Trusted Publishing ([RFC #61](https://github.com/rubygems/rfcs/pull/61)), a future `publish.yml` workflow can be added as the signed-attestation augment (per engineering guide §6.3) — but `scripts/release.sh` stays the primary path.

### 16.3 release.sh (primary publishing path — per engineering guide §6.1)

Mirror `sdk-node/scripts/publish.sh` shape:

1. **Pre-flight**: assert on `main`, working tree clean, target `vX.Y.Z` tag does not yet exist locally or on the remote, `~/.gem/credentials` is present.
2. **Verify**: `bundle exec rubocop` + `bundle exec rbs validate && bundle exec steep check` + `bundle exec yard --fail-on-warning` + `bundle exec rspec spec` + `bundle audit` + integration tests if `POLI_PAGE_API_KEY` set + `ruby examples/demo.rb` end-to-end against develop + `gem build poli-page.gemspec`.
3. **Pack inspect**: `gem unpack poli-page-X.Y.Z.gem` to a temp dir, show contents + total size.
4. **Confirm**: prompt before publishing. Abort cleanly on `n`.
5. **Publish**: `gem push poli-page-X.Y.Z.gem` (no `--dry-run` flag — RubyGems does not support one; the `gem build` + `gem unpack` + inspect step substitutes).
6. **Tag**: `git tag vX.Y.Z && git push origin vX.Y.Z`. (Tag push is after publish; if publish fails we don't want a tag pointing at an unpublished commit.)
7. **`--dry-run` flag** does everything except `gem push` and the tag push.

### 16.4 Pre-push hooks (engineering guide §8)

`.git/hooks/pre-push` installed via `scripts/install-hooks.sh` (idempotent). Hooks: `bundle exec rubocop`, `bundle exec steep check`, `bundle exec rspec spec` (unit only, skips integration). Add a `RUN_INTEGRATION=1` opt-in for full integration runs.

`overcommit` is the Ruby-ecosystem hook manager but it's a heavy dep with a complex config; for an SDK with one hook, a hand-written `pre-push` shell script is simpler and matches the Go / Rust / Python pattern in the fleet.

### 16.5 Docs workflow

`.github/workflows/docs.yml`:
- Triggers: push to `main`, release tag push.
- Steps: `bundle install`, `bundle exec yard`, deploy `doc/` to GitHub Pages (CNAME → `docs.poli.page/reference/sdk/ruby/`).
- Separately, `rubydoc.info` builds on every gem publish automatically — zero config needed for that path.

### 16.6 Supply-chain protections

Mirror the protections added to the Node SDK in commit `bd85a76` ("Adds safety measures against supply chain attacks") and the sibling plans' §16.6. The Ruby ecosystem provides several protections natively; we layer the rest.

**Publish-side**:
- **Manual `gem push` after local `scripts/release.sh` confirmation**. No CI token, no automatic publish workflow. The key lives in `~/.gem/credentials` on the maintainer's machine, **scoped to the `poli-page` gem** via RubyGems UI (`/profile/api_keys → New API Key → Scope: push to a specific gem → poli-page`).
- **RubyGems MFA required**: `rubygems_mfa_required: "true"` in the gemspec metadata enforces server-side; the maintainer's account also has MFA enabled (RubyGems rejects pushes from non-MFA-protected accounts when this metadata is set).
- **RubyGems immutability**: published versions are immutable. Yanking marks a version as broken but doesn't remove it (source remains inspectable). Equivalent in spirit to `proxy.golang.org` + `sum.golang.org` and crates.io's yank-doesn't-delete model.
- **Gem signing**: RubyGems supports OpenSSL-based gem signing (`build --sign-key key.pem`), but the feature is dormant — most published gems don't sign, and Bundler doesn't verify by default. Defer; revisit when RubyGems ships Sigstore/Trusted Publishing.

**Install-side** (CI and dev environments):
- **`Gemfile.lock` committed and used in CI**. Reproducible builds; every dep is content-addressed.
- **`--frozen`** in CI install steps (`bundle install --frozen`). Prevents accidental `Gemfile.lock` regeneration during builds.
- **`bundle config set --local frozen 'true'`** as a default in `CONTRIBUTING.md` so contributors don't accidentally bump deps.

**Dependency surface**:
- **`bundle audit`** in `ci.yml`: `bundle exec bundler-audit check --update`. Fails CI on any RubyGems advisory affecting the resolved dep set. Database auto-updates daily.
- **Dependabot** at `.github/dependabot.yml` with `package-ecosystem: bundler` and `package-ecosystem: github-actions`, weekly schedule, grouped dev-deps.
- **Minimal hard runtime deps** (§5.1): **zero** runtime deps. Dev deps are isolated to the Gemfile and don't ship in the published `.gem`.

**Static analysis**:
- **CodeQL supports Ruby** as of 2023. `.github/workflows/codeql.yml` runs on `push`, `pull_request`, and weekly. Use the "security and quality" query set.
- **RuboCop** with the `rubocop-performance` and `rubocop-security` plugins covers most security-adjacent patterns (open-stat-as-file, eval, command injection).

**Workflow hardening**:
- **Pin GitHub Actions to commit SHAs**, not floating tags. `uses: actions/checkout@<40-char-sha>  # v4.2.2`. Same for `ruby/setup-ruby`, `actions/upload-artifact`, etc.
- **Restrict workflow permissions**. Each job declares only what it needs. `ci.yml` is read-only on contents; `integration.yml` only needs `secrets:` access; `docs.yml` needs `pages: write` only.

**Out of scope for v1.0**:
- SBOM generation (CycloneDX or SPDX). `cyclonedx-ruby` exists; worth adding later, not blocking.
- Sigstore signing of gems. There's no RubyGems-side support yet; [RFC #61](https://github.com/rubygems/rfcs/pull/61) addresses this. Revisit when it ships.

---

## 17. Best practices baked in (Stripe / Anthropic / OpenAI / Octokit playbook)

These are the explicit reasons behind specific decisions above. Keep them in mind as principles, not just rules:

- **Stdlib `Net::HTTP` only** (Anthropic SDK Ruby, modern stripe-ruby): zero runtime deps; no Faraday version conflicts; the supply-chain surface is the Ruby stdlib.
- **Class-hierarchy errors** (stripe-ruby, openai-ruby, anthropic-sdk-ruby, octokit): `rescue PoliPage::AuthenticationError` is the idiomatic Ruby pattern; predicate methods on the base kept for spec parity.
- **Auto-retry with idempotency keys** (Stripe / Anthropic): every POST sends a `SecureRandom.uuid`; callers override via `idempotency_key:`. 5xx + 429 + network + timeout retried; 4xx never.
- **Stdlib `Logger` injection** (stripe-ruby `Stripe.logger`, anthropic-sdk-ruby): the ecosystem-standard logger interface. Silent by default; works with any `Logger`-compatible object (lograge, ougai, semantic_logger).
- **Required kwargs for project-mode enforcement** (Ruby idiom): `def pdf(project:, ...)` raises `ArgumentError` immediately if `project` is omitted. Strongest single-language enforcement Ruby provides.
- **`Data.define` for value objects** (Ruby 3.2+ idiom): immutable, frozen, equality-by-value, pattern-match-friendly. The Ruby-3.2-native equivalent of Rust structs, Python frozen dataclasses, and PHP readonly classes.
- **Constructor kwargs + sensible defaults** (Ruby idiom): `PoliPage::Client.new(api_key:, base_url: "...", max_retries: 2, ...)`. No "builder pattern" — Ruby kwargs are the language primitive.
- **One-client-per-process pattern** (Ruby SDK convention): build one client at startup, pass it around. Documented prominently.
- **Cancellation via `Timeout.timeout` and `Thread#raise`** (Ruby concurrency primitives): no async cancellation token; users wrap with `Timeout` for deadlines or spawn the call in a thread for `Thread#raise` aborts.
- **Stable wire format**: camelCase on the wire (via `Internal::Wire.to_wire`), snake_case in Ruby. The translator is the conversion layer; users never write conversion code.
- **Type-safe inputs via required kwargs + RBS sigs** (Ruby type-system idiom): runtime arg-check + static type-check; defense in depth.
- **`nil` for nullable fields** (Ruby idiom): no `Option<T>` ceremony.
- **Idempotency for state-mutating calls**: every POST gets `Idempotency-Key`; deletes are inherently idempotent (200/204 even on already-deleted).
- **No silent fallback to old endpoints**: if a future API change breaks the SDK, raise loudly with a clear error.
- **Predictable versioning**: SemVer 2.0.0; CHANGELOG-driven; human review of public-surface diffs at release time (no `cargo public-api` equivalent in Ruby).
- **Named constants in `Internal::Constants`**: every API path, every default (`DEFAULT_BASE_URL`, `DEFAULT_MAX_RETRIES`, `DEFAULT_RETRY_DELAY`, `DEFAULT_TIMEOUT`, `RETRY_AFTER_CAP`), every header name. Specs import from there — never re-type string literals.
- **YARD `@example` on every public method**: enforced by `yard --fail-on-warning`. Examples can't bit-rot for syntax.
- **MIT license** (Ruby ecosystem convention): matches Node/Python/Go/PHP siblings.
- **Supply-chain protections** (§16.6): `Gemfile.lock` committed + `--frozen` in CI + `bundle audit` + Dependabot + SHA-pinned actions + per-gem scoped push key + RubyGems MFA enforced via gemspec metadata. Equivalent to Node `--provenance`, Python wheels-only + lockfile + pip-audit, Go `go.sum` + `govulncheck`, PHP `composer audit`, and Rust `cargo audit + deny`. Trusted Publishing isn't shipped on RubyGems yet; revisit when it lands.

---

## 18. Divergences from the Python / Go / PHP / Node / Rust SDK plans (intentional)

These are places where the Ruby SDK diverges from siblings because Ruby has a stronger or different primitive (or a different ecosystem norm). All other behavior matches exactly. New divergences require explicit discussion — do not add them silently.

| Concern | Other SDKs | Ruby | Why |
|---|---|---|---|
| Concurrency | sync+async (Python) / sync+goroutines (Go) / sync (PHP) / async (Node) / async-first + blocking (Rust) | **Sync-only at v1.0** | Ruby has no mainstream async story; threading is the concurrency primitive. Async via the `async` gem is post-v1.0 future work. |
| HTTP client | built-in `fetch` (Node) / `httpx` (Python) / `net/http` (Go) / PSR-18 (PHP) / `reqwest` hard dep (Rust) | **Stdlib `Net::HTTP`, zero runtime deps** | Matches anthropic-sdk-ruby and modern stripe-ruby. Avoids Faraday-version-hell footgun. |
| Sum types / mode enforcement | TS discriminated unions / Python `Union[]` / Go sealed interface / PHP sealed abstract class / Rust native `enum` | **Required kwargs + RBS sigs + runtime validation** | Ruby has no compile time. `def pdf(project:, ...)` raises `ArgumentError` immediately. |
| Errors | single class (Node/Go) / hierarchy (Python/PHP) / single enum (Rust) | **Class hierarchy** (PoliPage::Error subclasses) | Matches stripe-ruby / openai-ruby / anthropic-sdk-ruby. `rescue ClassName` is the idiomatic dispatch. |
| Nullable wire fields | `string \| null` / `Optional[str]` / `*string` / `?string` / `Option<T>` | **bare nil** | Ruby's nil is the language primitive. |
| Wire translation | hand-written (Python/PHP) / `json:` tags (Go) / native (Node) / `#[serde(rename_all)]` (Rust) | **Hand-written `Internal::Wire.to_wire`/`from_wire`** | No `serde`-equivalent in Ruby stdlib. ~30 LOC translator. |
| Cancellation | `AbortSignal` (Node) / `asyncio.CancelledError` (Python) / `context.Context` (Go) / `timeout:` only (PHP) / future-drop (Rust) | **`Timeout.timeout` + `Thread#raise`** | Ruby's only cancellation primitives. Documented as caller-side patterns. |
| Streaming | `ReadableStream` / generator / `io.ReadCloser` / PSR-7 / `impl Stream` | **Block-yielding + Enumerator fallback** | Ruby's `Net::HTTP#read_body { |chunk| ... }` + `Enumerator.new` composition. |
| Constructor | options object / dict / functional options / named args / builder pattern (Rust) | **Constructor kwargs** | Ruby kwargs are the language primitive. |
| Observability | logging (Python) / log/slog (Go) / PSR-3 (PHP) / hooks (Node) / `tracing` (Rust) | **Stdlib `Logger` + hook procs** | Matches stripe-ruby `Stripe.logger`. |
| Compile-time type checks | TS compiler / pyright / Go compiler / PHPStan / rustc + clippy + trybuild | **RBS + Steep + runtime validation** | Ruby's official type-sig story; Steep is the RBS-native checker. Sorbet is optional for users. |
| Doc generation | typedoc / pdoc / pkg.go.dev / phpDocumentor / rustdoc | **YARD + rubydoc.info + GitHub Pages** | YARD is the Ruby standard; rubydoc.info auto-builds on publish. |
| Lockfile | committed (Node) / committed (Python lock) / committed (`go.sum`) / NOT committed (PHP) / committed (Rust) | **`Gemfile.lock` committed** | Modern Bundler recommendation; reproducible CI; consumers resolve their own. |
| Install-smoke | npm pack + tarball install / wheel install / consumer module / `composer require` from path / `cargo new` consumer | **`gem install ./poli-page-*.gem` + `ruby -r poli_page -e ...`** | Mirrors the consumer experience. |
| License | MIT (Node/Python/Go/PHP) / dual MIT-Apache (Rust) | **MIT** | Ruby ecosystem convention matches Node/Python/Go/PHP. No dual-license norm in Ruby. |
| Vuln scanning | `npm audit` / `pip-audit` / `govulncheck` / `composer audit` / `cargo audit` | **`bundle audit`** | RubyGems advisory DB. |
| Static security | CodeQL (Node/Python/Go/Ruby) / none (PHP/Rust) | **CodeQL Ruby + RuboCop security plugins** | Both available. |
| Publishing | npm publish (Node) / Trusted Publishing (Python) / git tag → proxy.golang.org (Go) / git tag → Packagist webhook (PHP) / `cargo publish` from machine (Rust) | **`gem push` from maintainer's machine + manual git tag** | No Trusted Publishing on RubyGems yet; per-gem scoped key is the credential boundary. MFA required via gemspec metadata. |
| Release workflow | `workflow_dispatch` Trusted Publishing (Python) / none (Go/PHP/Rust) | **None — only `scripts/release.sh`** | No CI-side artifact to build; `gem push` is local-only. Matches Go/PHP/Rust posture. |
| Hosting | docs.poli.page reverse proxy (all) | **rubydoc.info direct + GitHub Pages redirect** | rubydoc.info IS the canonical Ruby docs host; GH Pages provides the docs.poli.page CNAME target. |
| Value objects | TS interface / Python dataclass / Go struct / PHP readonly class / Rust struct | **`Data.define`** | Ruby 3.2+ native; immutable, frozen, pattern-match-friendly. |

---

## 19. Open items

All design decisions are locked. What remains is operational tasks and phase-time verifications.

### Pre-flight check (Phase 0, ~1 minute)

- **RubyGems name availability**: visit `https://rubygems.org/gems/poli-page` (HTTP 404 = available). If taken, fallback to `polipage` (no hyphen — common in Ruby; see `rest-client` vs `restclient`).
- **`PoliPage` module conflict check**: grep `rubygems.org` search for any existing gem exporting a `PoliPage` module identifier; vanishingly rare but worth a quick check.
- **GitHub repo creation**: `poli-page/sdk-ruby` does not exist yet — Xavier creates it; the implementation agent links the local repo to the remote.

### Xavier coordination (before Phase 7)

- **RubyGems API key**: Xavier creates a RubyGems account (or uses an existing one), enables MFA, generates a key **scoped to the `poli-page` gem only** (`/profile/api_keys → New API Key → Scope: push to a specific gem → poli-page`), and shares it via 1Password / similar so it can be stored on the maintainer's `~/.gem/credentials`. **Do not** create a generic-scope key; the per-gem scope is the credential boundary.
- **Docs hosting redirect**: `docs.poli.page/reference/sdk/ruby/` redirects to either `https://rubydoc.info/gems/poli-page/latest` (auto-built) or the GitHub Pages YARD output (CNAME). Pick one.
- **Roadmap update**: when this SDK ships v1.0, add a Ruby row to `sdk-roadmap.md` "10-repo target" table:
  ```
  | `poli-page/sdk-ruby` | Core | RubyGems | `poli-page` |
  ```
  (And update the target count and ordering as appropriate.)
- **Engineering guide §4.1 refresh**: if not done in another phase, refresh the cross-SDK policy to mention Ruby alongside the other ecosystems explicitly.

### Phase-time verifications (Phase 6 RC tag)

- **rubydoc.info build**: visit `https://rubydoc.info/gems/poli-page/<rc-tag>` and confirm the build succeeded. First build takes ~5 minutes after publish; failures are visible at `https://rubydoc.info/gems/poli-page/<rc-tag>/builds`.
- **GitHub Pages YARD deploy**: confirm `docs.yml` ran cleanly on push to `main` and the docs.poli.page CNAME serves the new version's HTML.
- **`gem install poli-page --pre` from a fresh shell**, no checkout — confirms the registry-side ingestion worked.
- **`bundle exec yard --fail-on-warning`** in the consumer crate — confirms no broken cross-references in the doc comments.

### Future enhancements (post-v1.0)

- **Async client via the `async` gem**: separate `PoliPage::AsyncClient` with the same surface area, using `Async::HTTP::Internet`. Non-breaking 1.x minor when user demand materializes.
- **Connection pooling**: `connection_pool` gem (separate dep) wrapping the existing `Transport` — non-breaking 1.x minor.
- **Framework integration gems**: `poli-page-rails` (ActiveJob integration, ActionMailer attachment helpers, Rails generator), `poli-page-sidekiq` (background-job-aware) — separate gems, separate plans, post-1.0.
- **Sorbet `T::Struct` support**: ship `.rbi` files alongside `.rbs` for Sorbet users who prefer Sorbet's stricter checker. Non-breaking 1.x minor.
- **SBOM generation**: `cyclonedx-ruby --output sbom.json` in CI; attach to GitHub releases. Worth adding when RubyGems Trusted Publishing ships.

---

## 20. What to do FIRST in the new session

When you start work in the new repo, do these in order:

1. **Read `/Users/mickael/Projects/sdk-node/sdk-specification.md`** end to end.
2. **Skim `/Users/mickael/Projects/sdk-node/src/`** to see the shape of every public method.
3. **Skim `/Users/mickael/Projects/sdk-python-plan.md`, `/Users/mickael/Projects/sdk-go-plan.md`, `/Users/mickael/Projects/sdk-php-plan.md`, and `/Users/mickael/Projects/sdk-rust-plan.md`** to see how sibling translations made architectural decisions — most apply directly with Ruby substitutions. The PHP plan is the closest structural analog (sync, dynamic, class-hierarchy errors).
4. **Skim `/Users/mickael/Projects/sdk-node/tests/integration/`** to see what the deployed API actually returns.
5. **Verify the `poli-page` name on RubyGems** — `https://rubygems.org/gems/poli-page`. If taken, choose a fallback (`polipage`).
6. **Confirm `github.com/poli-page/sdk-ruby` is the chosen repo path** with Xavier (and that the repo is created).
7. **Phase 0 of §13** — get an empty gem with green CI.
8. Then iterate phase by phase. Each phase ends in a commit; do not bundle phases.

Use the superpowers TDD skill (`superpowers:test-driven-development`) starting in phase 1. Write the failing spec, then the implementation, then refactor. The Node SDK's tests are the spec for behavior — port them first.

---

## 21. Handoff prompt for the new conversation

Paste this into the new Claude Code session in the cloned `sdk-ruby` repo:

> We're building `poli-page`, the official Poli Page SDK for Ruby. It's a translation of the already-shipped Node SDK (`@poli-page/sdk` v1.0) at `/Users/mickael/Projects/sdk-node/`. The contract is fixed by `/Users/mickael/Projects/sdk-node/sdk-specification.md` v1.3 — read that first.
>
> The full plan is at `/Users/mickael/Projects/sdk-ruby/sdk-ruby-plan.md`. Read it end to end before you do anything. It defines: architecture (sync-only via stdlib `Net::HTTP` with zero runtime deps, pure transport core in `PoliPage::Internal::HTTP`, required-kwarg + RBS for project-mode enforcement, class-hierarchy errors rooted at `PoliPage::Error`, stdlib `Logger` for observability, hand-rolled snake_case ↔ camelCase wire translator), naming (RubyGems `poli-page`, require `poli_page`, client `PoliPage::Client`, snake_case methods, `Error` hierarchy + predicates), build (Ruby 3.2 MSRV, single gem, MIT license, `Gemfile.lock` committed, gemspec MFA-required metadata), CI (ruby 3.2/3.3/3.4 on ubuntu + single mac+win on 3.4, RuboCop, Steep, RSpec, bundler-audit, CodeQL), publishing (manual `scripts/release.sh` → `gem push` + `git push origin <tag>`; no auto-publish workflow; rubydoc.info auto-builds), and a 7-phase build order.
>
> The Python, Go, PHP, and Rust sibling plans at `/Users/mickael/Projects/sdk-python-plan.md`, `/Users/mickael/Projects/sdk-go-plan.md`, `/Users/mickael/Projects/sdk-php-plan.md`, and `/Users/mickael/Projects/sdk-rust-plan.md` share all architectural decisions — when in doubt, mirror them with Ruby substitutions. The PHP plan is the closest structural analog. When the spec is silent, the Node SDK behavior wins. When the spec and deployed API disagree, the deployed API wins — and the empirical source of truth is the CLI's api-client at `/Users/mickael/n/lib/node_modules/@poli-page/cli/dist/api-client.js`.
>
> Start with Phase 0 of the plan: repo init, `poli-page.gemspec`, `.rubocop.yml`, `Rakefile`, `Gemfile.lock`, green CI on ruby 3.2/3.3/3.4. Use TDD from Phase 1 onward. Port the Node SDK's tests one-by-one before porting the implementation.
>
> Do NOT diverge from the Node SDK's behavior without checking with me first. Behavior parity is the explicit v1.0.0 goal. The intentional Ruby-vs-other-SDKs divergences are catalogued in §18 of the plan; do not add new ones silently.
>
> The local `sdk-ruby` repo has been git-initialized but is NOT yet linked to a GitHub remote — Mickael will link it once `poli-page/sdk-ruby` is created on GitHub.

---

## 22. Pointers (cheat sheet)

| Need | Location |
|---|---|
| Multi-language contract | `/Users/mickael/Projects/sdk-node/sdk-specification.md` |
| Cross-SDK engineering guide (authoritative) | `/Users/mickael/Projects/sdk-ruby/sdk-engineering-guide.md` |
| Multi-repo roadmap | `/Users/mickael/Projects/sdk-ruby/sdk-roadmap.md` |
| Node SDK source | `/Users/mickael/Projects/sdk-node/src/` |
| Node SDK tests | `/Users/mickael/Projects/sdk-node/tests/` |
| Python sibling plan | `/Users/mickael/Projects/sdk-python-plan.md` (or `/Users/mickael/Projects/sdk-python/sdk-python-plan.md`) |
| Go sibling plan | `/Users/mickael/Projects/sdk-go-plan.md` (or `/Users/mickael/Projects/sdk-go/sdk-go-plan.md`) |
| PHP sibling plan | `/Users/mickael/Projects/sdk-php-plan.md` (or `/Users/mickael/Projects/sdk-php.md/sdk-php.md`) |
| Rust sibling plan | `/Users/mickael/Projects/sdk-rust-plan.md` |
| CLI api-client (empirical truth) | `/Users/mickael/n/lib/node_modules/@poli-page/cli/dist/api-client.js` |
| Node SDK demo | `/Users/mickael/Projects/sdk-node/demo/` |
| Deployed API base (dev) | `https://api-develop.poli.page` |
| Deployed API base (prod) | `https://api.poli.page` |
| Test API key | sdk-node `.env` (POLI_PAGE_API_KEY=pp_test_...) |
| This plan | `/Users/mickael/Projects/sdk-ruby/sdk-ruby-plan.md` |
| rubydoc.info page (post-release) | `https://rubydoc.info/gems/poli-page` |
| RubyGems page (post-release) | `https://rubygems.org/gems/poli-page` |
| GitHub repo (TBD) | `https://github.com/poli-page/sdk-ruby` |
