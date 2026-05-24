# frozen_string_literal: true

# Integration test against the deployed develop API. Gated on:
#   - INTEGRATION=1
#   - POLI_PAGE_API_KEY=pp_test_...

return unless ENV["INTEGRATION"] == "1"

RSpec.describe "PoliPage::Client#documents.* (integration)" do
  before(:all) do
    skip "POLI_PAGE_API_KEY not set" unless ENV["POLI_PAGE_API_KEY"]
    WebMock.allow_net_connect!
  end

  after(:all) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:client) do
    PoliPage::Client.new(
      api_key:  ENV.fetch("POLI_PAGE_API_KEY"),
      base_url: ENV.fetch("POLI_PAGE_BASE_URL", "https://api-develop.poli.page")
    )
  end

  let(:project)  { ENV.fetch("POLI_PAGE_TEST_PROJECT", "getting-started") }
  let(:template) { ENV.fetch("POLI_PAGE_TEST_TEMPLATE", "welcome") }
  let(:version)  { ENV.fetch("POLI_PAGE_TEST_VERSION", "1.0.0") }

  let(:descriptor) do
    client.render.document(project: project, template: template, version: version,
                           data: { name: "Ada" })
  end

  it "documents.get round-trips a freshly rendered descriptor" do
    fetched = client.documents.get(descriptor.document_id)
    expect(fetched).to be_a(PoliPage::DocumentDescriptor)
    expect(fetched.document_id).to eq(descriptor.document_id)
    expect(fetched.page_count).to eq(descriptor.page_count)
  end

  it "documents.preview returns html + page_count" do
    result = client.documents.preview(descriptor.document_id)
    expect(result).to be_a(PoliPage::DocumentPreviewResult)
    expect(result.html).not_to be_empty
    expect(result.page_count).to be >= 1
  end

  it "documents.thumbnails returns an array of Thumbnail" do
    thumbs = client.documents.thumbnails(descriptor.document_id, width: 320)
    expect(thumbs).to be_an(Array)
    expect(thumbs).not_to be_empty
    expect(thumbs.first).to be_a(PoliPage::Thumbnail)
    expect(thumbs.first.width).to eq(320)
    expect(thumbs.first.data).to be_a(String)
  end

  it "documents.delete removes the document; re-deleting raises GoneError" do
    id = descriptor.document_id
    expect(client.documents.delete(id)).to be_nil
    expect { client.documents.delete(id) }.to raise_error(PoliPage::GoneError)
  end
end
