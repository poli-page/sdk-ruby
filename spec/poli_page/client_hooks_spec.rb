# frozen_string_literal: true

RSpec.describe PoliPage::Client do
  let(:api_key) { "pp_test_abc" }

  describe "on_request constructor kwarg" do
    it "accepts on_request: as a callable and exposes it via instance config" do
      hook = ->(_e) {}
      expect { described_class.new(api_key: api_key, on_request: hook) }.not_to raise_error
    end

    it "tolerates nil on_request (default)" do
      expect { described_class.new(api_key: api_key) }.not_to raise_error
    end
  end

  describe "on_response constructor kwarg" do
    it "accepts on_response: as a callable" do
      hook = ->(_e) {}
      expect { described_class.new(api_key: api_key, on_response: hook) }.not_to raise_error
    end
  end

  describe "on_request firing" do
    let(:body) { '{"html":"x","totalPages":1,"environment":"sandbox"}' }

    it "fires on_request before each HTTP attempt with 1-based counter" do
      events = []
      client = described_class.new(api_key: api_key, on_request: ->(e) { events << e })
      allow(client).to receive(:sleep)
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return({ status: 500, body: "{}" }, { status: 200, body: body })

      client.render.preview(template: "x", data: {})

      expect(events.size).to eq(2)
      expect(events.map(&:attempt)).to eq([1, 2])
      expect(events.map(&:method)).to all(eq("POST"))
      expect(events.map(&:url)).to all(eq("https://api.poli.page/v1/render/preview"))
      expect(events.first).to be_a(PoliPage::RequestEvent)
    end

    it "fires on_request even when the request will fail terminally" do
      events = []
      client = described_class.new(api_key: api_key, max_retries: 0,
                                   on_request: ->(e) { events << e })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')

      expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::ValidationError)
      expect(events.size).to eq(1)
      expect(events.first.attempt).to eq(1)
    end

    it "swallows exceptions raised inside on_request (safe-fire)" do
      client = described_class.new(api_key: api_key, max_retries: 0,
                                   on_request: ->(_e) { raise "hook exploded" })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: '{"html":"x","totalPages":1,"environment":"sandbox"}')

      expect { client.render.preview(template: "x", data: {}) }.not_to raise_error
    end
  end

  describe "on_response firing" do
    let(:body) { '{"html":"x","totalPages":1,"environment":"sandbox"}' }

    it "fires on_response after a 2xx with status, request_id, duration_ms" do
      events = []
      client = described_class.new(api_key: api_key, on_response: ->(e) { events << e })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: body,
                   headers: { "x-request-id" => "req_abc" })

      client.render.preview(template: "x", data: {})

      expect(events.size).to eq(1)
      expect(events.first).to be_a(PoliPage::ResponseEvent)
      expect(events.first.status).to eq(200)
      expect(events.first.request_id).to eq("req_abc")
      expect(events.first.duration_ms).to be_a(Integer)
      expect(events.first.duration_ms).to be >= 0
    end

    it "does NOT fire on_response on non-2xx (retried 500 then 200)" do
      events = []
      client = described_class.new(api_key: api_key, on_response: ->(e) { events << e })
      allow(client).to receive(:sleep)
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return({ status: 500, body: "{}" }, { status: 200, body: body })

      client.render.preview(template: "x", data: {})

      expect(events.size).to eq(1)
      expect(events.first.status).to eq(200)
    end

    it "does NOT fire on_response on terminal 4xx" do
      events = []
      client = described_class.new(api_key: api_key, max_retries: 0,
                                   on_response: ->(e) { events << e })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')

      expect { client.render.preview(template: "x", data: {}) }.to raise_error(PoliPage::ValidationError)
      expect(events).to be_empty
    end

    it "tolerates a missing x-request-id header (nil)" do
      events = []
      client = described_class.new(api_key: api_key, on_response: ->(e) { events << e })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: body)

      client.render.preview(template: "x", data: {})

      expect(events.first.request_id).to be_nil
    end

    it "swallows exceptions raised inside on_response (safe-fire)" do
      client = described_class.new(api_key: api_key,
                                   on_response: ->(_e) { raise "hook exploded" })
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: body)

      expect { client.render.preview(template: "x", data: {}) }.not_to raise_error
    end
  end
end
