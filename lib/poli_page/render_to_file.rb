# frozen_string_literal: true

require "fileutils"
require "pathname"

module PoliPage
  class Client
    # Render a PDF and stream the bytes straight to `path`. Built on
    # `render.pdf_stream`, so memory usage stays bounded regardless of
    # document size. Creates parent directories if missing. Overwrites
    # existing files (sdk-ruby-plan.md §11).
    #
    # @param path   [String, Pathname]
    # @param kwargs forwarded to `Resources::Render#pdf_stream`
    # @return       [nil]
    # @raise        [PoliPage::InvalidOptionsError] on filesystem failure
    # @raise        any error raised by `Resources::Render#pdf_stream`
    def render_to_file(path, **kwargs)
      pathname = Pathname(path)
      FileUtils.mkdir_p(pathname.dirname) unless pathname.dirname.directory?

      stream_to_path(pathname, kwargs)
      nil
    rescue Errno::EACCES, Errno::ENOSPC, Errno::EISDIR, Errno::ENOENT, Errno::EROFS => e
      raise PoliPage::InvalidOptionsError,
            "failed to write to #{pathname}: #{e.class}: #{e.message}"
    end

    private

    def stream_to_path(pathname, kwargs)
      File.open(pathname, "wb") do |io|
        render.pdf_stream(**kwargs) { |chunk| io.write(chunk) }
      end
    rescue StandardError
      # Clean up the partial / empty file so the caller can see the failure
      # cleanly. Mirrors Node `fs.createWriteStream` cleanup behaviour.
      FileUtils.rm_f(pathname)
      raise
    end
  end
end
