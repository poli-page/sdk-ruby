# frozen_string_literal: true

# Ports sdk-node/tests/documents.test.ts. The Ruby SDK splits the namespace
# behind `client.documents`; methods accept positional `id` first (URL path
# fragment), followed by kwargs as needed.

RSpec.describe PoliPage::Resources::Documents do
  let(:client) { PoliPage::Client.new(api_key: "pp_sandbox_abc", max_retries: 0) }
  let(:descriptor_json) { DocumentDescriptorJSON.build }

  describe "#get" do
    it "GETs /v1/documents/:id and returns a DocumentDescriptor" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc_abc123")
             .to_return(status: 200, body: descriptor_json)

      desc = client.documents.get("doc_abc123")
      expect(desc).to be_a(PoliPage::DocumentDescriptor)
      expect(desc.document_id).to eq("doc_abc123")
      expect(stub).to have_been_requested
    end

    it "attaches the client back-reference so #download_pdf works" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc123").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "%PDF-1.4 stub")
      desc = client.documents.get("doc_abc123")
      expect(desc.download_pdf).to eq("%PDF-1.4 stub")
    end

    it "URL-encodes the document id" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc%20with%20space")
             .to_return(status: 200, body: descriptor_json)
      client.documents.get("doc with space")
      expect(stub).to have_been_requested
    end

    it "raises NotFoundError on 404" do
      stub_request(:get, "https://api.poli.page/v1/documents/missing")
        .to_return(status: 404, body: '{"code":"DOCUMENT_NOT_FOUND","message":"nope"}')
      expect { client.documents.get("missing") }.to raise_error(PoliPage::NotFoundError)
    end

    it "raises GoneError with code DOCUMENT_GONE on 410 (deleted or expired sandbox document)" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_old")
        .to_return(status: 410, body: '{"error":"DOCUMENT_GONE","detail":"gone"}')
      expect { client.documents.get("doc_old") }
        .to raise_error(PoliPage::GoneError) { |e| expect(e.code).to eq(PoliPage::ErrorCodes::DOCUMENT_GONE) }
    end

    it "decodes any environment name, e.g. staging" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc123")
        .to_return(status: 200, body: DocumentDescriptorJSON.build(environment: "staging"))
      expect(client.documents.get("doc_abc123").environment).to eq("staging")
    end

    it "defaults a missing metadata to {}" do
      body = JSON.generate(JSON.parse(descriptor_json).except("metadata"))
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc123").to_return(status: 200, body: body)
      expect(client.documents.get("doc_abc123").metadata).to eq({})
    end

    it "ignores response fields it does not know (e.g. a legacy version)" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc123")
        .to_return(status: 200, body: DocumentDescriptorJSON.build(version: "1.0.0"))
      expect(client.documents.get("doc_abc123").to_h).not_to have_key(:version)
    end
  end

  describe "#preview" do
    it "GETs /v1/documents/:id/preview, returns html + page_count from X-Document-Page-Count" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc/preview")
        .to_return(status: 200, body: "<html><body>page</body></html>",
                   headers: { "Content-Type" => "text/html", "X-Document-Page-Count" => "3" })

      result = client.documents.preview("doc_abc")
      expect(result).to be_a(PoliPage::DocumentPreviewResult)
      expect(result.html).to eq("<html><body>page</body></html>")
      expect(result.page_count).to eq(3)
    end

    it "defaults page_count to 0 when X-Document-Page-Count is absent" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc/preview")
        .to_return(status: 200, body: "<html/>", headers: { "Content-Type" => "text/html" })
      result = client.documents.preview("doc_abc")
      expect(result.page_count).to eq(0)
    end

    it "defaults page_count to 0 for non-numeric X-Document-Page-Count" do
      stub_request(:get, "https://api.poli.page/v1/documents/doc_abc/preview")
        .to_return(status: 200, body: "<html/>",
                   headers: { "Content-Type" => "text/html", "X-Document-Page-Count" => "garbage" })
      result = client.documents.preview("doc_abc")
      expect(result.page_count).to eq(0)
    end

    it "URL-encodes the document id" do
      stub = stub_request(:get, "https://api.poli.page/v1/documents/doc%2Fwith%2Fslashes/preview")
             .to_return(status: 200, body: "<html/>",
                        headers: { "X-Document-Page-Count" => "1" })
      client.documents.preview("doc/with/slashes")
      expect(stub).to have_been_requested
    end
  end

  describe "#thumbnails" do
    let(:thumbs_response) do
      JSON.generate(
        thumbnails: [
          { page: 1, width: 320, height: 452, contentType: "image/png", data: "img1" },
          { page: 2, width: 320, height: 452, contentType: "image/png", data: "img2" }
        ]
      )
    end

    it "POSTs to /v1/documents/:id/thumbnails wrapping options under `thumbnails`" do
      stub = stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
             .with do |req|
               body = JSON.parse(req.body)
               body == { "thumbnails" => { "width" => 320, "format" => "png" } }
             end
             .to_return(status: 200, body: thumbs_response)

      thumbs = client.documents.thumbnails("doc_abc", width: 320, format: "png")
      expect(thumbs).to be_an(Array)
      expect(thumbs.size).to eq(2)
      expect(thumbs.first).to be_a(PoliPage::Thumbnail)
      expect(thumbs.first.page).to eq(1)
      expect(thumbs.first.content_type).to eq("image/png")
      expect(stub).to have_been_requested
    end

    it "URL-encodes the document id" do
      stub_request(:post, "https://api.poli.page/v1/documents/doc%20with%20space/thumbnails")
        .to_return(status: 200, body: thumbs_response)
      result = client.documents.thumbnails("doc with space", width: 320)
      expect(result).to be_an(Array)
    end

    it "sends {} when no option is given" do
      stub = stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
             .with { |req| JSON.parse(req.body) == {} }
             .to_return(status: 200, body: thumbs_response)
      expect(client.documents.thumbnails("doc_abc").size).to eq(2)
      expect(stub).to have_been_requested
    end

    it "sends {} when every option is nil" do
      stub = stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
             .with { |req| JSON.parse(req.body) == {} }
             .to_return(status: 200, body: thumbs_response)
      client.documents.thumbnails("doc_abc", width: nil, format: nil)
      expect(stub).to have_been_requested
    end

    it "accepts webp and forwards every option without a client-side check" do
      stub = stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
             .with do |req|
               JSON.parse(req.body) == {
                 "thumbnails" => { "width" => 10, "format" => "webp", "quality" => 500, "pages" => [0] }
               }
             end
             .to_return(status: 200, body: thumbs_response)
      client.documents.thumbnails("doc_abc", width: 10, format: "webp", quality: 500, pages: [0])
      expect(stub).to have_been_requested
    end

    it "surfaces the API's 400 VALIDATION_ERROR for out-of-bounds options" do
      stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
        .to_return(status: 400, body: '{"error":"VALIDATION_ERROR","detail":"width must be >= 50"}')
      expect { client.documents.thumbnails("doc_abc", width: 10) }
        .to raise_error(PoliPage::ValidationError) { |e| expect(e.code).to eq("VALIDATION_ERROR") }
    end

    it "omits nil-valued knobs from the wire body" do
      stub = stub_request(:post, "https://api.poli.page/v1/documents/doc_abc/thumbnails")
             .with do |req|
               body = JSON.parse(req.body)
               body["thumbnails"] == { "width" => 320 }
             end
             .to_return(status: 200, body: thumbs_response)
      client.documents.thumbnails("doc_abc", width: 320)
      expect(stub).to have_been_requested
    end
  end

  describe "#delete" do
    it "DELETEs /v1/documents/:id and returns nil" do
      stub = stub_request(:delete, "https://api.poli.page/v1/documents/doc_abc")
             .to_return(status: 204, body: "")
      expect(client.documents.delete("doc_abc")).to be_nil
      expect(stub).to have_been_requested
    end

    it "URL-encodes the document id" do
      stub = stub_request(:delete, "https://api.poli.page/v1/documents/doc%20with%20space")
             .to_return(status: 204, body: "")
      client.documents.delete("doc with space")
      expect(stub).to have_been_requested
    end

    it "is idempotent: re-deleting an already-deleted document resolves on 204" do
      stub = stub_request(:delete, "https://api.poli.page/v1/documents/doc_abc")
             .to_return(status: 204, body: "")
      expect(client.documents.delete("doc_abc")).to be_nil
      expect(client.documents.delete("doc_abc")).to be_nil
      expect(stub).to have_been_requested.twice
    end
  end
end
