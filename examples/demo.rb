#!/usr/bin/env ruby
# frozen_string_literal: true

# poli-page — Ruby SDK end-to-end demo.
#
# Run:  ruby examples/demo.rb
#       POLI_PAGE_API_KEY=pp_test_... ruby examples/demo.rb
#
# Walks through every public method of the SDK and writes the results to
# `examples/output/`. Uses the `getting-started/welcome/1.0.0` template
# that's auto-provisioned in every Poli Page org, so this works out of
# the box with any fresh API key — no project setup needed.
#
# Order matches sdk-ruby-plan.md §13 Phase 5: render.pdf → render.pdf_stream
# → render_to_file → render.preview → render.document → documents.get →
# documents.thumbnails → documents.preview → documents.delete → intentional
# error path.

require "logger"
require_relative "../lib/poli_page"
require_relative "shared"

OUT_DIR = File.join(__dir__, "output")
FileUtils.mkdir_p(OUT_DIR)

api_key  = Demo.ensure_api_key
base_url = Demo.resolve_base_url

# Single client, reused across every call. Hooks observe HTTP traffic without
# coupling to a logging library — they never block or change request behaviour.
client = PoliPage::Client.new(
  api_key:  api_key,
  base_url: base_url,
  on_retry: ->(event) {
    puts Demo.yellow("  ↻") + Demo.dim("  retry attempt #{event.attempt} after #{event.delay.round(3)}s: #{event.reason.code}")
  },
  on_error: ->(err) {
    puts Demo.red("  ✗") + Demo.dim("  terminal error: #{err.class}: #{err.code}")
  }
)

PROJECT_INPUT = {
  project:  "getting-started",
  template: "welcome",
  version:  "1.0.0",
  data:     { name: "Ruby SDK Demo" }
}.freeze

TOTAL_STEPS = 10

# 1. render.pdf — fetch PDF bytes into memory ────────────────────────────────
Demo.step(1, TOTAL_STEPS, "render.pdf() — PDF bytes in memory")
pdf = client.render.pdf(**PROJECT_INPUT)
render_path = File.join(OUT_DIR, "render.pdf")
File.binwrite(render_path, pdf)
puts "  #{pdf.bytesize} bytes, magic: #{Demo.bold(pdf[0, 4])}"
puts "  #{Demo.dim("open:")} #{Demo.file_link(render_path)}"

# 2. render.pdf_stream — stream chunks to a sink ─────────────────────────────
Demo.step(2, TOTAL_STEPS, "render.pdf_stream() — stream chunks (block form)")
stream_path = File.join(OUT_DIR, "stream.pdf")
total = 0
File.open(stream_path, "wb") do |io|
  client.render.pdf_stream(**PROJECT_INPUT) do |chunk|
    io.write(chunk)
    total += chunk.bytesize
  end
end
puts "  #{total} bytes streamed"
puts "  #{Demo.dim("open:")} #{Demo.file_link(stream_path)}"

# 3. render_to_file — convenience helper ────────────────────────────────────
Demo.step(3, TOTAL_STEPS, "render_to_file() — render straight to disk")
file_path = File.join(OUT_DIR, "file.pdf")
client.render_to_file(file_path, **PROJECT_INPUT)
puts "  wrote #{file_path}"
puts "  #{Demo.dim("open:")} #{Demo.file_link(file_path)}"

# 4. render.preview — rendered HTML + page count + environment ───────────────
Demo.step(4, TOTAL_STEPS, "render.preview() — rendered HTML + total_pages + environment")
preview = client.render.preview(**PROJECT_INPUT)
preview_path = File.join(OUT_DIR, "render-preview.html")
File.write(preview_path, preview.html)
puts "  #{Demo.bold(preview.total_pages)} page(s), env=#{Demo.bold(preview.environment)}, #{preview.html.length} chars"
puts "  #{Demo.dim("open:")} #{Demo.file_link(preview_path)}"

# 5. render.document — render + store, returning the descriptor ──────────────
Demo.step(5, TOTAL_STEPS, "render.document() — store the document, return the descriptor")
doc = client.render.document(**PROJECT_INPUT)
puts "  #{Demo.dim("documentId:")} #{Demo.bold(doc.document_id)}"
puts "  #{Demo.dim("pageCount:")}  #{doc.page_count}"

# 6. documents.get — re-fetch the descriptor by id ──────────────────────────
Demo.step(6, TOTAL_STEPS, "documents.get(id) — re-fetch the descriptor")
fetched = client.documents.get(doc.document_id)
puts "  #{Demo.dim("documentId matches:")} #{fetched.document_id == doc.document_id}"

# 7. documents.thumbnails — page thumbnails (Starter+ tier) ─────────────────
Demo.step(7, TOTAL_STEPS, "documents.thumbnails(id) — page thumbnails (Starter+ tier)")
begin
  thumbs = client.documents.thumbnails(doc.document_id, width: 320)
  puts "  #{thumbs.size} thumbnail(s), first page #{Demo.bold(thumbs.first.page)} (#{thumbs.first.width}x#{thumbs.first.height}, #{thumbs.first.content_type})"
rescue PoliPage::PermissionDeniedError, PoliPage::APIError => e
  # Free tier returns 403 / 402 for thumbnails. Demo continues.
  puts "  #{Demo.dim("skipped (#{e.code}, status #{e.status}) — Starter+ tier feature")}"
end

# 8. documents.preview — stored document HTML (no engine work) ──────────────
Demo.step(8, TOTAL_STEPS, "documents.preview(id) — stored document HTML (no engine work)")
stored_preview = client.documents.preview(doc.document_id)
stored_path = File.join(OUT_DIR, "documents-preview.html")
File.write(stored_path, stored_preview.html)
puts "  #{Demo.bold(stored_preview.page_count)} page(s), #{stored_preview.html.length} chars"
puts "  #{Demo.dim("open:")} #{Demo.file_link(stored_path)}"

# 9. documents.delete — soft-delete the document ────────────────────────────
Demo.step(9, TOTAL_STEPS, "documents.delete(id) — soft-delete the document")
client.documents.delete(doc.document_id)
puts "  #{Demo.green("✔")} deleted #{Demo.bold(doc.document_id)}"

# 10. Error handling — DELIBERATELY trigger a 400 and inspect the result ────
Demo.step(10, TOTAL_STEPS, "error handling — DEMO ONLY (we trigger an error on purpose)")
puts Demo.yellow("  ⚠  This step is intentional — the SDK is about to raise, but the")
puts Demo.yellow("     demo will rescue and inspect it. ") + Demo.bold("The demo is NOT crashing.")
puts Demo.dim("     (We send version=banana, expecting the API to return 400 INVALID_VERSION_FORMAT.)")
puts
begin
  client.render.pdf(project: "getting-started", template: "welcome", version: "banana", data: {})
  puts "  #{Demo.red("✗ unexpected: the call succeeded but should have failed")}"
rescue PoliPage::AuthenticationError, PoliPage::PermissionDeniedError => e
  puts "  #{Demo.green("✔")} Auth/permission error caught: #{e.code} (status #{e.status})"
  puts "     request_id=#{e.request_id.inspect}  auth_error?=#{e.auth_error?}  retryable?=#{e.retryable?}"
rescue PoliPage::Error => e
  puts "  #{Demo.green("✔")} Error caught successfully. PoliPage::Error exposed:"
  puts "     code:           #{e.code}"
  puts "     status:         #{e.status}"
  puts "     request_id:     #{e.request_id.inspect}"
  puts "     class:          #{e.class}"
  puts "     auth_error?     #{e.auth_error?}"
  puts "     validation_error? #{e.validation_error?}"
  puts "     retryable?      #{e.retryable?}"
end

puts
puts "#{Demo.green("✔")} #{Demo.bold("All steps completed.")} Inspect output in #{Demo.file_link(OUT_DIR)}"
puts
