# frozen_string_literal: true

# Defines `build`, `install`, and `release` (build + tag-guard + gem push)
# from the gemspec. The `release` task is what `rubygems/release-gem` runs
# in .github/workflows/release.yml; on a tag-triggered run the tag already
# exists, so `release:source_control_push` is skipped and only the RubyGems
# push (via Trusted Publishing OIDC) happens.
require "bundler/gem_tasks"

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc "Validate RBS signature syntax under sig/"
task :rbs_validate do
  sh "bundle exec rbs validate"
end

desc "Run Steep type-check (errors only, allows warnings)"
task :steep do
  sh "bundle exec steep check --severity-level=error"
end

desc "YARD docs (warning-free) to doc/"
task :yard do
  sh "bundle exec yard --fail-on-warning"
end

# Default task runs lint + RBS syntax validation + Steep (errors-only) +
# unit specs. Steep runs with `--severity-level=error`: only severity-error
# diagnostics fail the build, so internal-namespace untyped calls (which
# Steep reports as `warning`) stay non-blocking. Use `bundle exec steep
# check` (no severity flag) locally for the strictest read.
task default: %i[rubocop rbs_validate steep spec]
