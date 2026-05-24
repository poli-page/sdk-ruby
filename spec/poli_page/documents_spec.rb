# frozen_string_literal: true

# Ports sdk-node/tests/documents.test.ts. The Ruby SDK splits the namespace
# behind `client.documents`; methods accept positional `id` first (URL path
# fragment), followed by kwargs as needed.

RSpec.describe PoliPage::Resources::Documents do
  let(:client) { PoliPage::Client.new(api_key: "pp_test_abc", max_retries: 0) }
  let(:descriptor_json) do
    JSON.generate(
      documentId: "doc_abc123", organizationId: "org_xyz",
      projectId: "proj_42", projectSlug: "billing",
      templateId: "tpl_invoice_v1", templateSlug: "invoice",
      version: "1.0.0", environment: "live", apiKeyId: "key_live_abc",
      format: "A4", orientation: "portrait", locale: "en-US",
      pageCount: 2, sizeBytes: 38_421,
      createdAt: "2026-04-30T19:45:22Z", metadata: {},
      expiresAt: "2026-04-30T20:00:22Z",
      presignedPdfUrl: "https://s3.example/presigned/x.pdf"
    )
  end

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

    it "raises GoneError on 410 (re-deleting an already-deleted document)" do
      stub_request(:delete, "https://api.poli.page/v1/documents/doc_abc")
        .to_return(status: 410, body: '{"code":"GONE","message":"already deleted"}')
      expect { client.documents.delete("doc_abc") }.to raise_error(PoliPage::GoneError)
    end
  end
end
