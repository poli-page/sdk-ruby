# frozen_string_literal: true

# Demonstrates: client.render.preview — render and return HTML + page count.
# The only render-* method that accepts both project mode and inline mode.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

# Project mode — render a stored template to HTML.
result = client.render.preview(
  project:  "billing",
  template: "invoice",
  data:     { invoice_number: "INV-001", total: 1280 }
)

puts "#{result.total_pages} page(s) in #{result.environment} mode"
puts "HTML length: #{result.html.length} chars"

# Inline mode — pass raw HTML directly. Useful for debugging template data
# without engaging the PDF pipeline.
greeting = client.render.preview(
  template: "<h1>Hello {{ name }}</h1>",
  data:     { name: "World" }
)
puts greeting.html
