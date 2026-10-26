# frozen_string_literal: true

RSpec.describe PoliPage::RenderInput do
  it "carries project, template, data, and optional knobs as keyword fields" do
    input = described_class.new(project: "billing", template: "invoice", data: { x: 1 })
    expect(input.project).to eq("billing")
    expect(input.template).to eq("invoice")
    expect(input.data).to eq({ x: 1 })
  end

  it "has the seven wire fields plus idempotency_key, and no version" do
    expect(described_class.members).to eq(
      %i[project template data format orientation locale metadata idempotency_key]
    )
    expect { described_class.new(project: "p", template: "t", data: {}, version: "1.0.0") }
      .to raise_error(ArgumentError, /version/)
  end

  it "round-trips into method kwargs via .to_h" do
    input = described_class.new(project: "p", template: "t",
                                data: { a: 1 }, format: "A4", orientation: "portrait",
                                locale: "en-US", metadata: { cust: "c1" })
    expect(input.to_h).to eq(
      project: "p", template: "t", data: { a: 1 },
      format: "A4", orientation: "portrait", locale: "en-US",
      metadata: { cust: "c1" }
    )
  end

  it "defaults optional fields to nil" do
    input = described_class.new(project: "p", template: "t", data: {})
    expect(input.format).to be_nil
    expect(input.orientation).to be_nil
    expect(input.locale).to be_nil
    expect(input.metadata).to be_nil
  end

  it "is frozen and value-equal" do
    a = described_class.new(project: "p", template: "t", data: {})
    b = described_class.new(project: "p", template: "t", data: {})
    expect(a).to be_frozen
    expect(a).to eq(b)
  end

  it "carries an optional idempotency_key field (Data-shape parity with resource kwargs)" do
    input = described_class.new(project: "p", template: "t", data: {},
                                idempotency_key: "caller-key-123")
    expect(input.idempotency_key).to eq("caller-key-123")
  end

  it "defaults idempotency_key to nil and strips it from .to_h when unset" do
    input = described_class.new(project: "p", template: "t", data: {})
    expect(input.idempotency_key).to be_nil
    expect(input.to_h).not_to have_key(:idempotency_key)
  end

  it "includes idempotency_key in .to_h when set (round-trips into method kwargs)" do
    input = described_class.new(project: "p", template: "t", data: {},
                                idempotency_key: "caller-key-123")
    expect(input.to_h).to include(idempotency_key: "caller-key-123")
  end

  it "replaces ProjectModeInput and InlineModeInput, which are gone" do
    expect(PoliPage.const_defined?(:ProjectModeInput)).to be false
    expect(PoliPage.const_defined?(:InlineModeInput)).to be false
  end
end
