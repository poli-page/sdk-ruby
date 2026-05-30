# frozen_string_literal: true

# Demonstrates: client.documents.preview — fetch the stored document's
# paginated HTML plus its page count, without re-rendering. The body is
# `text/html`, not a JSON envelope.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

stored = client.documents.preview("doc_INV-001")

puts "#{stored.page_count} page(s), #{stored.html.length} chars"
File.write("preview.html", stored.html)
