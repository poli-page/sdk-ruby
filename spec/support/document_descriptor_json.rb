# frozen_string_literal: true

require "json"

# Wire-shape (camelCase) `DocumentDescriptor` body as `POST /v1/render` and
# `GET /v1/documents/:id` return it. Pass overrides to change single fields.
module DocumentDescriptorJSON
  FIELDS = {
    documentId: "doc_abc123", organizationId: "org_xyz",
    projectId: "proj_42", projectSlug: "billing",
    templateId: "tpl_invoice_v1", templateSlug: "invoice",
    environment: "live", apiKeyId: "key_live_abc",
    format: "A4", orientation: "portrait", locale: "en-US",
    pageCount: 2, sizeBytes: 38_421,
    createdAt: "2026-04-30T19:45:22Z", metadata: {},
    expiresAt: "2026-04-30T20:00:22Z",
    presignedPdfUrl: "https://s3.example/presigned/x.pdf"
  }.freeze

  module_function

  def build(**overrides)
    JSON.generate(FIELDS.merge(overrides))
  end
end
