# frozen_string_literal: true

module PoliPage
  # Convenience value-object form of the project-mode render input. Methods
  # accept bare kwargs directly; this wrapper is for callers who want
  # `Data.define`'s equality, frozen-by-default semantics, and a single
  # marshallable type to thread through their own code.
  ProjectModeInput = Data.define(
    :project,
    :template,
    :data,
    :version,
    :format,
    :orientation,
    :locale,
    :metadata,
    :idempotency_key
  ) do
    # @return [Hash] kwargs ready to splat into the matching `client.render.*` method
    def to_h
      super.compact
    end
  end

  # Allow positional-as-keyword construction with optional fields defaulted to nil
  # — Data.define is strict by default. We re-open the class only to add a
  # forgiving constructor that lets callers omit the optional knobs.
  class << ProjectModeInput
    alias _strict_new new

    def new(project:, template:, data:, version: nil, format: nil,
            orientation: nil, locale: nil, metadata: nil, idempotency_key: nil)
      _strict_new(project: project, template: template, data: data,
                  version: version, format: format, orientation: orientation,
                  locale: locale, metadata: metadata, idempotency_key: idempotency_key)
    end
  end
end
