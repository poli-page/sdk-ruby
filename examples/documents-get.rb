# frozen_string_literal: true

# Demonstrates: client.documents.get — re-fetch a stored document by id.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

doc = client.documents.get("doc_INV-001")

puts "document #{doc.document_id} created at #{doc.created_at}"
puts "#{doc.page_count} page(s), format=#{doc.format}, environment=#{doc.environment}"

# The descriptor carries a fresh presigned URL — call `#download_pdf` to
# fetch the bytes if you need them.
File.binwrite("invoice.pdf", doc.download_pdf)
