# frozen_string_literal: true

require "digest"
require "json"
require "time"

require_relative "mock_http_server"

# Runs the cases of the Poli Page API contract (https://github.com/poli-page/api-contract)
# against PoliPage::Client. See spec/contract/contract_spec.rb.
module PoliPageContract
  # The contract file, or the skip list, is not something this harness can run.
  class ContractError < StandardError; end

  KNOWN_FORMAT_VERSION = 1

  # This SDK's name in `policy.cancellationSdks`.
  SDK_NAME = "ruby"

  # The client's key when a case sets no `apiKey`.
  TEST_API_KEY = "pp_sandbox_00000000000000000000000000000000"

  SKIP_LIST_PATH = File.expand_path("../contract-skip.json", __dir__)

  # The normalizations this harness applies; each must be in `policy.normalizations`.
  NORMALIZATIONS_USED = %w[
    N-STATUS-NULL N-REQID-NULL N-BYTES N-DELETE-NULL N-THUMBS-ARRAY N-PREVIEW N-DESCRIPTOR N-DURATION-MS
  ].freeze

  # The loaded contract and the skip list, as the spec reads them.
  class Suite
    attr_reader :contract, :policy, :skip_list

    def initialize(path)
      @contract = PoliPageContract.load_contract(path)
      @policy = @contract.fetch("policy")
      @skip_list = PoliPageContract.load_skip_list
    end

    def all_cases
      @contract.fetch("cases")
    end

    def sdk_cases
      all_cases.select { |kase| kase["kind"] == "sdk" }
    end

    def running_ids
      sdk_cases.select { |kase| PoliPageContract.runs?(kase, @policy) }.map { |kase| kase["id"] }
    end
  end

  # The suite at `POLI_CONTRACT`, or nil when it is unset.
  def self.suite
    path = ENV.fetch("POLI_CONTRACT", "")
    return nil if path.empty?

    @suite ||= Suite.new(path)
  end

  module_function

  def load_contract(path)
    contract = begin
      JSON.parse(File.read(path))
    rescue SystemCallError, JSON::ParserError => e
      raise ContractError, "POLI_CONTRACT=#{path} cannot be read as JSON: #{e.message}"
    end
    unless contract.is_a?(Hash) && contract.key?("formatVersion")
      raise ContractError, "#{path} is not a contract.json: it has no formatVersion"
    end
    return contract if contract["formatVersion"] == KNOWN_FORMAT_VERSION

    raise ContractError, "contract.json formatVersion #{contract["formatVersion"].inspect} is not supported " \
                         "(this harness reads format #{KNOWN_FORMAT_VERSION}): update spec/support/contract_harness.rb"
  end

  def load_skip_list(path = SKIP_LIST_PATH)
    parsed = JSON.parse(File.read(path))
    raise ContractError, "spec/contract-skip.json must be an object of case id to reason" unless parsed.is_a?(Hash)

    parsed.each do |id, reason|
      next if reason.is_a?(String) && !reason.strip.empty?

      raise ContractError, "spec/contract-skip.json: #{id.inspect} needs a reason"
    end
    parsed
  end

  # Whether `kase` runs in this SDK: a `requires: "cancellation"` case only
  # in the SDKs of `policy.cancellationSdks`.
  def runs?(kase, policy)
    case kase["requires"]
    when nil then true
    when "cancellation" then policy.fetch("cancellationSdks").include?(SDK_NAME)
    else raise ContractError, "unknown case requirement #{kase["requires"].inspect}"
    end
  end

  # --- Placeholders: {{mock}}, {{httpDate+N}} --------------------------------

  PLACEHOLDER = /\{\{([^}]*)\}\}/
  HTTP_DATE = /\AhttpDate\+(\d+)\z/

  def substitute(value, origin)
    case value
    when String then value.gsub(PLACEHOLDER) { placeholder(Regexp.last_match(1), origin) }
    when Array then value.map { |item| substitute(item, origin) }
    when Hash then value.transform_values { |item| substitute(item, origin) }
    else value
    end
  end

  def placeholder(name, origin)
    return origin if name == "mock"

    date = HTTP_DATE.match(name)
    raise ContractError, "unknown contract placeholder {{#{name}}}" unless date

    # An HTTP-date has whole seconds: round to the nearest one.
    Time.at((Time.now.to_f + date[1].to_i).round).httpdate
  end
end

require_relative "contract_case"
require_relative "contract_examples"
