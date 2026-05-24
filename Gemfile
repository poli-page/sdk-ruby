# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "bundler-audit", "~> 0.9.2", require: false
  # Pin transitive dep: parallel 2.1.0+ requires Ruby >= 3.3, but gemspec
  # supports Ruby >= 3.2, so the CI Ruby 3.2 job can't resolve the lockfile
  # without this cap.
  gem "parallel", "< 2.1", require: false
  gem "rake", "~> 13.2", require: false
  gem "rbs", "~> 3.6", require: false
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.69", require: false
  gem "rubocop-rspec", "~> 3.3", require: false
  gem "simplecov", "~> 0.22", require: false
  gem "steep", "~> 1.9", require: false
  gem "vcr", "~> 6.3"
  gem "webmock", "~> 3.24"
  gem "yard", "~> 0.9.37", require: false
end
