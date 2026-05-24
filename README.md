# Poli Page SDK for Ruby

Official Ruby client for [Poli Page](https://poli.page) — render PDFs, previews,
and thumbnails from HTML templates via the Poli Page API.

> **Status: Phase 0 (skeleton).** This gem is being bootstrapped against
> [`sdk-ruby-plan.md`](sdk-ruby-plan.md). The public API is not stable yet and
> `0.0.x` releases are pre-1.0 placeholders. The first feature-complete release
> will be `1.0.0`.

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

## Quick start

```ruby
require "poli_page"

# The Client constructor will be implemented in Phase 2.
# client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))
# pdf = client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: { ... })
# File.binwrite("invoice.pdf", pdf)
```

The full API surface (`render.pdf`, `render.pdf_stream`, `render.preview`,
`render.document`, `documents.get`, `documents.preview`, `documents.thumbnails`,
`documents.delete`, `Client#render_to_file`) lands incrementally across phases
1–5. See [`sdk-ruby-plan.md`](sdk-ruby-plan.md) §13 for the build order.

## Development

```sh
bundle install
bundle exec rake          # rubocop + rspec
bundle exec rspec         # unit specs only
bundle exec rubocop       # lint
```

Integration specs hit `https://api-develop.poli.page` and are gated:

```sh
INTEGRATION=1 POLI_PAGE_API_KEY=pp_test_... bundle exec rspec spec/integration
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) (lands in Phase 6).

## License

[MIT](LICENSE)
