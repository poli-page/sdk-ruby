# frozen_string_literal: true

# Demonstrates: PoliPage::Client.new — the single entry point.
require "poli_page"

client = PoliPage::Client.new(
  api_key:     ENV.fetch("POLI_PAGE_API_KEY"),
  timeout:     60,
  max_retries: 2
)

# The same `client` instance is reused for every render and document call.
# Configuration is immutable after `#initialize`; the client is thread-safe.
client
