# frozen_string_literal: true

RSpec.describe PoliPage::RetryEvent do
  it "is a Data value object with attempt, delay_ms (Integer), reason" do
    err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500)
    event = described_class.new(attempt: 2, delay_ms: 500, reason: err)
    expect(event.attempt).to eq(2)
    expect(event.delay_ms).to eq(500)
    expect(event.delay_ms).to be_a(Integer)
    expect(event.reason).to be(err)
  end

  it "no longer exposes `.delay` (renamed to delay_ms per Plan 0 / D3)" do
    err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500)
    event = described_class.new(attempt: 1, delay_ms: 500, reason: err)
    expect(event).not_to respond_to(:delay)
  end

  it "is frozen" do
    err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500)
    expect(described_class.new(attempt: 1, delay_ms: 500, reason: err)).to be_frozen
  end
end
