# frozen_string_literal: true

RSpec.describe PoliPage::ResponseEvent do
  it "is a Data value object with status, request_id, duration_ms" do
    event = described_class.new(status: 200, request_id: "req_abc", duration_ms: 42)
    expect(event.status).to eq(200)
    expect(event.request_id).to eq("req_abc")
    expect(event.duration_ms).to eq(42)
  end

  it "accepts nil request_id (header absent)" do
    event = described_class.new(status: 200, request_id: nil, duration_ms: 7)
    expect(event.request_id).to be_nil
  end

  it "is frozen" do
    expect(described_class.new(status: 200, request_id: nil, duration_ms: 1)).to be_frozen
  end
end
