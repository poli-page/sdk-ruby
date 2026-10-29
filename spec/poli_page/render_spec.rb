# frozen_string_literal: true

# Ports sdk-node/tests/render.test.ts for the three render methods, which
# all POST /v1/render.

RSpec.describe PoliPage::Resources::Render do
  let(:client) { PoliPage::Client.new(api_key: "pp_sandbox_abc", max_retries: 0) }
  let(:descriptor_json) { DocumentDescriptorJSON.build }

  it "has no #preview (POST /v1/render/preview was removed from the API)" do
    expect(client.render).not_to respond_to(:preview)
    expect(PoliPage.const_defined?(:PreviewResult)).to be false
    expect(PoliPage::Internal::Constants.const_defined?(:PATH_RENDER_PREVIEW)).to be false
  end

  describe "#document" do
    it "POSTs to /v1/render and returns a DocumentDescriptor" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .with(body: hash_including("project" => "billing", "template" => "invoice"))
        .to_return(status: 200, body: descriptor_json)

      desc = client.render.document(project: "billing", template: "invoice",
                                    data: { invoice_number: "INV-001" })

      expect(desc).to be_a(PoliPage::DocumentDescriptor)
      expect(desc.document_id).to eq("doc_abc123")
      expect(desc.presigned_pdf_url).to eq("https://s3.example/presigned/x.pdf")
      expect(desc.page_count).to eq(2)
    end

    it "attaches the client back-reference so #download_pdf works" do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "%PDF-1.4 stub")

      desc = client.render.document(project: "billing", template: "invoice", data: {})
      expect(desc.download_pdf).to eq("%PDF-1.4 stub")
    end

    it "returns any environment name unchanged (open set)" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 200, body: DocumentDescriptorJSON.build(environment: "staging"))

      desc = client.render.document(project: "billing", template: "invoice", data: {})
      expect(desc.environment).to eq("staging")
    end

    it "ignores response fields it does not know (e.g. a legacy version)" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 200, body: DocumentDescriptorJSON.build(version: "1.0.0", newField: true))

      desc = client.render.document(project: "billing", template: "invoice", data: {})
      expect(desc.document_id).to eq("doc_abc123")
      expect(desc.to_h).not_to have_key(:version)
    end

    it "sends exactly the seven documented fields" do
      stub = stub_request(:post, "https://api.poli.page/v1/render")
             .with do |req|
               JSON.parse(req.body) == {
                 "project" => "billing", "template" => "invoice", "data" => { "invoiceNumber" => "INV-001" },
                 "metadata" => { "customerId" => "cust_1" }, "format" => "A4",
                 "orientation" => "landscape", "locale" => "fr-FR"
               }
             end
             .to_return(status: 200, body: descriptor_json)

      client.render.document(project: "billing", template: "invoice", data: { invoiceNumber: "INV-001" },
                             metadata: { customerId: "cust_1" }, format: "A4",
                             orientation: "landscape", locale: "fr-FR", idempotency_key: "abc")
      expect(stub).to have_been_requested
    end

    it "sends the keys of data and metadata exactly as given, at every depth" do
      sent = nil
      stub_request(:post, "https://api.poli.page/v1/render")
        .with { |req| sent = JSON.parse(req.body) }
        .to_return(status: 200, body: descriptor_json)

      client.render.document(project: "p", template: "t",
                             data: { customer_id: "c1", lineItems: [{ unit_price: 9 }], "some_key" => 1 },
                             metadata: { customer_id: "c1", customerId: "c2" })
      expect(sent["data"]).to eq({ "customer_id" => "c1", "lineItems" => [{ "unit_price" => 9 }], "some_key" => 1 })
      expect(sent["metadata"]).to eq({ "customer_id" => "c1", "customerId" => "c2" })
    end

    it "returns metadata exactly as the API stored it" do
      body = JSON.parse(descriptor_json).merge(
        "metadata" => { "someKey" => "a", "some_key" => "b", "nested" => { "innerKey" => 1 } }
      )
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: JSON.generate(body))

      doc = client.render.document(project: "p", template: "t", data: {})
      expect(doc.metadata).to eq({ "someKey" => "a", "some_key" => "b", "nested" => { "innerKey" => 1 } })
      expect(doc.page_count).to be_a(Integer)
    end

    it "omits unset optional fields from the wire body (no nulls)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render")
             .with { |req| JSON.parse(req.body) == { "project" => "p", "template" => "t", "data" => {} } }
             .to_return(status: 200, body: descriptor_json)

      client.render.document(project: "p", template: "t", data: {})
      expect(stub).to have_been_requested
    end

    it "rejects a version keyword before any request (no version input)" do
      stub = stub_request(:post, "https://api.poli.page/v1/render")
      expect { client.render.document(project: "p", template: "t", data: {}, version: "1.0.0") }
        .to raise_error(ArgumentError, /version/)
      expect(stub).not_to have_been_requested
    end

    it "surfaces a 404 { error, detail } as code TEMPLATE_NOT_FOUND with the detail as message" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 404,
                   body: '{"error":"TEMPLATE_NOT_FOUND","detail":"Template \'nope\' not found","requestId":"r1"}')
      expect { client.render.document(project: "getting-started", template: "nope", data: {}) }
        .to raise_error(PoliPage::NotFoundError) { |e|
          expect(e.code).to eq(PoliPage::ErrorCodes::TEMPLATE_NOT_FOUND)
          expect(e.status).to eq(404)
          expect(e.message).to eq("Template 'nope' not found")
        }
    end

    it "passes an unknown error code through verbatim" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 409, body: '{"error":"SOME_FUTURE_CODE","detail":"later"}')
      expect { client.render.document(project: "p", template: "t", data: {}) }
        .to raise_error(PoliPage::APIError) { |e|
          expect(e.code).to eq("SOME_FUTURE_CODE")
          expect(e.message).to eq("later")
        }
    end

    it "raises ValidationError on 400" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 400, body: '{"error":"VALIDATION_ERROR","detail":"bad input"}',
                   headers: { "x-request-id" => "req_bad" })
      expect { client.render.document(project: "p", template: "t", data: {}) }
        .to raise_error(PoliPage::ValidationError) { |e|
          expect(e.code).to eq("VALIDATION_ERROR")
          expect(e.status).to eq(400)
          expect(e.request_id).to eq("req_bad")
          expect(e.message).to eq("bad input")
        }
    end

    it "raises AuthenticationError on 401" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 401, body: '{"error":"INVALID_API_KEY","detail":"bad key"}')
      expect { client.render.document(project: "p", template: "t", data: {}) }
        .to raise_error(PoliPage::AuthenticationError)
    end

    it "raises RateLimitError on 429" do
      stub_request(:post, "https://api.poli.page/v1/render")
        .to_return(status: 429, body: '{"error":"QUOTA_EXCEEDED","detail":"quota"}')
      expect { client.render.document(project: "p", template: "t", data: {}) }
        .to raise_error(PoliPage::RateLimitError)
    end

    it "raises PROJECT_REQUIRED_FOR_DOCUMENT before any request when project is nil or empty" do
      stub = stub_request(:post, "https://api.poli.page/v1/render")
      [nil, ""].each do |project|
        expect { client.render.document(project: project, template: "t", data: {}) }
          .to raise_error(PoliPage::InvalidOptionsError, "project is required") { |e|
            expect([e.code, e.status]).to eq(["PROJECT_REQUIRED_FOR_DOCUMENT", nil])
          }
      end
      expect(stub).not_to have_been_requested
    end
  end

  describe "codes never retried (sdk-specification.md §9.1)" do
    let(:client) { PoliPage::Client.new(api_key: "pp_sandbox_abc", max_retries: 2) }

    { "QUOTA_EXCEEDED" => 429, "OVERAGE_CAP_EXCEEDED" => 429, "STORAGE_ACCESS_DENIED" => 502 }.each do |code, status|
      it "does not retry #{status} #{code}, even with a Retry-After" do
        stub = stub_request(:post, "https://api.poli.page/v1/render")
               .to_return(status: status, body: %({"error":"#{code}"}), headers: { "Retry-After" => "1" })
        expect { client.render.document(project: "p", template: "t", data: {}) }
          .to raise_error(PoliPage::Error) { |e| expect([e.code, e.retryable?]).to eq([code, false]) }
        expect(stub).to have_been_requested.once
      end
    end
  end

  describe "#pdf" do
    it "POSTs /v1/render, fetches the presigned URL, and returns the bytes" do
      stub_render = stub_request(:post, "https://api.poli.page/v1/render")
                    .to_return(status: 200, body: descriptor_json)
      stub_pdf = stub_request(:get, "https://s3.example/presigned/x.pdf")
                 .to_return(status: 200, body: "%PDF-1.4 stub")

      pdf = client.render.pdf(project: "billing", template: "invoice", data: {})
      expect(pdf).to eq("%PDF-1.4 stub")
      expect(stub_render).to have_been_requested
      expect(stub_pdf).to have_been_requested
    end

    it "raises DownloadError if the presigned fetch fails" do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 403, body: "<Error/>")

      expect { client.render.pdf(project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::DownloadError)
    end
  end

  describe "#pdf_stream" do
    before do
      stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
      stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "AAAABBBBCCCC")
    end

    it "yields the PDF body in chunks when a block is given" do
      collected = +""
      client.render.pdf_stream(project: "billing", template: "invoice", data: {}) do |chunk|
        collected << chunk
      end
      expect(collected).to eq("AAAABBBBCCCC")
    end

    it "returns an Enumerator when called without a block" do
      enum = client.render.pdf_stream(project: "billing", template: "invoice", data: {})
      expect(enum).to be_a(Enumerator)
      collected = +""
      enum.each { |chunk| collected << chunk }
      expect(collected).to eq("AAAABBBBCCCC")
    end
  end
end
