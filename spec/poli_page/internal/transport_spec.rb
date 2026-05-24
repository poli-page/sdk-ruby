# frozen_string_literal: true

# Per sdk-ruby-plan.md §3.2 and §8. The transport is the only module that
# opens sockets; tests use WebMock to intercept at the Net::HTTP layer.

RSpec.describe PoliPage::Internal::Transport do
  subject(:transport) { described_class.new(base_url: "https://api.poli.page", timeout: 60) }

  describe "#execute" do
    it "returns a Response with status, headers, and body for 2xx" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .with(headers: { "Authorization" => "Bearer pp_test" })
        .to_return(status: 200, body: '{"ok":true}',
                   headers: { "Content-Type" => "application/json", "x-request-id" => "req_1" })

      response = transport.execute(method: :post, path: "/v1/render",
                                   headers: { "Authorization" => "Bearer pp_test",
                                              "Content-Type" => "application/json" },
                                   body: '{"project":"p"}')

      expect(response.status).to eq(200)
      expect(response.body).to eq('{"ok":true}')
      expect(response.headers["x-request-id"]).to eq("req_1")
    end

    it "returns the response unchanged for non-2xx (caller decides what to do)" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}',
                   headers: { "x-request-id" => "req_err" })

      response = transport.execute(method: :post, path: "/v1/render", headers: {}, body: "{}")
      expect(response.status).to eq(400)
      expect(response.body).to include("VALIDATION_ERROR")
    end

    it "supports GET (no body)" do
      stub_request(:get, "https://api.poli.page/v1/documents/abc")
        .to_return(status: 200, body: '{"id":"abc"}')
      response = transport.execute(method: :get, path: "/v1/documents/abc", headers: {})
      expect(response.status).to eq(200)
      expect(response.body).to eq('{"id":"abc"}')
    end

    it "supports DELETE (no body)" do
      stub_request(:delete, "https://api.poli.page/v1/documents/abc")
        .to_return(status: 204, body: "")
      response = transport.execute(method: :delete, path: "/v1/documents/abc", headers: {})
      expect(response.status).to eq(204)
    end

    it "translates Net::OpenTimeout → PoliPage::TimeoutError" do
      stub_request(:post, "https://api.poli.page/v1/render").to_timeout
      expect { transport.execute(method: :post, path: "/v1/render", headers: {}, body: "{}") }
        .to raise_error(PoliPage::TimeoutError) { |e|
          expect(e.code).to eq("timeout")
          expect(e.timeout).to eq(60)
        }
    end

    it "translates SocketError → PoliPage::ConnectionError" do
      stub_request(:post, "https://api.poli.page/v1/render").to_raise(SocketError.new("dns lookup failed"))
      expect { transport.execute(method: :post, path: "/v1/render", headers: {}, body: "{}") }
        .to raise_error(PoliPage::ConnectionError) { |e|
          expect(e.code).to eq("network_error")
          expect(e.message).to include("dns lookup failed")
          expect(e.cause).to be_a(SocketError)
        }
    end

    it "translates Errno::ECONNREFUSED → PoliPage::ConnectionError" do
      stub_request(:get, "https://api.poli.page/v1/documents/abc").to_raise(Errno::ECONNREFUSED)
      expect { transport.execute(method: :get, path: "/v1/documents/abc", headers: {}) }
        .to raise_error(PoliPage::ConnectionError)
    end

    it "translates OpenSSL::SSL::SSLError → PoliPage::ConnectionError" do
      stub_request(:post, "https://api.poli.page/v1/render").to_raise(OpenSSL::SSL::SSLError.new("bad cert"))
      expect { transport.execute(method: :post, path: "/v1/render", headers: {}, body: "{}") }
        .to raise_error(PoliPage::ConnectionError)
    end

    it "joins base_url and relative path via Internal::HTTP.build_url" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/xyz").to_return(status: 200, body: "{}")
      transport.execute(method: :get, path: "/v1/documents/xyz", headers: {})
      expect(stub).to have_been_requested
    end

    it "downcases header keys on the response (Net::HTTP normalisation)" do
      stub_request(:get, "https://api.poli.page/v1/documents/abc")
        .to_return(status: 200, body: "{}", headers: { "X-Request-Id" => "req_xyz" })
      response = transport.execute(method: :get, path: "/v1/documents/abc", headers: {})
      expect(response.headers["x-request-id"]).to eq("req_xyz")
    end
  end
end
