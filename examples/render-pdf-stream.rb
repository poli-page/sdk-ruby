# frozen_string_literal: true

# Demonstrates: client.render.pdf_stream — stream PDF chunks with bounded memory.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

# Block form — pipe straight to a file. The block is yielded raw chunks
# (binary Strings) as they arrive from the presigned URL.
File.open("invoice.pdf", "wb") do |io|
  client.render.pdf_stream(
    project:  "billing",
    template: "invoice",
    data:     { invoice_number: "INV-001", total: 1280 }
  ) { |chunk| io.write(chunk) }
end

# Enumerator form — when no block is given. Useful for piping through
# Enumerable chains or summing bytes for logging.
total = client.render.pdf_stream(
  project:  "billing",
  template: "invoice",
  data:     { invoice_number: "INV-001", total: 1280 }
).sum(&:bytesize)
puts "streamed #{total} bytes"
