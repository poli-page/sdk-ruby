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
    "documentation_uri"     => "https://rubydoc.info/gems/poli-page",
    "bug_tracker_uri"       => "https://github.com/poli-page/sdk-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  s.files = Dir["lib/**/*.rb"] + Dir["sig/**/*.rbs"] +
            %w[LICENSE README.md CHANGELOG.md MIGRATION.md SECURITY.md].select { |f| File.exist?(f) }
  s.require_paths = ["lib"]
end
