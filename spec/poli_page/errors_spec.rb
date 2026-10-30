# frozen_string_literal: true

# Ported from sdk-node/tests/error.test.ts. The Node SDK uses a single
# `PoliPageError` class with predicate methods; the Ruby SDK splits the
# error space into a class hierarchy (rescue-friendly) but keeps the
# predicates on the base for spec parity.

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

  describe "#retryable? for the codes the SDK never retries (sdk-specification.md §9.1)" do
    it "is false for QUOTA_EXCEEDED, OVERAGE_CAP_EXCEEDED (429) and STORAGE_ACCESS_DENIED (502)" do
      expect(PoliPage::RateLimitError.new("m", code: "QUOTA_EXCEEDED", status: 429).retryable?).to be false
      expect(PoliPage::RateLimitError.new("m", code: "OVERAGE_CAP_EXCEEDED", status: 429).retryable?).to be false
      expect(PoliPage::APIError.new("m", code: "STORAGE_ACCESS_DENIED", status: 502).retryable?).to be false
      expect(PoliPage::RateLimitError.new("m", code: "RATE_LIMIT_EXCEEDED", status: 429).retryable?).to be true
    end

    it "is false for DOWNLOAD_FAILED whatever the storage status" do
      [503, 500, 429, 403, nil].each do |status|
        expect(PoliPage::DownloadError.new(status: status).retryable?).to be(false), "storage status #{status.inspect}"
      end
      expect(PoliPage::APIError.new("m", code: "PUBLISH_IN_PROGRESS", status: 503).retryable?).to be true
    end
  end

  describe "predicates read status and code, not the class (sdk-specification.md §8.1)" do
    it "classes a DOWNLOAD_FAILED by its storage status" do
      expect(PoliPage::DownloadError.new(status: 403).auth_error?).to be true
      expect(PoliPage::DownloadError.new(status: 429).rate_limit_error?).to be true
      expect(PoliPage::DownloadError.new(status: 400).validation_error?).to be true
      expect(PoliPage::DownloadError.new.network_error?).to be false
    end

    it "classes an API error by its status, whatever the subclass" do
      expect(PoliPage::APIError.new("m", code: "X", status: 401).auth_error?).to be true
      expect(PoliPage::APIError.new("m", code: "X", status: 400).validation_error?).to be true
      expect(PoliPage::InvalidOptionsError.new("m").validation_error?).to be false
    end
  end

  describe "SDK messages (sdk-specification.md §8.3)" do
    it "uses the exact texts of the specification" do
      expect(PoliPage::ConnectionError.new.message).to eq("Network request failed")
      expect(PoliPage::TimeoutError.new(timeout: 0.15).message).to eq("Request timed out after 150ms")
      expect(PoliPage::TimeoutError.new(timeout: 60).message).to eq("Request timed out after 60000ms")
      expect(PoliPage::DownloadError.new(status: 403).message).to eq("Failed to download PDF: HTTP 403")
      expect(PoliPage::DownloadError.new.message).to eq("Failed to download PDF: network error")
    end

    it "keeps the cause it was given, even when raised outside a rescue" do
      original = Net::ReadTimeout.new
      err = PoliPage::TimeoutError.new(timeout: 1, cause: original)
      expect { raise err }.to raise_error(err) { |e| expect(e.cause).to be(original) }
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

  describe "SDK-internal error subclasses" do
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
      expect(err.message).to eq("Request timed out after 30000ms")
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

  describe "#to_payload" do
    it "uses API status for status-bearing errors" do
      err = PoliPage::AuthenticationError.new(
        "Forbidden", code: "authentication_failed", status: 401, request_id: "req_abc"
      )
      expect(err.to_payload).to eq(
        code: "authentication_failed",
        message: "Forbidden",
        status: 401,
        request_id: "req_abc"
      )
    end

    it "uses 503 for ConnectionError" do
      err = PoliPage::ConnectionError.new(message: "dns")
      expect(err.to_payload[:status]).to eq(503)
      expect(err.status).to be_nil
    end

    it "uses 504 for TimeoutError" do
      err = PoliPage::TimeoutError.new(timeout: 30)
      expect(err.to_payload[:status]).to eq(504)
      expect(err.status).to be_nil
    end

    it "request_id is nil when absent" do
      err = PoliPage::ConnectionError.new(message: "dns")
      expect(err.to_payload[:request_id]).to be_nil
    end
  end
end

RSpec.describe PoliPage::ErrorCodes do
  it "exposes the 32 known API codes" do
    expected = %w[
      MISSING_API_KEY INVALID_API_KEY ORGANIZATION_CANCELLED ORGANIZATION_PURGED
      FORBIDDEN VALIDATION_ERROR MISSING_DATA MISSING_TEMPLATE_SLUG
      PROJECT_REQUIRED_FOR_DOCUMENT NOT_FOUND DOCUMENT_NOT_FOUND QUOTA_EXCEEDED
      OVERAGE_CAP_EXCEEDED INTERNAL_ERROR
      PUBLISH_IN_PROGRESS ENVIRONMENT_MISMATCH PROJECT_NOT_IN_ENVIRONMENT
      TEMPLATE_NOT_FOUND DOCUMENT_GONE ENVIRONMENT_PROTECTED ORGANIZATION_PAYMENT_GRACE
      EMPTY_DOCUMENT STORAGE_ACCESS_DENIED ORGANIZATION_MIGRATING PROJECT_NOT_FOUND
      TEMPLATE_ERROR TEMPLATE_UNSAFE THUMBNAILS_NOT_AVAILABLE RATE_LIMIT_EXCEEDED RENDER_BODY_TOO_LARGE
      DOCUMENT_TOO_LARGE RENDER_TIMEOUT
    ]
    expected.each do |name|
      expect(described_class.const_get(name)).to eq(name)
    end
    expect(described_class.constants.map(&:to_s)).to match_array(expected)
  end

  it "no longer exports the version, GONE and PAYMENT_REQUIRED codes" do
    removed = %i[
      VERSION_NOT_FOUND INVALID_VERSION_FORMAT VERSION_REQUIRED INVALID_VERSION_FOR_KEY_ENV
      MISSING_PROJECT_OR_TEMPLATE GONE PAYMENT_REQUIRED
    ]
    removed.each do |name|
      expect(described_class.const_defined?(name)).to be false
    end
  end

  it "does NOT export STORAGE_REQUIRED (retired from the deployed API)" do
    expect(described_class.const_defined?(:STORAGE_REQUIRED)).to be false
  end
end
