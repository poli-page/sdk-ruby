# frozen_string_literal: true

require_relative "lib/poli_page/version"

Gem::Specification.new do |s|
  s.name        = "poli-page"
  s.version     = PoliPage::VERSION
  s.summary     = "Poli Page SDK for Ruby — render PDFs from HTML templates via the Poli Page API"
  s.description = "Official Ruby client for Poli Page. Renders PDFs, previews, and thumbnails via api.poli.page."
  s.authors     = ["Poli Page"]
  s.email       = "support@poli.page"
  s.homepage    = "https://poli.page"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.2"

  s.metadata = {
    "homepage_uri"          => "https://poli.page",
    "source_code_uri"       => "https://github.com/poli-page/sdk-ruby",
    "changelog_uri"         => "https://github.com/poli-page/sdk-ruby/blob/main/CHANGELOG.md",
    "documentation_uri"     => "https://poli-page.github.io/sdk-ruby/",
    "bug_tracker_uri"       => "https://github.com/poli-page/sdk-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir["lib/**/*.rb"] + Dir["sig/**/*.rbs"] +
            %w[LICENSE README.md CHANGELOG.md MIGRATION.md SECURITY.md CODE_OF_CONDUCT.md]
            .select { |f| File.exist?(f) }
  s.require_paths = ["lib"]

  # `base64` moved from a default gem to a bundled gem in Ruby 3.4. The SDK
  # surfaces base64-encoded thumbnail bytes (PoliPage::Thumbnail#data) and the
  # documented decode path (`Base64.decode64`) needs the `base64` library,
  # which is no longer auto-available on Ruby 3.4+. Declare it explicitly so
  # consumers don't hit `LoadError -- base64`.
  s.add_dependency "base64", ">= 0.1"
end
