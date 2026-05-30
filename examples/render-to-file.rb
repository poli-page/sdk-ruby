# frozen_string_literal: true

# Demonstrates: client.render_to_file — stream a rendered PDF straight to
# disk with bounded memory. Parent directories are created automatically;
# the partial file is removed on render error.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

client.render_to_file(
  "invoices/INV-001.pdf",
  project:  "billing",
  template: "invoice",
  data:     { invoice_number: "INV-001", total: 1280 }
)

puts "wrote invoices/INV-001.pdf"
