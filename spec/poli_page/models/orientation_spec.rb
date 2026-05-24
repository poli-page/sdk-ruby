# frozen_string_literal: true

RSpec.describe PoliPage::Orientation do
  it "exposes 'portrait' and 'landscape'" do
    expect(described_class::ORIENTATIONS).to eq(Set["portrait", "landscape"])
  end

  it "ORIENTATIONS is a frozen Set" do
    expect(described_class::ORIENTATIONS).to be_frozen
  end

  it ".valid? returns true for portrait and landscape" do
    expect(described_class.valid?("portrait")).to be true
    expect(described_class.valid?("landscape")).to be true
  end

  it ".valid? returns false for anything else" do
    expect(described_class.valid?("sideways")).to be false
    expect(described_class.valid?(nil)).to be false
  end
end
