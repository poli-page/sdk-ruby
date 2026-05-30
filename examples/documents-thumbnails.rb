# frozen_string_literal: true

# Demonstrates: client.documents.thumbnails — get base64-encoded page
# thumbnails for a stored document.
require "base64"
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

thumbs = client.documents.thumbnails(
  "doc_INV-001",
  width:  320,
  format: "png",
  pages:  [1, 2]
)

# Each entry is a `PoliPage::Thumbnail` carrying base64-encoded image bytes.
thumbs.each do |t|
  File.binwrite("page-#{t.page}.png", Base64.decode64(t.data))
  puts "page #{t.page}: #{t.width}x#{t.height} #{t.content_type}"
end
