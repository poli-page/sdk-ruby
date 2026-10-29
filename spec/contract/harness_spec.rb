# frozen_string_literal: true

require "tmpdir"

require_relative "../support/contract_harness"

# The contract harness refuses what it cannot run, whatever POLI_CONTRACT is.
RSpec.describe PoliPageContract do
  def write_json(dir, value)
    path = File.join(dir, "contract.json")
    File.write(path, JSON.generate(value))
    path
  end

  describe ".load_contract" do
    it "rejects a formatVersion it does not know" do
      Dir.mktmpdir do |dir|
        expect { described_class.load_contract(write_json(dir, { "formatVersion" => 2 })) }
          .to raise_error(PoliPageContract::ContractError, /formatVersion 2 is not supported/)
      end
    end

    it "rejects a file without formatVersion, or that is not JSON" do
      Dir.mktmpdir do |dir|
        expect { described_class.load_contract(write_json(dir, [])) }
          .to raise_error(PoliPageContract::ContractError, /no formatVersion/)
        File.write(File.join(dir, "bad.json"), "{")
        expect { described_class.load_contract(File.join(dir, "bad.json")) }
          .to raise_error(PoliPageContract::ContractError, /cannot be read as JSON/)
      end
    end
  end

  describe ".load_skip_list" do
    it "needs a reason for every listed case" do
      Dir.mktmpdir do |dir|
        path = write_json(dir, { "network.drop" => " " })
        expect do
          described_class.load_skip_list(path)
        end.to raise_error(PoliPageContract::ContractError, /needs a reason/)
      end
    end

    it "is an object of case id to reason in the repository" do
      expect(described_class.load_skip_list).to be_a(Hash)
    end
  end

  describe ".substitute" do
    it "replaces {{mock}} and {{httpDate+N}}" do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 21, 7, 28, 0))
      expect(described_class.substitute({ "a" => ["{{mock}}/x", "{{httpDate+2}}"] }, "http://127.0.0.1:1"))
        .to eq({ "a" => ["http://127.0.0.1:1/x", "Wed, 21 Oct 2026 07:28:02 GMT"] })
    end

    it "rejects any other placeholder" do
      expect { described_class.substitute("{{nope}}", "http://x") }
        .to raise_error(PoliPageContract::ContractError, /unknown contract placeholder \{\{nope\}\}/)
    end
  end

  describe ".runs?" do
    it "runs a cancellation case only in the SDKs of policy.cancellationSdks" do
      kase = { "requires" => "cancellation" }
      expect(described_class.runs?(kase, { "cancellationSdks" => %w[node go] })).to be false
      expect(described_class.runs?(kase, { "cancellationSdks" => %w[ruby] })).to be true
      expect { described_class.runs?({ "requires" => "x" }, {}) }.to raise_error(PoliPageContract::ContractError)
    end
  end

  describe ".expected_prefix" do
    let(:kase) do
      events = [{ "type" => "request" }, { "type" => "retry" }, { "type" => "request" }, { "type" => "retry" },
                { "type" => "request" }]
      { "expect" => { "events" => events, "requests" => [1, 2, 3], "result" => {} } }
    end

    it "keeps the events and requests up to the Nth retry event, and not the result" do
      events, requests, check_result = described_class.expected_prefix(kase.merge("stopAfterRetryEvents" => 1))
      expect(events.map { |e| e["type"] }).to eq(%w[request retry])
      expect([requests, check_result]).to eq([[1], false])
    end

    it "rejects a stop after more retries than the case has" do
      expect { described_class.expected_prefix(kase.merge("stopAfterRetryEvents" => 3)) }
        .to raise_error(PoliPageContract::ContractError, /fewer retries/)
    end
  end
end
