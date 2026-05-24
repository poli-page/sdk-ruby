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
    PoliPage::Client.new(
      api_key:  ENV.fetch("POLI_PAGE_API_KEY"),
      base_url: ENV.fetch("POLI_PAGE_BASE_URL", "https://api-develop.poli.page")
    )
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
end
