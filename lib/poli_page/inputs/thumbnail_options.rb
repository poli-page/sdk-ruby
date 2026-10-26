# frozen_string_literal: true

module PoliPage
  # Convenience value-object form of the `client.documents.thumbnails`
  # options hash. Methods accept bare kwargs directly; this wrapper is for
  # callers who want `Data.define`'s equality + frozen-by-default semantics.
  #
  # Every option is optional; a nil option is not sent and the API default
  # applies. The API checks the bounds (`400 VALIDATION_ERROR`).
  #
  # - `width`   [Integer, nil]              thumbnail width in pixels, 50-2000; API default 400
  # - `format`  ["jpeg", "webp", "png", nil] output format; API default "jpeg"
  # - `quality` [Integer, nil]              JPEG quality 1-100; only valid when format is "jpeg"
  # - `pages`   [Array<Integer>, nil]       1-based page numbers to render; nil means all pages
  ThumbnailOptions = Data.define(:width, :format, :quality, :pages) do
    def to_h
      super.compact
    end
  end

  class << ThumbnailOptions
    alias _strict_new new

    def new(width: nil, format: nil, quality: nil, pages: nil)
      _strict_new(width: width, format: format, quality: quality, pages: pages)
    end
  end
end
