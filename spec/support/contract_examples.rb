# frozen_string_literal: true

RSpec.shared_examples "the API contract file" do
  let(:suite) { PoliPageContract.suite }
  let(:policy) { suite.policy }
  let(:constants) { PoliPage::Internal::Constants }

  it "has sdk cases and no case kind other than sdk and impl" do
    expect(suite.sdk_cases).not_to be_empty, 'the contract has no kind "sdk" case'
    expect(suite.all_cases.map { |kase| kase["kind"] }.uniq - %w[sdk impl]).to eq([])
  end

  it "allows every normalization this suite applies" do
    allowed = policy.fetch("normalizations").map { |n| n["id"] }
    expect(PoliPageContract::NORMALIZATIONS_USED - allowed).to eq([])
  end

  it "lists in spec/contract-skip.json only cases this suite runs" do
    unknown = suite.skip_list.keys - suite.running_ids
    expect(unknown).to eq([]), "not cases this suite runs, remove them from contract-skip.json: #{unknown}"
  end

  it "has the SDK messages of the policy" do
    errors = policy.fetch("sdkErrors")
    expect(errors.dig("invalid_options", "message")).to eq(constants::MESSAGE_INVALID_OPTIONS)
    expect(errors.dig("network_error", "message")).to eq(constants::MESSAGE_NETWORK_ERROR)
    expect(errors.dig("timeout", "message")).to eq(constants::MESSAGE_TIMEOUT.sub("%<timeout_ms>d", "{timeoutMs}"))
    expect(errors.dig("DOWNLOAD_FAILED", "message")).to eq(constants::MESSAGE_DOWNLOAD_FAILED.sub("%<status>d",
                                                                                                  "{status}"))
    expect(errors.dig("DOWNLOAD_FAILED", "networkMessage")).to eq(constants::MESSAGE_DOWNLOAD_FAILED_NETWORK)
    expect(errors.dig("PROJECT_REQUIRED_FOR_DOCUMENT", "message")).to eq(constants::MESSAGE_PROJECT_REQUIRED)
  end

  it "has the retry policy of the contract" do
    expect(constants::NON_RETRYABLE_CODES).to match_array(policy.fetch("nonRetryableCodes"))
    expect(constants::RETRY_AFTER_CAP * 1000).to eq(policy.fetch("retryAfterClampMs"))
  end
end

# One example per `kind: "sdk"` case, named by its id.
RSpec.shared_examples "the API contract cases" do
  def check_case(kase)
    run = PoliPageContract::CaseRun.new(kase).run
    events, requests, check_result = PoliPageContract.expected_prefix(kase)
    aggregate_failures do
      expect(run.describe_requests(requests)).to eq(PoliPageContract.substitute(requests, run.origin))
      expect(run.describe_events(events)).to eq(events)
      check_result(run, kase) if check_result
    end
  end

  def check_result(run, kase)
    expect(run.result).to eq(PoliPageContract.substitute(kase.dig("expect", "result"), run.origin))
  end

  # A listed case must still fail; once it passes, the run fails until it
  # leaves the list.
  def check_listed_case(kase, reason)
    begin
      check_case(kase)
    rescue RSpec::Expectations::ExpectationNotMetError
      skip "listed in spec/contract-skip.json: #{reason}"
    end
    raise "#{kase["id"]} passes now: remove it from spec/contract-skip.json"
  end

  PoliPageContract.suite.sdk_cases.each do |kase|
    it kase["id"] do
      suite = PoliPageContract.suite
      unless suite.running_ids.include?(kase["id"])
        skip "policy.cancellationSdks does not list #{PoliPageContract::SDK_NAME}"
      end

      reason = suite.skip_list[kase["id"]]
      reason ? check_listed_case(kase, reason) : check_case(kase)
    end
  end
end
