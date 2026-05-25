# frozen_string_literal: true

require_relative "models/preview_result"
require_relative "models/document_descriptor"

module PoliPage
  module Resources
    # `client.render` namespace. Each method captures a back-reference to the
    # parent `PoliPage::Client` and delegates HTTP execution through it
    # (sdk-ruby-plan.md §3.1).
    class Render
      def initialize(client)
        @client = client
      end

      # POST /v1/render/preview — render and return the HTML, total page
      # count, and the environment ("sandbox" / "live") inferred from the
      # API key. Accepts both project mode and inline mode (the only render-*
      # method that does).
      #
      # @param template        [String]  template slug (project mode) OR raw HTML (inline mode)
      # @param data            [Hash]    template data
      # @param project         [String, nil] project slug; required for project mode
      # @param version         [String, nil] exact semver (e.g. "1.0.0") or "draft"
      # @param format          [String, nil] one of `PoliPage::PageFormat::FORMATS`; default A4
      # @param orientation     [String, nil] "portrait" or "landscape"; default portrait
      # @param locale          [String, nil] BCP 47 (e.g. "en-US")
      # @param metadata        [Hash, nil]   primitive-valued metadata echoed on render.document responses
      # @param idempotency_key [String, nil] caller-supplied UUID; auto-generated if nil
      # @return [PoliPage::PreviewResult]
      # @raise  [PoliPage::ValidationError] on 400
      # @raise  [PoliPage::AuthenticationError] on 401
      #
      # @example Project mode
      #   result = client.render.preview(
      #     project: "billing", template: "invoice", version: "1.0.0",
      #     data:    { invoice_number: "INV-001" }
      #   )
      #   puts result.html
      #   puts "#{result.total_pages} page(s) in #{result.environment} mode"
      #
      # @example Inline mode (raw HTML; only render.preview accepts this)
      #   result = client.render.preview(
      #     template: "<h1>Hello {{ name }}</h1>",
      #     data:     { name: "World" }
      #   )
      def preview(template:, data:, project: nil, version: nil, format: nil,
                  orientation: nil, locale: nil, metadata: nil,
                  idempotency_key: nil)
        validate_render_kwargs!(format: format, orientation: orientation)
        body = { project: project, template: template, data: data, version: version,
                 format: format, orientation: orientation, locale: locale, metadata: metadata }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER_PREVIEW,
                                      body: body, idempotency_key: idempotency_key)
        PoliPage::PreviewResult.new(**parsed)
      end

      # POST /v1/render — render and store the document, returning a
      # `PoliPage::DocumentDescriptor` with the client back-reference attached
      # so that `#download_pdf` works. Project mode only.
      #
      # @return [PoliPage::DocumentDescriptor]
      #
      # @example
      #   doc = client.render.document(
      #     project:  "billing",
      #     template: "invoice",
      #     version:  "1.0.0",
      #     data:     { invoice_number: "INV-001" },
      #     metadata: { customer_id: "cust_123" }   # echoed on the descriptor
      #   )
      #   db.invoices.update(id: "INV-001", document_id: doc.document_id)
      #   pdf = doc.download_pdf
      def document(project:, template:, data:, version: nil, format: nil,
                   orientation: nil, locale: nil, metadata: nil,
                   idempotency_key: nil)
        validate_render_kwargs!(format: format, orientation: orientation)
        body = { project: project, template: template, data: data, version: version,
                 format: format, orientation: orientation, locale: locale, metadata: metadata }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER,
                                      body: body, idempotency_key: idempotency_key)
        parsed[:metadata] ||= {}
        PoliPage::DocumentDescriptor.new(**parsed, _client: @client)
      end

      # Two-hop: render the document, then fetch the presigned PDF URL and
      # return the raw bytes (binary-encoded String). The presigned fetch
      # is unauthenticated and NOT subject to the retry policy.
      #
      # @return [String] raw PDF bytes
      # @raise  [PoliPage::DownloadError] on second-hop failure
      #
      # @example
      #   pdf = client.render.pdf(
      #     project: "billing", template: "invoice", version: "1.0.0",
      #     data:    { invoice_number: "INV-001" }
      #   )
      #   File.binwrite("invoice.pdf", pdf)
      def pdf(project:, template:, data:, version: nil, format: nil,
              orientation: nil, locale: nil, metadata: nil, idempotency_key: nil)
        desc = document(project: project, template: template, data: data,
                        version: version, format: format, orientation: orientation,
                        locale: locale, metadata: metadata, idempotency_key: idempotency_key)
        desc.download_pdf
      end

      # Streaming form of `#pdf`. With a block, yields raw chunks (binary
      # bytes) as they arrive. Without a block, returns an `Enumerator` so
      # the caller can `.each`, `.first(n)`, pipe into `Enumerable` chains,
      # etc.
      #
      # @yieldparam chunk [String] raw bytes
      # @return           [Enumerator, nil]
      # @raise            [PoliPage::DownloadError]
      #
      # @example Block form — pipe straight to a file
      #   File.open("invoice.pdf", "wb") do |io|
      #     client.render.pdf_stream(
      #       project: "billing", template: "invoice", version: "1.0.0", data: data
      #     ) { |chunk| io.write(chunk) }
      #   end
      #
      # @example Enumerator form
      #   enum = client.render.pdf_stream(
      #     project: "billing", template: "invoice", version: "1.0.0", data: data
      #   )
      #   total = enum.sum(&:bytesize)
      def pdf_stream(project:, template:, data:, version: nil, format: nil,
                     orientation: nil, locale: nil, metadata: nil, idempotency_key: nil, &block)
        unless block
          return Enumerator.new do |yielder|
            pdf_stream(project: project, template: template, data: data,
                       version: version, format: format, orientation: orientation,
                       locale: locale, metadata: metadata,
                       idempotency_key: idempotency_key) { |chunk| yielder << chunk }
          end
        end

        desc = document(project: project, template: template, data: data,
                        version: version, format: format, orientation: orientation,
                        locale: locale, metadata: metadata, idempotency_key: idempotency_key)
        @client.stream_bytes(desc.presigned_pdf_url, &block)
      end

      private

      # Local arg validation — fail fast with a clear `InvalidOptionsError`
      # before issuing the HTTP request. The deployed API rejects these too,
      # but raising client-side saves a round-trip and surfaces a friendlier
      # error message (sdk-ruby-plan.md §9.1).
      def validate_render_kwargs!(format:, orientation:)
        if format && !PoliPage::PageFormat.valid?(format)
          raise PoliPage::InvalidOptionsError,
                "invalid format: #{format.inspect}; expected one of #{PoliPage::PageFormat::FORMATS.to_a}"
        end
        return unless orientation && !PoliPage::Orientation.valid?(orientation)

        raise PoliPage::InvalidOptionsError,
              "invalid orientation: #{orientation.inspect}; expected 'portrait' or 'landscape'"
      end
    end
  end
end
