# frozen_string_literal: true

RSpec.describe PoliPage::RetryEvent do
  it "is a Data value object with attempt, delay, reason" do
    err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500)
    event = described_class.new(attempt: 2, delay: 0.5, reason: err)
    expect(event.attempt).to eq(2)
    expect(event.delay).to eq(0.5)
    expect(event.reason).to be(err)
  end

  it "is frozen" do
    err = PoliPage::APIError.new("boom", code: "INTERNAL_ERROR", status: 500)
    expect(described_class.new(attempt: 1, delay: 0.5, reason: err)).to be_frozen
  end
end
