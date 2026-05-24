# frozen_string_literal: true

# Steep only checks the public surface — the `internal/` namespace is
# convention-private (sdk-ruby-plan.md §3.1) and ships no RBS signatures.
# Adding sigs for internal code would create churn every time we refactor
# the transport core without changing the public contract.
target :lib do
  signature "sig"

  check "lib/poli_page/client.rb"
  check "lib/poli_page/render.rb"
  check "lib/poli_page/documents.rb"
  check "lib/poli_page/render_to_file.rb"
  check "lib/poli_page/errors.rb"
  check "lib/poli_page/retry_event.rb"
  check "lib/poli_page/models"
  check "lib/poli_page/inputs"

  library "json"
  library "uri"
  library "net-http"
  library "openssl"
  library "logger"
  library "securerandom"
  library "fileutils"
  library "pathname"
  library "cgi"
end
