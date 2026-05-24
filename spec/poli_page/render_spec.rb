# frozen_string_literal: true

# Ports the preview-related tests from sdk-node/tests/render.test.ts (the
# `renderPreview` describe block). Other render.* methods land in Phase 3.

RSpec.describe PoliPage::Resources::Render do
  let(:client) { PoliPage::Client.new(api_key: "pp_test_abc", max_retries: 0) }

  describe "#preview" do
    let(:body) do
      JSON.generate({ html: "<p>preview</p>", totalPages: 3, environment: "sandbox" })
    end

    it "POSTs to /v1/render/preview and returns html + total_pages + environment" do
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      result = client.render.preview(template: "<p>x</p>", data: {})

      expect(result).to be_a(PoliPage::PreviewResult)
      expect(result.html).to eq("<p>preview</p>")
      expect(result.total_pages).to eq(3)
      expect(result.environment).to eq("sandbox")
    end

    it "accepts project mode (project + template slugs)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with(body: hash_including("project" => "billing", "template" => "invoice", "version" => "1.0.0"))
             .to_return(status: 200, body: body)
      client.render.preview(project: "billing", template: "invoice", version: "1.0.0", data: { x: 1 })
      expect(stub).to have_been_requested
    end

    it "accepts inline mode (the only render-* method that does)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with(body: hash_including("template" => "<h1>inline</h1>"))
             .to_return(status: 200, body: body)
      client.render.preview(template: "<h1>inline</h1>", data: {})
      expect(stub).to have_been_requested
    end

    it "translates snake_case kwargs to camelCase on the wire and strips idempotency_key from body" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with do |req|
               parsed = JSON.parse(req.body)
               parsed["template"] == "<p>x</p>" &&
                 !parsed.key?("idempotency_key") &&
                 !parsed.key?("idempotencyKey")
             end
        .to_return(status: 200, body: body)

      client.render.preview(template: "<p>x</p>", data: {}, idempotency_key: "abc")
      expect(stub).to have_been_requested
    end

    it "forwards metadata in the request body (camelCased)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with { |req| JSON.parse(req.body)["metadata"] == { "customerId" => "cust_1" } }
             .to_return(status: 200, body: body)
      client.render.preview(template: "<p>x</p>", data: {}, metadata: { customer_id: "cust_1" })
      expect(stub).to have_been_requested
    end

    it "omits nil-valued optional fields from the wire body (Hash#compact)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render/preview")
             .with do |req|
               parsed = JSON.parse(req.body)
               !parsed.key?("locale") && !parsed.key?("orientation") && !parsed.key?("metadata")
             end
        .to_return(status: 200, body: body)
      client.render.preview(template: "<p>x</p>", data: {})
      expect(stub).to have_been_requested
    end

    it "raises ValidationError on 400" do
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad input"}',
                   headers: { "x-request-id" => "req_bad" })
      expect { client.render.preview(template: "<p>x</p>", data: {}) }
        .to raise_error(PoliPage::ValidationError) { |e|
          expect(e.code).to eq("VALIDATION_ERROR")
          expect(e.status).to eq(400)
          expect(e.request_id).to eq("req_bad")
          expect(e.message).to eq("bad input")
        }
    end

    it "raises AuthenticationError on 401" do
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 401, body: '{"code":"INVALID_API_KEY","message":"bad key"}')
      expect { client.render.preview(template: "<p>x</p>", data: {}) }
        .to raise_error(PoliPage::AuthenticationError)
    end

    it "raises RateLimitError on 429" do
      stub_request(:post, "https://api.poli.page/v1/render/preview")
        .to_return(status: 429, body: '{"code":"QUOTA_EXCEEDED","message":"quota"}')
      expect { client.render.preview(template: "<p>x</p>", data: {}) }
        .to raise_error(PoliPage::RateLimitError)
    end
  end

  describe "#document" do
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

    it "POSTs to /v1/render and returns a DocumentDescriptor" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .with(body: hash_including("project" => "billing", "template" => "invoice"))
        .to_return(status: 200, body: descriptor_json)

      desc = client.render.document(project: "billing", template: "invoice",
                                    version: "1.0.0", data: { invoice_number: "INV-001" })

      expect(desc).to be_a(PoliPage::DocumentDescriptor)
      expect(desc.document_id).to eq("doc_abc123")
      expect(desc.presigned_pdf_url).to eq("https://s3.example/presigned/x.pdf")
      expect(desc.page_count).to eq(2)
    end

    it "attaches the client back-reference so #download_pdf works" do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "%PDF-1.4 stub")

      desc = client.render.document(project: "billing", template: "invoice",
                                    version: "1.0.0", data: {})
      expect(desc.download_pdf).to eq("%PDF-1.4 stub")
    end
  end

  describe "#pdf" do
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

    it "POSTs /v1/render, fetches the presigned URL, and returns the bytes" do
      stub_render = stub_request(:post, "https://api.poli.page/v1/render")
                    .to_return(status: 200, body: descriptor_json)
      stub_pdf = stub_request(:get, "https://s3.example/presigned/x.pdf")
                 .to_return(status: 200, body: "%PDF-1.4 stub")

      pdf = client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: {})
      expect(pdf).to eq("%PDF-1.4 stub")
      expect(stub_render).to have_been_requested
      expect(stub_pdf).to have_been_requested
    end

    it "raises DownloadError if the presigned fetch fails" do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 403, body: "<Error/>")

      expect { client.render.pdf(project: "billing", template: "invoice", version: "1.0.0", data: {}) }
        .to raise_error(PoliPage::DownloadError)
    end
  end

  describe "#pdf_stream" do
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

    before do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "AAAABBBBCCCC")
    end

    it "yields the PDF body in chunks when a block is given" do
      collected = +""
      client.render.pdf_stream(project: "billing", template: "invoice", version: "1.0.0", data: {}) do |chunk|
        collected << chunk
      end
      expect(collected).to eq("AAAABBBBCCCC")
    end

    it "returns an Enumerator when called without a block" do
      enum = client.render.pdf_stream(project: "billing", template: "invoice", version: "1.0.0", data: {})
      expect(enum).to be_a(Enumerator)
      collected = +""
      enum.each { |chunk| collected << chunk }
      expect(collected).to eq("AAAABBBBCCCC")
    end
  end
end
