# frozen_string_literal: true

# Demonstrates: client.documents.delete — soft-delete a stored document.
require "poli_page"

client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))

client.documents.delete("doc_INV-001")

# Returns nil. Re-deleting an already-deleted document raises
# `PoliPage::GoneError` (HTTP 410).
puts "deleted doc_INV-001"
