# frozen_string_literal: true

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
