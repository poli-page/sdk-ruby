# frozen_string_literal: true

module PoliPage
  module Internal
    # @api private
    #
    # snake_case ↔ camelCase translator (sdk-ruby-plan.md §5.4). Pure, no
    # runtime dependency on metaprogramming DSLs. Outgoing: hash keys are
    # stringified and camelized. Incoming: hash keys are snake_cased and
    # symbolized.
    module Wire
      module_function

      def to_wire(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), h|
            h[snake_to_camel(k.to_s)] = to_wire(v)
          end
        when Array
          value.map { |v| to_wire(v) }
        else
          value
        end
      end

      def from_wire(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), h|
            h[camel_to_snake(k.to_s).to_sym] = from_wire(v)
          end
        when Array
          value.map { |v| from_wire(v) }
        else
          value
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
