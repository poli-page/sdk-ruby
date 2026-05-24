# frozen_string_literal: true

RSpec.describe PoliPage::PageFormat do
  it "exposes the 12 valid page-format strings (sdk-specification.md §4.1)" do
    expect(described_class::FORMATS).to include("A3", "A4", "A5", "Letter", "Legal", "Tabloid")
  end

  it "FORMATS is a frozen Set" do
    expect(described_class::FORMATS).to be_a(Set)
    expect(described_class::FORMATS).to be_frozen
  end

  it ".valid? returns true for known formats" do
    expect(described_class.valid?("A4")).to be true
  end

  it ".valid? returns false for unknown formats" do
    expect(described_class.valid?("A99")).to be false
    expect(described_class.valid?(nil)).to be false
  end
end
