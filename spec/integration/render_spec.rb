# frozen_string_literal: true

# Integration test against the deployed develop API. Gated on:
#   - INTEGRATION=1
#   - POLI_PAGE_API_KEY=pp_test_...
#
# Defaults to the develop base URL but honours POLI_PAGE_BASE_URL,
# POLI_PAGE_TEST_PROJECT, POLI_PAGE_TEST_TEMPLATE, POLI_PAGE_TEST_VERSION
# (mirrors the Node integration tests).

return unless ENV["INTEGRATION"] == "1"

RSpec.describe "PoliPage::Client#render.preview (integration)" do
  before(:all) do
    skip "POLI_PAGE_API_KEY not set" unless ENV["POLI_PAGE_API_KEY"]
    WebMock.allow_net_connect!
  end

  after(:all) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:client) do
    opts = { api_key: ENV.fetch("POLI_PAGE_API_KEY") }
    opts[:base_url] = ENV["POLI_PAGE_TEST_BASE_URL"] if ENV["POLI_PAGE_TEST_BASE_URL"]
    PoliPage::Client.new(**opts)
  end

  let(:project)  { ENV.fetch("POLI_PAGE_TEST_PROJECT", "getting-started") }
  let(:template) { ENV.fetch("POLI_PAGE_TEST_TEMPLATE", "welcome") }
  let(:version)  { ENV.fetch("POLI_PAGE_TEST_VERSION", "1.0.0") }

  it "returns a PreviewResult with non-empty HTML" do
    result = client.render.preview(project: project, template: template, version: version,
                                   data: { name: "Ada" })
    expect(result).to be_a(PoliPage::PreviewResult)
    expect(result.html).to be_a(String)
    expect(result.html).not_to be_empty
    expect(result.total_pages).to be >= 1
    expect(result.environment).to(satisfy { |e| %w[sandbox live].include?(e) })
  end

  it "render.document returns a usable DocumentDescriptor" do
    desc = client.render.document(project: project, template: template, version: version,
                                  data: { name: "Ada" })
    expect(desc).to be_a(PoliPage::DocumentDescriptor)
    expect(desc.document_id).to be_a(String)
    expect(desc.presigned_pdf_url).to start_with("http")
    expect(desc.page_count).to be >= 1
  end

  it "render.pdf returns the PDF bytes (header %PDF-)" do
    pdf = client.render.pdf(project: project, template: template, version: version,
                            data: { name: "Ada" })
    expect(pdf).to be_a(String)
    expect(pdf.bytes.size).to be > 1_000
    expect(pdf[0, 5]).to eq("%PDF-")
  end

  it "render.pdf_stream yields the same bytes as render.pdf (block form)" do
    collected = +""
    collected.force_encoding(Encoding::ASCII_8BIT)
    client.render.pdf_stream(project: project, template: template, version: version,
                             data: { name: "Ada" }) { |chunk| collected << chunk }
    expect(collected[0, 5]).to eq("%PDF-")
    expect(collected.bytes.size).to be > 1_000
  end
end
