# frozen_string_literal: true

# Build `reference/types.mdx` — public types/value-objects/error-class summary.
module TypesPage
  module_function

  # Public types/value objects/resource namespaces, in the order they should
  # appear on the page. Each entry is the YARD path of a class/module.
  PUBLIC_TYPES = [
    "PoliPage::Client",
    "PoliPage::Resources::Render",
    "PoliPage::Resources::Documents",
    "PoliPage::ProjectModeInput",
    "PoliPage::InlineModeInput",
    "PoliPage::ThumbnailOptions",
    "PoliPage::PreviewResult",
    "PoliPage::DocumentDescriptor",
    "PoliPage::DocumentPreviewResult",
    "PoliPage::Thumbnail",
    "PoliPage::PageFormat",
    "PoliPage::Orientation",
    "PoliPage::RetryEvent"
  ].freeze

  def build
    blocks = PUBLIC_TYPES.map do |path|
      node = YARD::Registry.at(path)
      next if node.nil?

      lede = first_paragraph(node.docstring.to_s)
      lede = "_(See the source for the full definition.)_" if lede.empty?
      "### `#{path}`\n\n#{lede}\n"
    end.compact

    <<~MDX
      ---
      title: Types
      description: Public classes, value objects, and resource namespaces exported by the poli-page gem.
      ---

      The Ruby SDK exposes the public classes, value objects, and resource namespaces below. They live under the `PoliPage` module:

      ```ruby
      require "poli_page"
      ```

      #{blocks.join("\n")}
      For value-object internals (`Data.define`'d objects like `PoliPage::DocumentDescriptor`), see [the source on GitHub](https://github.com/poli-page/sdk-ruby/tree/main/lib/poli_page/models).
    MDX
  end

  def first_paragraph(doc)
    para = doc.to_s.split(/\n\s*\n/, 2).first.to_s.strip
    para
  end
end
