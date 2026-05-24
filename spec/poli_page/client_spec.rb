# frozen_string_literal: true

RSpec.describe PoliPage::Client do
  let(:api_key) { "pp_test_abc" }

  describe ".new (constructor validation)" do
    it "requires an api_key" do
      expect { described_class.new(api_key: nil) }.to raise_error(PoliPage::InvalidOptionsError, /api_key/)
      expect { described_class.new(api_key: "") }.to raise_error(PoliPage::InvalidOptionsError, /api_key/)
    end

    it "applies defaults from Internal::Constants" do
      client = described_class.new(api_key: api_key)
      expect(client.base_url).to eq("https://api.poli.page")
      expect(client.max_retries).to eq(2)
      expect(client.retry_delay).to eq(0.5)
      expect(client.timeout).to eq(60)
    end

    it "accepts overrides for base_url / max_retries / retry_delay / timeout" do
      client = described_class.new(
        api_key: api_key,
        base_url: "https://api-develop.poli.page",
        max_retries: 5,
        retry_delay: 0.25,
        timeout: 30
      )
      expect(client.base_url).to eq("https://api-develop.poli.page")
      expect(client.max_retries).to eq(5)
      expect(client.retry_delay).to eq(0.25)
      expect(client.timeout).to eq(30)
    end

    it "exposes a `render` resource namespace" do
      client = described_class.new(api_key: api_key)
      expect(client.render).to be_a(PoliPage::Resources::Render)
    end
  end

  describe "request execution" do
    subject(:client) { described_class.new(api_key: api_key, max_retries: 0) }

    it "sends Authorization, Content-Type, Accept, User-Agent, Idempotency-Key on POST" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with(
               headers: {
                 "Authorization" => "Bearer #{api_key}",
                 "Content-Type"  => "application/json",
                 "Accept"        => "application/json",
                 "User-Agent"    => "poli-page-sdk-ruby/#{PoliPage::VERSION}"
               }
             ) { |req| req.headers.key?("Idempotency-Key") }
             .to_return(status: 200, body: '{"html":"<p>x</p>","totalPages":1,"environment":"sandbox"}')

      client.render.preview(template: "<p>x</p>", data: {})
      expect(stub).to have_been_requested
    end

    it "uses a caller-supplied idempotency_key when provided" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with(headers: { "Idempotency-Key" => "caller-key-123" })
             .to_return(status: 200, body: '{"html":"x","totalPages":1,"environment":"sandbox"}')
      client.render.preview(template: "<p>x</p>", data: {}, idempotency_key: "caller-key-123")
      expect(stub).to have_been_requested
    end
  end

  describe "retry loop (sdk-ruby-plan.md §6)" do
    let(:body) { '{"html":"x","totalPages":1,"environment":"sandbox"}' }

    before { allow(client).to receive(:sleep) } # don't actually sleep in tests

    context "with max_retries: 2 (default)" do
      subject(:client) { described_class.new(api_key: api_key) }

      it "retries on 500 up to max_retries + 1 attempts then raises APIError" do
        stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
               .to_return(status: 500, body: '{"code":"INTERNAL_ERROR","message":"boom"}')
        expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::APIError)
        expect(stub).to have_been_requested.times(3)
      end

      it "retries on 429 and honours Retry-After" do
        stub_request(:post, "https://api.poli.page/v1/render/preview")
          .to_return({ status: 429, body: "{}", headers: { "Retry-After" => "1" } },
                     { status: 200, body: body })
        client.render.preview(template: "x", data: {})
        expect(client).to have_received(:sleep).with(1) # used Retry-After as-is
      end

      it "retries on PoliPage::ConnectionError" do
        stub_request(:post, "https://api.poli.page/v1/render/preview")
          .to_raise(SocketError.new("dns")).then
          .to_return(status: 200, body: body)
        expect { client.render.preview(template: "x", data: {}) }.not_to raise_error
      end

      it "does NOT retry on 400 (ValidationError)" do
        stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
               .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')
        expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::ValidationError)
        expect(stub).to have_been_requested.times(1)
      end

      it "does NOT retry on 401" do
        stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
               .to_return(status: 401, body: '{"code":"INVALID_API_KEY","message":"bad key"}')
        expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::AuthenticationError)
        expect(stub).to have_been_requested.times(1)
      end
    end

    context "with max_retries: 0 (retries disabled)" do
      subject(:client) { described_class.new(api_key: api_key, max_retries: 0) }

      it "makes exactly one attempt on 500" do
        stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
               .to_return(status: 500, body: "{}")
        expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::APIError)
        expect(stub).to have_been_requested.times(1)
      end
    end
  end

  describe "hooks (sdk-ruby-plan.md §10.2)" do
    let(:body) { '{"html":"x","totalPages":1,"environment":"sandbox"}' }

    it "fires on_retry before each retry sleep, carrying a RetryEvent" do
      events = []
      client = described_class.new(api_key: api_key, on_retry: ->(e) { events << e })
      allow(client).to receive(:sleep)
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return({ status: 500, body: "{}" }, { status: 200, body: body })
      client.render.preview(template: "x", data: {})
      expect(events.size).to eq(1)
      expect(events.first).to be_a(PoliPage::RetryEvent)
      expect(events.first.attempt).to eq(2)
      expect(events.first.reason).to be_a(PoliPage::APIError)
    end

    it "fires on_error once at terminal failure" do
      errors = []
      client = described_class.new(api_key: api_key, max_retries: 0, on_error: ->(e) { errors << e })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')
      expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::ValidationError)
      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(PoliPage::ValidationError)
    end

    it "swallows exceptions raised inside hooks (Node #fireHook parity)" do
      client = described_class.new(
        api_key: api_key, max_retries: 0,
        on_error: ->(_e) { raise "hook exploded" }
      )
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')
      expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::ValidationError)
    end
  end

  describe "thread safety smoke" do
    it "supports concurrent calls on a single client" do
      client = described_class.new(api_key: api_key, max_retries: 0)
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: '{"html":"x","totalPages":1,"environment":"sandbox"}')
      threads = Array.new(8) { Thread.new { client.render.preview(template: "x", data: {}) } }
      results = threads.map(&:value)
      expect(results).to all(be_a(PoliPage::PreviewResult))
    end
  end
end
