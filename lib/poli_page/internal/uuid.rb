# frozen_string_literal: true

require "securerandom"

module PoliPage
  module Internal
    # @api private
    #
    # Thin wrapper over `SecureRandom.uuid`. Indirection exists so a future
    # swap (e.g. UUIDv7 once the stdlib lands `SecureRandom.uuid_v7`) is a
    # one-file change (sdk-ruby-plan.md §13 Phase 1).
    module UUID
      module_function

      def generate
        SecureRandom.uuid
      end
    end
  end
end
