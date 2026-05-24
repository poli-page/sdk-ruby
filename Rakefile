# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

# Default task runs lint + unit specs. `steep` will be added in Phase 1 once
# `sig/*.rbs` files start landing (per sdk-ruby-plan.md §13 Phase 1 and §16.1).
task default: %i[rubocop spec]
