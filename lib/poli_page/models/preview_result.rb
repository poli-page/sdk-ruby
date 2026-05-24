# frozen_string_literal: true

module PoliPage
  # Return value of `client.render.preview`. The HTML is the rendered output;
  # `total_pages` is the page count the rendering engine reports;
  # `environment` is either `"sandbox"` or `"live"` and reflects the key the
  # request was made with.
  PreviewResult = Data.define(:html, :total_pages, :environment)
end
