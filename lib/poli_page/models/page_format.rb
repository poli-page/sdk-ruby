# frozen_string_literal: true

module PoliPage
  # Valid `format:` strings for the rendering endpoints (sdk-specification.md
  # §4.1). Ruby has no native enum; a frozen Set of strings is the most
  # idiomatic representation and matches the wire format directly. The set
  # is used both for input validation (in resource methods) and for
  # documentation.
  module PageFormat
    FORMATS = Set[
      "A3", "A4", "A5", "A6",
      "Letter", "Legal", "Tabloid",
      "Executive", "B4", "B5",
      "Statement", "Folio"
    ].freeze

    module_function

    def valid?(value)
      FORMATS.include?(value)
    end
  end
end
