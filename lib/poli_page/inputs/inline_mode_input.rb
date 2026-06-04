# frozen_string_literal: true

module PoliPage
  # Convenience value-object form of the inline-mode render input. Inline
  # mode is only accepted by `client.render.preview` (sdk-ruby-plan.md §13
  # Phase 2); the render-to-document methods require project mode.
  InlineModeInput = Data.define(
    :template,
    :data,
    :format,
    :orientation,
    :locale,
    :metadata,
    :idempotency_key
  ) do
    def to_h
      super.compact
    end
  end

  class << InlineModeInput
    alias _strict_new new

    def new(template:, data:, format: nil, orientation: nil, locale: nil,
            metadata: nil, idempotency_key: nil)
      _strict_new(template: template, data: data, format: format,
                  orientation: orientation, locale: locale, metadata: metadata,
                  idempotency_key: idempotency_key)
    end
  end
end
