# frozen_string_literal: true

# Ported 1:1 from sdk-node/tests/internal/http.test.ts (sdk-ruby-plan.md §13
# Phase 1). Note: the Ruby SDK works in seconds (matching `Kernel#sleep` and
# `Net::HTTP#*_timeout`), whereas the Node SDK uses milliseconds — values
# adapted accordingly. The cap is 30 s (vs Node's 30_000 ms). Behavior parity
# is preserved.

RSpec.describe PoliPage::Internal::HTTP do
  describe ".parse_retry_after" do
    it "returns nil for nil" do
      expect(described_class.parse_retry_after(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.parse_retry_after("")).to be_nil
    end

    it "returns 0 for '0'" do
      expect(described_class.parse_retry_after("0")).to eq(0)
    end

    it "returns 5 (seconds) for '5'" do
      expect(described_class.parse_retry_after("5")).to eq(5)
    end

    it "caps at 30 seconds for very large second values" do
      expect(described_class.parse_retry_after("999")).to eq(30)
      expect(described_class.parse_retry_after("100000")).to eq(30)
    end

    it "returns nil for non-numeric, non-date strings" do
      expect(described_class.parse_retry_after("abc")).to be_nil
      expect(described_class.parse_retry_after("not a date")).to be_nil
    end

    it "returns 0 for past HTTP-date" do
      past = (Time.now - 60).httpdate
      expect(described_class.parse_retry_after(past)).to eq(0)
    end

    it "returns ~delta seconds for a future HTTP-date" do
      future = (Time.now + 5).httpdate
      result = described_class.parse_retry_after(future)
      expect(result).to be > 3
      expect(result).to be <= 5
    end

    it "caps a very-far-future HTTP-date at 30 seconds" do
      far_future = (Time.now + (60 * 60)).httpdate
      expect(described_class.parse_retry_after(far_future)).to eq(30)
    end
  end

  describe ".compute_backoff" do
    before do
      # Pin Kernel#rand to 0 → jitter factor = 0.5
      allow(described_class).to receive(:rand).and_return(0)
    end

    it "returns retry_after as-is when given (no jitter applied)" do
      expect(described_class.compute_backoff(attempt: 1, base_delay: 0.5, retry_after: 1.0)).to eq(1.0)
      expect(described_class.compute_backoff(attempt: 3, base_delay: 0.5, retry_after: 0.25)).to eq(0.25)
    end

    it "returns 0 when retry_after is 0 (treats 0 as defined)" do
      expect(described_class.compute_backoff(attempt: 1, base_delay: 0.5, retry_after: 0)).to eq(0)
    end

    it "applies exponential backoff when retry_after is nil" do
      # jitter factor = 0.5 (rand mocked to 0)
      expect(described_class.compute_backoff(attempt: 1, base_delay: 0.5, retry_after: nil)).to eq(0.25)
      expect(described_class.compute_backoff(attempt: 2, base_delay: 0.5, retry_after: nil)).to eq(0.5)
      expect(described_class.compute_backoff(attempt: 3, base_delay: 0.5, retry_after: nil)).to eq(1.0)
    end

    it "applies maximum jitter when rand returns ≈0.999" do
      allow(described_class).to receive(:rand).and_return(0.999) # jitter ≈ 1.499
      expect(described_class.compute_backoff(attempt: 1, base_delay: 0.5, retry_after: nil)).to be_within(0.01).of(0.75)
    end

    it "jitter factor stays within [0.5, 1.5) across many samples" do
      allow(described_class).to receive(:rand).and_call_original
      samples = Array.new(200) { described_class.compute_backoff(attempt: 1, base_delay: 1.0, retry_after: nil) }
      expect(samples).to all(be_between(0.5, 1.5))
    end

    it "calls rand exactly once when retry_after is nil" do
      allow(described_class).to receive(:rand).and_return(0.25)
      described_class.compute_backoff(attempt: 2, base_delay: 0.5, retry_after: nil)
      expect(described_class).to have_received(:rand).once
    end

    it "does not call rand when retry_after is defined" do
      allow(described_class).to receive(:rand)
      described_class.compute_backoff(attempt: 2, base_delay: 0.5, retry_after: 1.0)
      expect(described_class).not_to have_received(:rand)
    end
  end

  describe ".parse_error_body" do
    it "extracts code and message from a complete JSON body" do
      result = described_class.parse_error_body(
        '{"code":"VALIDATION_ERROR","message":"data is required"}',
        400
      )
      expect(result).to eq(["VALIDATION_ERROR", "data is required"])
    end

    it "falls back to message as code when code is absent" do
      result = described_class.parse_error_body('{"message":"something broke"}', 400)
      expect(result).to eq(["something broke", "something broke"])
    end

    it "falls back to error field as code when code and message absent" do
      result = described_class.parse_error_body('{"error":"oops"}', 400)
      expect(result).to eq(["oops", "API error (400): oops"])
    end

    it "returns unknown_error code when JSON has no recognised fields" do
      result = described_class.parse_error_body("{}", 400)
      expect(result).to eq(["unknown_error", "API error (400): unknown_error"])
    end

    it "returns INTERNAL_ERROR when body is not valid JSON" do
      result = described_class.parse_error_body("not json", 502)
      expect(result).to eq(["INTERNAL_ERROR", "API error 502: response body was not valid JSON"])
    end

    it "returns INTERNAL_ERROR for HTML error pages" do
      code, message = described_class.parse_error_body("<html>upstream gone</html>", 502)
      expect(code).to eq("INTERNAL_ERROR")
      expect(message).to include("502")
    end

    it "returns INTERNAL_ERROR for empty body" do
      code, = described_class.parse_error_body("", 500)
      expect(code).to eq("INTERNAL_ERROR")
    end
  end

  describe ".build_headers" do
    let(:ua) { "poli-page-sdk-ruby/1.0.0" }

    def post_headers(api_key: "pp_test_x", idempotency_key: "idem-1", user_agent: ua)
      described_class.build_headers(method: :post, api_key: api_key,
                                    idempotency_key: idempotency_key, user_agent: user_agent)
    end

    it "always sets Accept: application/json (deployed SDK endpoints all return JSON)" do
      expect(post_headers["Accept"]).to eq("application/json")
    end

    it "always sets Content-Type: application/json on POST" do
      expect(post_headers["Content-Type"]).to eq("application/json")
    end

    it "sets Authorization with Bearer prefix" do
      expect(post_headers(api_key: "pp_test_xyz")["Authorization"]).to eq("Bearer pp_test_xyz")
    end

    it "sets the supplied User-Agent verbatim" do
      expect(post_headers(user_agent: "custom-ua/9.9.9")["User-Agent"]).to eq("custom-ua/9.9.9")
    end

    it "sets the Idempotency-Key header from the argument" do
      expect(post_headers(idempotency_key: "idem-abc-123")["Idempotency-Key"]).to eq("idem-abc-123")
    end

    it "GET requests omit Content-Type and Idempotency-Key but keep auth/UA/Accept" do
      h = described_class.build_headers(method: :get, api_key: "pp_test_x", idempotency_key: nil, user_agent: ua)
      expect(h["Content-Type"]).to be_nil
      expect(h["Idempotency-Key"]).to be_nil
      expect(h["Authorization"]).to eq("Bearer pp_test_x")
      expect(h["User-Agent"]).to eq(ua)
      expect(h["Accept"]).to eq("application/json")
    end

    it "DELETE requests omit Content-Type and Idempotency-Key but keep auth/UA/Accept" do
      h = described_class.build_headers(method: :delete, api_key: "pp_test_x", idempotency_key: nil, user_agent: ua)
      expect(h["Content-Type"]).to be_nil
      expect(h["Idempotency-Key"]).to be_nil
      expect(h["Authorization"]).to eq("Bearer pp_test_x")
    end
  end

  describe ".build_url" do
    it "joins a base URL and a path with a single slash" do
      expect(described_class.build_url("https://api.poli.page", "/v1/render")).to eq("https://api.poli.page/v1/render")
    end

    it "tolerates a trailing slash on the base URL" do
      expect(described_class.build_url("https://api.poli.page/", "/v1/render")).to eq("https://api.poli.page/v1/render")
    end

    it "tolerates a missing leading slash on the path" do
      expect(described_class.build_url("https://api.poli.page", "v1/render")).to eq("https://api.poli.page/v1/render")
    end
  end

  describe ".classify" do
    it "returns ValidationError for 400" do
      err = described_class.classify(status: 400, code: "VALIDATION_ERROR", message: "bad", request_id: "r1")
      expect(err).to be_a(PoliPage::ValidationError)
      expect(err.code).to eq("VALIDATION_ERROR")
      expect(err.status).to eq(400)
      expect(err.request_id).to eq("r1")
      expect(err.message).to eq("bad")
    end

    it "returns AuthenticationError for 401" do
      expect(described_class.classify(status: 401, code: "INVALID_API_KEY", message: "x", request_id: nil))
        .to be_a(PoliPage::AuthenticationError)
    end

    it "returns PermissionDeniedError for 403" do
      expect(described_class.classify(status: 403, code: "FORBIDDEN", message: "x", request_id: nil))
        .to be_a(PoliPage::PermissionDeniedError)
    end

    it "returns NotFoundError for 404" do
      expect(described_class.classify(status: 404, code: "NOT_FOUND", message: "x", request_id: nil))
        .to be_a(PoliPage::NotFoundError)
    end

    it "returns GoneError for 410" do
      expect(described_class.classify(status: 410, code: "GONE", message: "x", request_id: nil))
        .to be_a(PoliPage::GoneError)
    end

    it "returns RateLimitError for 429" do
      expect(described_class.classify(status: 429, code: "QUOTA_EXCEEDED", message: "x", request_id: nil))
        .to be_a(PoliPage::RateLimitError)
    end

    it "returns APIError for unmapped 4xx" do
      expect(described_class.classify(status: 418, code: "TEAPOT", message: "x", request_id: nil))
        .to be_a(PoliPage::APIError)
    end

    it "returns APIError for 5xx" do
      err = described_class.classify(status: 500, code: "INTERNAL_ERROR", message: "x", request_id: nil)
      expect(err).to be_a(PoliPage::APIError)
      expect(err.status).to eq(500)
    end

    it "returns APIError for 402 PAYMENT_REQUIRED" do
      expect(described_class.classify(status: 402, code: "PAYMENT_REQUIRED", message: "x", request_id: nil))
        .to be_a(PoliPage::APIError)
    end
  end
end
