# frozen_string_literal: true

# Ported from sdk-node/tests/error.test.ts. The Node SDK uses a single
# `PoliPageError` class with predicate methods; the Ruby SDK splits the
# error space into a class hierarchy (rescue-friendly) but keeps the
# predicates on the base for spec parity (sdk-ruby-plan.md §7.1).

RSpec.describe PoliPage::Error do
  describe "#auth_error?" do
    it "is true for status 401 (AuthenticationError) and 403 (PermissionDeniedError)" do
      expect(PoliPage::AuthenticationError.new("m", code: "INVALID_API_KEY", status: 401).auth_error?).to be true
      expect(PoliPage::PermissionDeniedError.new("m", code: "FORBIDDEN", status: 403).auth_error?).to be true
      expect(PoliPage::NotFoundError.new("m", code: "NOT_FOUND", status: 404).auth_error?).to be false
      expect(PoliPage::ConnectionError.new(message: "down").auth_error?).to be false
    end
  end

  describe "#rate_limit_error?" do
    it "is true for status 429 (RateLimitError)" do
      expect(PoliPage::RateLimitError.new("m", code: "rate_limited", status: 429).rate_limit_error?).to be true
      expect(PoliPage::APIError.new("m", code: "INTERNAL_ERROR", status: 500).rate_limit_error?).to be false
    end
  end

  describe "#validation_error?" do
    it "is true for status 400 (ValidationError)" do
      expect(PoliPage::ValidationError.new("m", code: "VALIDATION_ERROR", status: 400).validation_error?).to be true
      expect(PoliPage::AuthenticationError.new("m", code: "INVALID_API_KEY", status: 401).validation_error?).to be false
    end
  end

  describe "#network_error?" do
    it "is true for ConnectionError and TimeoutError" do
      expect(PoliPage::ConnectionError.new(message: "down").network_error?).to be true
      expect(PoliPage::TimeoutError.new(timeout: 60).network_error?).to be true
      expect(PoliPage::APIError.new("m", code: "INTERNAL_ERROR", status: 500).network_error?).to be false
    end
  end

  describe "#retryable?" do
    it "is true for 5xx, 429, network_error, and timeout" do
      expect(PoliPage::APIError.new("m", code: "INTERNAL_ERROR", status: 500).retryable?).to be true
      expect(PoliPage::APIError.new("m", code: "INTERNAL_ERROR", status: 502).retryable?).to be true
      expect(PoliPage::RateLimitError.new("m", code: "rate_limited", status: 429).retryable?).to be true
      expect(PoliPage::ConnectionError.new(message: "down").retryable?).to be true
      expect(PoliPage::TimeoutError.new(timeout: 60).retryable?).to be true
      expect(PoliPage::ValidationError.new("m", code: "VALIDATION_ERROR", status: 400).retryable?).to be false
    end
  end

  describe "field preservation" do
    it "preserves message, code, status, request_id" do
      err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500, request_id: "req_abc")
      expect(err.message).to eq("boom")
      expect(err.code).to eq("INTERNAL_ERROR")
      expect(err.status).to eq(500)
      expect(err.request_id).to eq("req_abc")
      expect(err).to be_a(StandardError)
      expect(err).to be_a(described_class)
    end
  end

  describe "SDK-internal error subclasses (sdk-ruby-plan.md §7.2)" do
    it "InvalidOptionsError carries code 'invalid_options' and nil status" do
      err = PoliPage::InvalidOptionsError.new("api_key is required")
      expect(err.code).to eq("invalid_options")
      expect(err.status).to be_nil
      expect(err.message).to eq("api_key is required")
    end

    it "ConnectionError carries code 'network_error' and the underlying cause" do
      original = SocketError.new("dns")
      err = PoliPage::ConnectionError.new(message: "dns lookup failed", cause: original)
      expect(err.code).to eq("network_error")
      expect(err.status).to be_nil
      expect(err.cause).to be(original)
    end

    it "TimeoutError carries code 'timeout' and the configured timeout in seconds" do
      err = PoliPage::TimeoutError.new(timeout: 30)
      expect(err.code).to eq("timeout")
      expect(err.status).to be_nil
      expect(err.timeout).to eq(30)
      expect(err.message).to include("30")
    end

    it "DownloadError carries code 'DOWNLOAD_FAILED' and may have an S3 status" do
      err = PoliPage::DownloadError.new(message: "s3 502", status: 502)
      expect(err.code).to eq("DOWNLOAD_FAILED")
      expect(err.status).to eq(502)
    end

    it "InternalError carries code 'INTERNAL_ERROR'" do
      err = PoliPage::InternalError.new("response body was not valid JSON", status: 500)
      expect(err.code).to eq("INTERNAL_ERROR")
      expect(err.status).to eq(500)
    end
  end
end

RSpec.describe PoliPage::ErrorCodes do
  it "exposes all known API codes per sdk-ruby-plan.md §7.4" do
    expected = %w[
      MISSING_API_KEY INVALID_API_KEY PAYMENT_REQUIRED FORBIDDEN
      ORGANIZATION_CANCELLED ORGANIZATION_PURGED NOT_FOUND VERSION_NOT_FOUND
      DOCUMENT_NOT_FOUND GONE VALIDATION_ERROR MISSING_DATA
      MISSING_PROJECT_OR_TEMPLATE MISSING_TEMPLATE_SLUG PROJECT_REQUIRED_FOR_DOCUMENT
      INVALID_VERSION_FORMAT VERSION_REQUIRED INVALID_VERSION_FOR_KEY_ENV
      QUOTA_EXCEEDED OVERAGE_CAP_EXCEEDED INTERNAL_ERROR
    ]
    expected.each do |name|
      expect(described_class.const_get(name)).to eq(name)
    end
  end

  it "does NOT export STORAGE_REQUIRED (retired from the deployed API)" do
    expect(described_class.const_defined?(:STORAGE_REQUIRED)).to be false
  end
end
