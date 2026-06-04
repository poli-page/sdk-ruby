# frozen_string_literal: true

RSpec.describe PoliPage::ProjectModeInput do
  it "carries project, template, data, and optional knobs as keyword fields" do
    input = described_class.new(project: "billing", template: "invoice",
                                version: "1.0.0", data: { x: 1 })
    expect(input.project).to eq("billing")
    expect(input.template).to eq("invoice")
    expect(input.version).to eq("1.0.0")
    expect(input.data).to eq({ x: 1 })
  end

  it "round-trips into method kwargs via .to_h" do
    input = described_class.new(project: "p", template: "t", version: "1.0.0",
                                data: { a: 1 }, format: "A4", orientation: "portrait",
                                locale: "en-US", metadata: { cust: "c1" })
    expect(input.to_h).to eq(
      project: "p", template: "t", version: "1.0.0", data: { a: 1 },
      format: "A4", orientation: "portrait", locale: "en-US",
      metadata: { cust: "c1" }
    )
  end

  it "defaults optional fields to nil" do
    input = described_class.new(project: "p", template: "t", data: {})
    expect(input.version).to be_nil
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
end

RSpec.describe PoliPage::InlineModeInput do
  it "carries an inline template string + data" do
    input = described_class.new(template: "<h1>{{ name }}</h1>", data: { name: "Ada" })
    expect(input.template).to eq("<h1>{{ name }}</h1>")
    expect(input.data).to eq({ name: "Ada" })
  end

  it "round-trips into method kwargs via .to_h (no project field)" do
    input = described_class.new(template: "<p>x</p>", data: {}, format: "A4")
    h = input.to_h
    expect(h).to include(template: "<p>x</p>", data: {}, format: "A4")
    expect(h).not_to have_key(:project)
  end

  it "defaults optional fields to nil" do
    input = described_class.new(template: "<p>x</p>", data: {})
    expect(input.format).to be_nil
    expect(input.orientation).to be_nil
    expect(input.metadata).to be_nil
  end

  it "carries an optional idempotency_key field (Data-shape parity with resource kwargs)" do
    input = described_class.new(template: "<p>x</p>", data: {},
                                idempotency_key: "caller-key-456")
    expect(input.idempotency_key).to eq("caller-key-456")
  end

  it "defaults idempotency_key to nil and strips it from .to_h when unset" do
    input = described_class.new(template: "<p>x</p>", data: {})
    expect(input.idempotency_key).to be_nil
    expect(input.to_h).not_to have_key(:idempotency_key)
  end

  it "includes idempotency_key in .to_h when set" do
    input = described_class.new(template: "<p>x</p>", data: {},
                                idempotency_key: "caller-key-456")
    expect(input.to_h).to include(idempotency_key: "caller-key-456")
  end
end
