# frozen_string_literal: true

# Per sdk-ruby-plan.md §5.4 and §3.1 spec/internal/wire_spec.rb.
# Snake_case Hash keys ↔ camelCase Hash keys, recursive.

RSpec.describe PoliPage::Internal::Wire do
  describe ".to_wire (snake_case → camelCase outgoing)" do
    it "transforms top-level symbol keys" do
      expect(described_class.to_wire(project: "billing", template: "invoice"))
        .to eq({ "project" => "billing", "template" => "invoice" })
    end

    it "transforms snake_case symbols into camelCase strings" do
      expect(described_class.to_wire(idempotency_key: "abc", request_id: "r1"))
        .to eq({ "idempotencyKey" => "abc", "requestId" => "r1" })
    end

    it "recursively transforms nested hashes" do
      input = { user: { first_name: "Ada", last_name: "Lovelace" } }
      expect(described_class.to_wire(input))
        .to eq({ "user" => { "firstName" => "Ada", "lastName" => "Lovelace" } })
    end

    it "recursively transforms hashes inside arrays" do
      input = { line_items: [{ unit_price: 9 }, { unit_price: 4 }] }
      expect(described_class.to_wire(input))
        .to eq({ "lineItems" => [{ "unitPrice" => 9 }, { "unitPrice" => 4 }] })
    end

    it "leaves primitives untouched" do
      expect(described_class.to_wire("string")).to eq("string")
      expect(described_class.to_wire(42)).to eq(42)
      expect(described_class.to_wire(true)).to be true
      expect(described_class.to_wire(nil)).to be_nil
    end

    it "leaves single-word keys unchanged" do
      expect(described_class.to_wire(data: { x: 1 }))
        .to eq({ "data" => { "x" => 1 } })
    end

    it "handles string keys as well as symbol keys" do
      expect(described_class.to_wire("snake_case" => 1))
        .to eq({ "snakeCase" => 1 })
    end
  end

  describe ".from_wire (camelCase → snake_case incoming)" do
    it "transforms top-level string keys to snake_case symbols" do
      expect(described_class.from_wire({ "totalPages" => 3, "environment" => "draft" }))
        .to eq({ total_pages: 3, environment: "draft" })
    end

    it "recursively transforms nested hashes" do
      input = { "documentDescriptor" => { "presignedPdfUrl" => "https://x" } }
      expect(described_class.from_wire(input))
        .to eq({ document_descriptor: { presigned_pdf_url: "https://x" } })
    end

    it "recursively transforms hashes inside arrays" do
      input = { "thumbnails" => [{ "pageNumber" => 1, "imageUrl" => "u1" }] }
      expect(described_class.from_wire(input))
        .to eq({ thumbnails: [{ page_number: 1, image_url: "u1" }] })
    end

    it "round-trips snake_case → camelCase → snake_case" do
      original = { project: "p", line_items: [{ unit_price: 9, vat_pct: 21 }] }
      wired = described_class.to_wire(original)
      restored = described_class.from_wire(wired)
      expect(restored).to eq(original)
    end

    it "leaves primitives untouched" do
      expect(described_class.from_wire(42)).to eq(42)
      expect(described_class.from_wire(nil)).to be_nil
      expect(described_class.from_wire("html")).to eq("html")
    end
  end
end

RSpec.describe PoliPage::Internal::UUID do
  describe ".generate" do
    it "returns an RFC 4122-shaped UUID string" do
      uuid = described_class.generate
      expect(uuid).to be_a(String)
      expect(uuid).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it "returns a different value on each call" do
      expect(described_class.generate).not_to eq(described_class.generate)
    end
  end
end
