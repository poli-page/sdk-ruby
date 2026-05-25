# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch

  # Coverage gate — keep CI honest. Internal seams shift over time; the
  # public surface stays well above these floors. Bump them up when the
  # measured coverage justifies it. Override locally by exporting
  # `SIMPLECOV_NO_FAIL=1` (e.g. when iterating on a single spec file).
  minimum_coverage line: 90, branch: 75 unless ENV["SIMPLECOV_NO_FAIL"] == "1"
end

require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

require "poli_page"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed
end
