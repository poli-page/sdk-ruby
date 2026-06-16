#!/usr/bin/env ruby
# frozen_string_literal: true

# Reference-page extractor for sdk-ruby.
#
# Reads YARD's in-process registry (`bundle exec yard` is run first to build
# `.yardoc`), walks the public surface of the `PoliPage` module, and emits
# MDX into `docs/src/content/docs/reference/` per the SDK docs convention
# (sdk-docs-convention §4b).
#
# Invocation (from `docs/`): `npm run extract` — which shells out to
# `ruby ../scripts/extract-api/main.rb`. The script must be executed from
# the repo root so YARD finds `lib/**/*.rb` and the `.yardoc` cache lives
# under `scripts/extract-api/.cache/`.

# The npm script (`docs/package.json` → `extract`) invokes us with bare
# `ruby ../scripts/extract-api/main.rb`, so the YARD gem isn't on the load
# path unless we activate the repo-root bundle ourselves. Pin BUNDLE_GEMFILE
# so it works from any working directory (CI runs from `docs/`).
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __dir__)
require "bundler/setup"

require "fileutils"
require "json"

HERE      = File.expand_path(__dir__)
REPO_ROOT = File.expand_path("../..", HERE)
REF_OUT   = File.join(REPO_ROOT, "docs", "src", "content", "docs", "reference")
YARDOC    = File.join(HERE, ".cache", ".yardoc")
EXAMPLES  = File.join(REPO_ROOT, "examples")

require_relative "method_pages"
require_relative "types_page"
require_relative "errors_page"
require_relative "runtime_support_page"
require_relative "client_page"
require_relative "meta_sidecar"

# 1. Build YARD's registry under .cache/.yardoc — keeps the repo's working
#    `.yardoc/` (if any) untouched.
FileUtils.mkdir_p(File.dirname(YARDOC))
yard_cmd = %W[bundle exec yard --db #{YARDOC} --no-output --no-stats lib/**/*.rb]
puts "extractor: running #{yard_cmd.join(' ')}"
Dir.chdir(REPO_ROOT) do
  unless system(*yard_cmd)
    abort "extractor: yard failed to build the registry"
  end
end

# 2. Load YARD's programmatic API and the populated registry.
require "yard"
YARD::Registry.load!(YARDOC)

# 3. Clean and rebuild the reference output tree.
FileUtils.rm_rf(REF_OUT)
FileUtils.mkdir_p(File.join(REF_OUT, "methods"))

# 4. Load the gem version from poli-page.gemspec via lib/poli_page/version.rb.
require_relative File.join(REPO_ROOT, "lib", "poli_page", "version")
gem_version = PoliPage::VERSION

# 5. Emit each page.
File.write(File.join(REF_OUT, "client.mdx"),          ClientPage.build)
MethodPages.build.each do |slug, mdx|
  File.write(File.join(REF_OUT, "methods", "#{slug}.mdx"), mdx)
end
File.write(File.join(REF_OUT, "types.mdx"),           TypesPage.build)
File.write(File.join(REF_OUT, "errors.mdx"),          ErrorsPage.build)
File.write(File.join(REF_OUT, "runtime-support.mdx"), RuntimeSupportPage.build(gem_version))
File.write(
  File.join(REF_OUT, "_meta.json"),
  "#{JSON.pretty_generate(MetaSidecar.build(gem_version))}\n"
)

puts "extractor: wrote #{REF_OUT}"
