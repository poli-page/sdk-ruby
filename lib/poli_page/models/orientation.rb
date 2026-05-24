# frozen_string_literal: true

module PoliPage
  # Valid `orientation:` strings for the rendering endpoints
  # (sdk-specification.md §4.1).
  module Orientation
    ORIENTATIONS = Set["portrait", "landscape"].freeze

    module_function

    def valid?(value)
      ORIENTATIONS.include?(value)
    end
  end
end
