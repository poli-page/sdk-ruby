# frozen_string_literal: true

RSpec.describe PoliPage::DocumentDescriptor do
  let(:fields) do
    {
      document_id: "doc_abc123", organization_id: "org_xyz",
      project_id: "proj_42", project_slug: "billing",
      template_id: "tpl_invoice_v1", template_slug: "invoice",
      version: "1.0.0", environment: "live", api_key_id: "key_live_abc",
      format: "A4", orientation: "portrait", locale: "en-US",
      page_count: 2, size_bytes: 38_421,
      created_at: "2026-04-30T19:45:22Z",
      metadata: {}, expires_at: "2026-04-30T20:00:22Z",
      presigned_pdf_url: "https://s3.example/presigned/x.pdf",
      _client: nil
    }
  end

  it "is a Data value object with the documented wire fields + a _client back-reference" do
    desc = described_class.new(**fields)
    expect(desc.document_id).to eq("doc_abc123")
    expect(desc.presigned_pdf_url).to eq("https://s3.example/presigned/x.pdf")
    expect(desc.page_count).to eq(2)
  end

  it "is frozen" do
    expect(described_class.new(**fields)).to be_frozen
  end

  it "accepts nil for nullable wire fields (project_id, orientation, locale, ...)" do
    nullable = fields.merge(project_id: nil, orientation: nil, locale: nil)
    desc = described_class.new(**nullable)
    expect(desc.project_id).to be_nil
    expect(desc.orientation).to be_nil
    expect(desc.locale).to be_nil
  end

  it "hides _client from #to_h output" do
    client = instance_double(PoliPage::Client)
    desc = described_class.new(**fields, _client: client)
    expect(desc.to_h).not_to have_key(:_client)
    expect(desc.to_h[:document_id]).to eq("doc_abc123")
  end

  it "has a compact #inspect that does not dump the client" do
    client = instance_double(PoliPage::Client)
    desc = described_class.new(**fields, _client: client)
    expect(desc.inspect).to include("doc_abc123")
    expect(desc.inspect).not_to include("_client")
  end

  describe "#download_pdf" do
    it "delegates to the back-reference client to fetch the bytes" do
      client = instance_double(PoliPage::Client)
      desc = described_class.new(**fields, _client: client)
      allow(client).to receive(:fetch_bytes).with(desc.presigned_pdf_url).and_return("%PDF-1.4 stub")

      expect(desc.download_pdf).to eq("%PDF-1.4 stub")
    end

    it "raises InternalError when _client is missing (descriptor wasn't attached)" do
      desc = described_class.new(**fields)
      expect { desc.download_pdf }
        .to raise_error(PoliPage::InternalError, /missing client back-reference/)
    end
  end
end
