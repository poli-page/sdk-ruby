# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc "Validate RBS signature syntax under sig/"
task :rbs_validate do
  sh "bundle exec rbs validate"
end

desc "YARD docs (warning-free) to doc/"
task :yard do
  sh "bundle exec yard --fail-on-warning"
end

# Default task runs lint + RBS syntax validation + unit specs.
#
# `bundle exec steep check` is intentionally excluded from the default task
# (and from CI) — see `sig/poli_page/*.rbs`: the published RBS sigs cover
# only the public surface, while `lib/poli_page/internal/` has no sigs by
# design (it's convention-private, semver-exempt). Steep's strict mode
# warns on every internal call. The sigs are still useful for consumer
# IDEs and `rbs validate` catches authoring errors in CI. Devs may still
# run `bundle exec steep check --severity-level error` locally.
task default: %i[rubocop rbs_validate spec]
