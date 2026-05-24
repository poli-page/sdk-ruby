# frozen_string_literal: true

module PoliPage
  # A single page thumbnail returned by `client.documents.thumbnails`.
  # `data` is base64-encoded image bytes; decode with `Base64.decode64(data)`
  # (stdlib).
  Thumbnail = Data.define(:page, :width, :height, :content_type, :data)
end
