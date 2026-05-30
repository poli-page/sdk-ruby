# frozen_string_literal: true

# Demonstrates: client.render.pdf — fetch the rendered PDF bytes in memory.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

pdf = client.render.pdf(
  project:  "billing",
  template: "invoice",
  data:     { invoice_number: "INV-001", total: 1280 }
)

# `pdf` is a binary-encoded String of PDF bytes.
File.binwrite("invoice.pdf", pdf)
puts "wrote #{pdf.bytesize} bytes"
