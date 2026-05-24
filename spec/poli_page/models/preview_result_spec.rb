# frozen_string_literal: true

RSpec.describe PoliPage::PreviewResult do
  it "is a Data value object with html, total_pages, environment" do
    result = described_class.new(html: "<p>x</p>", total_pages: 3, environment: "sandbox")
    expect(result.html).to eq("<p>x</p>")
    expect(result.total_pages).to eq(3)
    expect(result.environment).to eq("sandbox")
  end

  it "is frozen (Data semantics)" do
    expect(described_class.new(html: "x", total_pages: 1, environment: "sandbox")).to be_frozen
  end

  it "supports equality by value" do
    a = described_class.new(html: "x", total_pages: 1, environment: "sandbox")
    b = described_class.new(html: "x", total_pages: 1, environment: "sandbox")
    expect(a).to eq(b)
  end

  it "supports pattern matching via deconstruct_keys" do
    result = described_class.new(html: "<p>ok</p>", total_pages: 2, environment: "live")
    case result
    in { total_pages:, environment: "live" }
      expect(total_pages).to eq(2)
    else
      raise "did not match"
    end
  end
end
