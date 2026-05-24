# frozen_string_literal: true

require_relative "models/preview_result"

module PoliPage
  module Resources
    # `client.render` namespace. Each method captures a back-reference to the
    # parent `PoliPage::Client` and delegates HTTP execution through it
    # (sdk-ruby-plan.md §3.1).
    #
    # In Phase 2, only `#preview` is implemented; `pdf`, `pdf_stream`, and
    # `document` land in Phase 3.
    class Render
      def initialize(client)
        @client = client
      end

      # POST /v1/render/preview — returns the rendered HTML, total page count,
      # and the environment ("sandbox" / "live") inferred from the API key.
      #
      # Accepts both project mode (`project:` + `template:` slugs) and inline
      # mode (`template:` as raw HTML string). Inline mode is the only one
      # the preview endpoint supports beyond project mode.
      #
      # @return [PoliPage::PreviewResult]
      def preview(template:, data:, project: nil, version: nil, format: nil,
                  orientation: nil, locale: nil, metadata: nil,
                  idempotency_key: nil)
        body = { project: project, template: template, data: data, version: version,
                 format: format, orientation: orientation, locale: locale, metadata: metadata }.compact
        parsed = @client.execute_post(Internal::Constants::PATH_RENDER_PREVIEW,
                                      body: body, idempotency_key: idempotency_key)
        PoliPage::PreviewResult.new(**parsed)
      end
    end
  end
end
