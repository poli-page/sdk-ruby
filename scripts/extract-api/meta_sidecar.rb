# frozen_string_literal: true

require "time"

module MetaSidecar
  module_function

  def build(gem_version)
    {
      language: "ruby",
      package:  { kind: "rubygems", name: "poli-page", version: gem_version },
      extractedAt: Time.now.utc.iso8601,
      extractorVersion: "0.1.0",
      client: { name: "PoliPage::Client", kind: "class" },
      methods: [
        { slug: "render-pdf",           name: "client.render.pdf" },
        { slug: "render-pdf-stream",    name: "client.render.pdf_stream" },
        { slug: "render-preview",       name: "client.render.preview" },
        { slug: "render-document",      name: "client.render.document" },
        { slug: "documents-get",        name: "client.documents.get" },
        { slug: "documents-preview",    name: "client.documents.preview" },
        { slug: "documents-thumbnails", name: "client.documents.thumbnails" },
        { slug: "documents-delete",     name: "client.documents.delete" },
        { slug: "render-to-file",       name: "client.render_to_file" }
      ],
      errors: [
        "PoliPage::Error", "PoliPage::ValidationError", "PoliPage::AuthenticationError",
        "PoliPage::PermissionDeniedError", "PoliPage::NotFoundError", "PoliPage::GoneError",
        "PoliPage::RateLimitError", "PoliPage::APIError",
        "PoliPage::InvalidOptionsError", "PoliPage::ConnectionError",
        "PoliPage::TimeoutError", "PoliPage::DownloadError", "PoliPage::InternalError"
      ].map { |c| { code: c } }
    }
  end
end
