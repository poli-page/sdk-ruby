# frozen_string_literal: true

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

      # POST /v1/render — render and store the document, returning a
      # `PoliPage::DocumentDescriptor` with the client back-reference attached
      # so that `#download_pdf` works. The API renders the project's copy
      # published in the API key's environment; the SDK never sends an
      # environment. The request body holds only the seven render fields
      # (`project`, `template`, `data`, `metadata`, `format`, `orientation`,
      # `locale`); unset optional fields are omitted.
      #
      # @param project         [String]      project slug
      # @param template        [String]      template slug inside the project
      # @param data            [Hash]        template data
      # @param format          [String, nil] one of `PoliPage::PageFormat::FORMATS`; API default when nil
      # @param orientation     [String, nil] "portrait" or "landscape"; API default when nil
      # @param locale          [String, nil] BCP 47 (e.g. "en-US")
      # @param metadata        [Hash, nil]   primitive-valued metadata echoed on the descriptor
      # @param idempotency_key [String, nil] caller-supplied UUID; auto-generated if nil
      # @return [PoliPage::DocumentDescriptor]
      # @raise  [PoliPage::InvalidOptionsError] `PROJECT_REQUIRED_FOR_DOCUMENT` when `project` is nil or empty
      # @raise  [PoliPage::ValidationError] on 400
      # @raise  [PoliPage::NotFoundError]   on 404 (e.g. `TEMPLATE_NOT_FOUND`, `PROJECT_NOT_IN_ENVIRONMENT`)
      #
      # @example
      #   doc = client.render.document(
      #     project:  "billing",
      #     template: "invoice",
      #     data:     { invoice_number: "INV-001" },
      #     metadata: { customer_id: "cust_123" }   # echoed on the descriptor
      #   )
      #   db.invoices.update(id: "INV-001", document_id: doc.document_id)
      #   pdf = doc.download_pdf
      def document(project:, template:, data:, format: nil, orientation: nil,
                   locale: nil, metadata: nil, idempotency_key: nil)
        validate_render_kwargs!(project: project, format: format, orientation: orientation)
        body = { project: project, template: template, data: data, metadata: metadata,
                 format: format, orientation: orientation, locale: locale }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER,
                                      body: body, idempotency_key: idempotency_key)
        PoliPage::DocumentDescriptor.from_wire(parsed, client: @client)
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
      #     project: "billing", template: "invoice",
      #     data:    { invoice_number: "INV-001" }
      #   )
      #   File.binwrite("invoice.pdf", pdf)
      def pdf(project:, template:, data:, format: nil, orientation: nil,
              locale: nil, metadata: nil, idempotency_key: nil)
        desc = document(project: project, template: template, data: data,
                        format: format, orientation: orientation,
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
      #       project: "billing", template: "invoice", data: data
      #     ) { |chunk| io.write(chunk) }
      #   end
      #
      # @example Enumerator form
      #   enum = client.render.pdf_stream(
      #     project: "billing", template: "invoice", data: data
      #   )
      #   total = enum.sum(&:bytesize)
      def pdf_stream(project:, template:, data:, format: nil, orientation: nil,
                     locale: nil, metadata: nil, idempotency_key: nil, &block)
        unless block
          return Enumerator.new do |yielder|
            pdf_stream(project: project, template: template, data: data,
                       format: format, orientation: orientation,
                       locale: locale, metadata: metadata,
                       idempotency_key: idempotency_key) { |chunk| yielder << chunk }
          end
        end

        desc = document(project: project, template: template, data: data,
                        format: format, orientation: orientation,
                        locale: locale, metadata: metadata, idempotency_key: idempotency_key)
        @client.stream_bytes(desc.presigned_pdf_url, &block)
      end

      private

      # Local arg validation — fail fast with a clear `InvalidOptionsError`
      # before issuing the HTTP request. The deployed API rejects these too,
      # but raising client-side saves a round-trip and surfaces a friendlier
      # error message (sdk-ruby-plan.md §9.1).
      def validate_render_kwargs!(project:, format:, orientation:)
        # Ruby cannot make `project` non-nil in its signature: a missing or
        # empty one raises before any request (sdk-specification.md §5.4).
        if project.nil? || project.to_s.empty?
          raise PoliPage::InvalidOptionsError.new(Internal::Constants::MESSAGE_PROJECT_REQUIRED,
                                                  code: ErrorCodes::PROJECT_REQUIRED_FOR_DOCUMENT)
        end
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
