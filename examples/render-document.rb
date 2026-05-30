# frozen_string_literal: true

# Demonstrates: client.render.document — render and store the document on
# Poli Page's servers. Returns a `PoliPage::DocumentDescriptor` with a
# back-reference to the client so `#download_pdf` works.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

doc = client.render.document(
  project:  "billing",
  template: "invoice",
  data:     { invoice_number: "INV-001", total: 1280 },
  metadata: { customer_id: "cust_123" }
)

# `doc.document_id` is the stored document's identifier — use it with
# `client.documents.*` to fetch, preview, thumbnail, or delete later.
puts "stored as document #{doc.document_id} (#{doc.page_count} page(s))"

# Pull the PDF bytes via the (15-minute TTL) presigned URL.
pdf = doc.download_pdf
File.binwrite("invoice.pdf", pdf)
