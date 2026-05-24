# frozen_string_literal: true

RSpec.describe PoliPage::DocumentPreviewResult do
  it "is a Data value object with html and page_count (NOT total_pages)" do
    result = described_class.new(html: "<html>x</html>", page_count: 3)
    expect(result.html).to eq("<html>x</html>")
    expect(result.page_count).to eq(3)
  end

  it "does not expose :total_pages — distinct from PreviewResult by spec" do
    result = described_class.new(html: "x", page_count: 1)
    expect(result.respond_to?(:total_pages)).to be false
    expect(result.to_h.keys).to contain_exactly(:html, :page_count)
  end

  it "is frozen" do
    expect(described_class.new(html: "x", page_count: 1)).to be_frozen
  end
end

RSpec.describe PoliPage::Thumbnail do
  let(:fields) do
    { page: 1, width: 320, height: 452, content_type: "image/png", data: "iVBOR...base64" }
  end

  it "is a Data value object with page, width, height, content_type, data" do
    thumb = described_class.new(**fields)
    expect(thumb.page).to eq(1)
    expect(thumb.width).to eq(320)
    expect(thumb.height).to eq(452)
    expect(thumb.content_type).to eq("image/png")
    expect(thumb.data).to eq("iVBOR...base64")
  end

  it "is frozen" do
    expect(described_class.new(**fields)).to be_frozen
  end
end

RSpec.describe PoliPage::ThumbnailOptions do
  it "requires :width and defaults others to nil" do
    opts = described_class.new(width: 320)
    expect(opts.width).to eq(320)
    expect(opts.format).to be_nil
    expect(opts.quality).to be_nil
    expect(opts.pages).to be_nil
  end

  it "carries format, quality, pages" do
    opts = described_class.new(width: 320, format: "jpeg", quality: 80, pages: [1, 2])
    expect(opts.format).to eq("jpeg")
    expect(opts.quality).to eq(80)
    expect(opts.pages).to eq([1, 2])
  end

  it "#to_h drops nil-valued knobs" do
    opts = described_class.new(width: 320, format: "png")
    expect(opts.to_h).to eq(width: 320, format: "png")
  end

  it "is frozen" do
    expect(described_class.new(width: 320)).to be_frozen
  end
end
