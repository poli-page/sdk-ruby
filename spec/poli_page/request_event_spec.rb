# frozen_string_literal: true

RSpec.describe PoliPage::RequestEvent do
  it "is a Data value object with method, url, attempt" do
    event = described_class.new(method: "POST", url: "https://api.poli.page/v1/render", attempt: 1)
    expect(event.method).to eq("POST")
    expect(event.url).to eq("https://api.poli.page/v1/render")
    expect(event.attempt).to eq(1)
  end

  it "is frozen" do
    expect(described_class.new(method: "GET", url: "u", attempt: 1)).to be_frozen
  end

  it "uses 1-based attempt counter (parity with sdk-node)" do
    event = described_class.new(method: "POST", url: "u", attempt: 1)
    expect(event.attempt).to eq(1)
  end
end
