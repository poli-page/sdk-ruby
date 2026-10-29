# frozen_string_literal: true

module PoliPage
  module Internal
    # @api private
    #
    # snake_case ↔ camelCase translator for the SDK's own field names
    # (sdk-ruby-plan.md §5.4, sdk-specification.md §2). Pure, no runtime
    # dependency on metaprogramming DSLs. Outgoing: hash keys are stringified
    # and camelized. Incoming: hash keys are snake_cased and symbolized.
    #
    # The caller's payloads are not the SDK's to rename: the value of a
    # top-level key listed in {PAYLOAD_KEYS} (`data`, `metadata`) passes
    # through untouched both ways, so `metadata` is sent as is and returned
    # exactly as the API stored it (sdk-specification.md §5.3), and `data`
    # reaches the template with the keys the caller wrote.
    module Wire
      # Top-level keys whose values are the caller's own JSON, never renamed.
      PAYLOAD_KEYS = %w[data metadata].freeze

      module_function

      # @param verbatim [Array<String>] top-level keys (wire spelling) whose
      #   values are copied unchanged
      def to_wire(value, verbatim = [])
        return value.map { |v| to_wire(v) } if value.is_a?(Array)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(k, v), h|
          key = snake_to_camel(k.to_s)
          h[key] = verbatim.include?(key) ? v : to_wire(v)
        end
      end

      # @param verbatim [Array<String>] top-level keys (wire spelling) whose
      #   values are copied unchanged
      def from_wire(value, verbatim = [])
        return value.map { |v| from_wire(v) } if value.is_a?(Array)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(k, v), h|
          h[camel_to_snake(k.to_s).to_sym] = verbatim.include?(k.to_s) ? v : from_wire(v)
        end
      end

      def snake_to_camel(str)
        str.gsub(/_([a-z])/) { Regexp.last_match(1).upcase }
      end

      def camel_to_snake(str)
        str.gsub(/([A-Z])/, '_\1').downcase
      end
    end
  end
end
