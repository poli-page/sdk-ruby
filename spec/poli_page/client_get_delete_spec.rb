# frozen_string_literal: true

# Phase 4 additions to PoliPage::Client: method-aware execution helpers for
# the documents.* namespace.

RSpec.describe PoliPage::Client do
  let(:client) { described_class.new(api_key: "pp_test_abc", max_retries: 0) }

  describe "#execute_get" do
    it "GETs the path with Authorization, returns parsed snake_case Hash" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc_abc")
             .with(headers: { "Authorization" => "Bearer pp_test_abc", "Accept" => "application/json" })
             .to_return(status: 200, body: '{"documentId":"doc_abc","pageCount":2}')

      result = client.execute_get("/v1/documents/doc_abc")
      expect(result).to eq(document_id: "doc_abc", page_count: 2)
      expect(stub).to have_been_requested
    end

    it "does NOT send Content-Type or Idempotency-Key on GET" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc_abc").with do |req|
        !req.headers.key?("Content-Type") && !req.headers.key?("Idempotency-Key")
      end.to_return(status: 200, body: "{}")
      client.execute_get("/v1/documents/doc_abc")
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:get, "https://api.poli.page/v1/documents/missing")
        .to_return(status: 404, body: '{"code":"DOCUMENT_NOT_FOUND","message":"nope"}')
      expect { client.execute_get("/v1/documents/missing") }
        .to raise_error(PoliPage::NotFoundError) { |e| expect(e.code).to eq("DOCUMENT_NOT_FOUND") }
    end
  end

  describe "#execute_delete" do
    it "DELETEs the path with Authorization and returns nil on 2xx" do
      stub_request(:delete, "https://api.poli.page/v1/documents/doc_abc")
        .with(headers: { "Authorization" => "Bearer pp_test_abc" })
        .to_return(status: 204, body: "")
      expect(client.execute_delete("/v1/documents/doc_abc")).to be_nil
    end

    it "raises GoneError on 410 (re-deleting a soft-deleted document)" do
      stub_request(:delete, "https://api.poli.page/v1/documents/doc_abc")
        .to_return(status: 410, body: '{"code":"GONE","message":"already deleted"}')
      expect { client.execute_delete("/v1/documents/doc_abc") }
        .to raise_error(PoliPage::GoneError) { |e| expect(e.code).to eq("GONE") }
    end
  end

  describe "#execute_get_raw" do
    it "returns the raw Transport::Response (body + headers) without JSON parsing" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc/preview")
        .to_return(status: 200, body: "<html>page</html>",
                   headers: { "Content-Type" => "text/html", "X-Document-Page-Count" => "3" })

      response = client.execute_get_raw("/v1/documents/doc_abc/preview")
      expect(response.body).to eq("<html>page</html>")
      expect(response.headers["x-document-page-count"]).to eq("3")
    end

    it "raises the appropriate PoliPage::Error on non-2xx" do
      stub_request(:get, "https://api.poli.page/v1/documents/missing/preview")
        .to_return(status: 404, body: '{"code":"DOCUMENT_NOT_FOUND","message":"nope"}')
      expect { client.execute_get_raw("/v1/documents/missing/preview") }
        .to raise_error(PoliPage::NotFoundError)
    end
  end

  describe "retry behaviour generalised to GET/DELETE" do
    subject(:client) { described_class.new(api_key: "pp_test_abc") }

    before { allow(client).to receive(:sleep) }

    it "retries GET on 500" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc_abc")
             .to_return(status: 500, body: "{}")
      expect { client.execute_get("/v1/documents/doc_abc") }.to raise_error(PoliPage::APIError)
      expect(stub).to have_been_requested.times(3)
    end

    it "does NOT retry GET on 404" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/x")
             .to_return(status: 404, body: '{"code":"NOT_FOUND","message":"nope"}')
      expect { client.execute_get("/v1/documents/x") }.to raise_error(PoliPage::NotFoundError)
      expect(stub).to have_been_requested.times(1)
    end
  end
end
