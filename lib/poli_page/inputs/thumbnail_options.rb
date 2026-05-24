# frozen_string_literal: true

module PoliPage
  # Convenience value-object form of the `client.documents.thumbnails`
  # options hash. Methods accept bare kwargs directly; this wrapper is for
  # callers who want `Data.define`'s equality + frozen-by-default semantics.
  #
  # - `width`   [Integer]                   thumbnail width in pixels (required)
  # - `format`  ["png", "jpeg", nil]        output format; default "png"
  # - `quality` [Integer, nil]              JPEG quality 1-100; only valid when format is "jpeg"
  # - `pages`   [Array<Integer>, nil]       1-based page indices to render; nil means all pages
  ThumbnailOptions = Data.define(:width, :format, :quality, :pages) do
    def to_h
      super.compact
    end
  end

  class << ThumbnailOptions
    alias _strict_new new

    def new(width:, format: nil, quality: nil, pages: nil)
      _strict_new(width: width, format: format, quality: quality, pages: pages)
    end
  end
end
