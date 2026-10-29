# frozen_string_literal: true

# Conformance with the Poli Page API contract (https://github.com/poli-page/api-contract).
#
# CI copies the pinned `contract.json` with the `poli-page/api-contract` action
# and sets `POLI_CONTRACT` to its path. Every `kind: "sdk"` case runs against a
# local HTTP server (spec/support/mock_http_server.rb, real sockets, WebMock
# off) that answers the case's `responses` in order and records each request;
# the example then compares the recorded requests, the `on_request` /
# `on_retry` events and the normalized result with the case's `expect`.
# Timing is checked as lower bounds, measured on the server.
#
# `spec/contract-skip.json` maps the case ids allowed to fail to the reason. A
# listed case that passes, or a listed id that is not a case this suite runs,
# fails the run.
#
# Locally: `POLI_CONTRACT=/path/to/contract.json bundle exec rspec`. Without it
# the suite is pending, except in CI, where a missing contract is an error.

require_relative "../support/contract_harness"

RSpec.describe PoliPage::Client do
  describe "API contract" do
    around { |example| PoliPageSpec::RealNetwork.around(example) }

    if PoliPageContract.suite.nil?
      it "needs POLI_CONTRACT in CI, and is pending without it locally" do
        skip "API contract: set POLI_CONTRACT to a contract.json path to run it" if ENV.fetch("CI", "").empty?

        message = 'POLI_CONTRACT is not set: in CI the "API contract" step must provide contract.json ' \
                  "(poli-page/api-contract action, output `path`)"
        expect(ENV.fetch("POLI_CONTRACT", "")).not_to be_empty, message
      end
    else
      it_behaves_like "the API contract file"
      it_behaves_like "the API contract cases"
    end
  end
end
