# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"

module PoliPage
  class Client
    # Render a PDF and stream the bytes to `path`. Built on
    # `render.pdf_stream`, so memory usage stays bounded regardless of
    # document size. Creates parent directories if missing, and replaces an
    # existing file.
    #
    # The PDF is written to a temporary file in the target's directory, which
    # is renamed over `path` only once the whole PDF is in. When anything
    # fails (the render, the download or the write), `path` is left as it
    # was: an existing file keeps its content, a missing one is not created.
    # The directory and the temporary file are prepared before the render,
    # so a path that cannot be written costs no render. When `path` is a
    # symbolic link, the PDF goes to the file it points to, and the link
    # stays a link.
    #
    # @param path   [String, Pathname]
    # @param kwargs forwarded to `Resources::Render#pdf_stream`
    # @return       [nil]
    # @raise        [PoliPage::FileWriteError] `io_error` when the file cannot be written (creating a
    #   parent directory, opening, writing or moving it into place): message
    #   `Failed to write PDF: <reason>`, the Ruby error as `cause`, no status, never retried
    # @raise        any error raised by `Resources::Render#pdf_stream`
    #
    # @example Write a PDF to disk
    #   client.render_to_file(
    #     "out/welcome.pdf",
    #     project:  "getting-started",
    #     template: "welcome",
    #     data:     { name: "World" }
    #   )
    def render_to_file(path, **kwargs)
      target = file_write { resolve_links(Pathname(path)) }
      temp = open_temp_file(target)
      begin
        render.pdf_stream(**kwargs) { |chunk| file_write { temp.write(chunk) } }
        file_write { move_into_place(temp, target) }
      ensure
        discard_temp_file(temp)
      end
      nil
    end

    # Errors of the file system: `Errno::*` and Ruby's own `IOError`.
    FILE_WRITE_ERRORS = [SystemCallError, ::IOError].freeze
    private_constant :FILE_WRITE_ERRORS

    private

    def file_write
      yield
    rescue *FILE_WRITE_ERRORS => e
      raise PoliPage::FileWriteError.new(cause: e)
    end

    # Most links the file system follows in one path (Linux's limit).
    MAX_LINKS = 40
    private_constant :MAX_LINKS

    # The file `path` names once its symbolic links are followed, so the
    # rename replaces that file, not the link. An existing file is its real
    # path. A link whose target does not exist yet resolves, hop by hop, to
    # that target, which the rename then creates: each relative link is read
    # against the real directory of the link, as the file system does, so a
    # `..` after a linked directory leaves the directory the link points to.
    def resolve_links(path)
      return Pathname(File.realpath(path)) if path.exist?

      current = path.to_s
      MAX_LINKS.times do
        return Pathname(current) unless File.symlink?(current)

        link = File.readlink(current)
        current = File.absolute_path?(link) ? link : File.join(File.realpath(File.dirname(current)), link)
      end
      raise Errno::ELOOP, path.to_s
    end

    # The temporary file sits next to the target, so the final rename stays
    # on one file system and replaces the target in one step.
    # A target that exists but cannot be written fails here, before any
    # render, as opening it for writing would: the rename could replace it
    # even so.
    def open_temp_file(target)
      file_write do
        raise Errno::EISDIR, target.to_s if target.directory?
        raise Errno::EACCES, target.to_s if target.exist? && !target.writable?

        FileUtils.mkdir_p(target.dirname)
        Tempfile.create([".#{target.basename}.", ".part"], target.dirname.to_s, binmode: true)
      end
    end

    def move_into_place(temp, target)
      temp.close
      File.chmod(target_mode(target), temp.path)
      File.rename(temp.path, target.to_s)
    end

    # The mode the file would get from a plain `File.open(path, "wb")`: an
    # existing file keeps its own, a new one gets the umask's default (the
    # temporary file is created owner-only).
    def target_mode(target)
      target.file? ? target.stat.mode & 0o7777 : 0o666 & ~File.umask
    end

    # Removes the temporary file, if still there. A failure to close it must
    # not hide the outcome of the call, so it is ignored.
    def discard_temp_file(temp)
      begin
        temp.close unless temp.closed?
      rescue *FILE_WRITE_ERRORS
        nil
      end
      FileUtils.rm_f(temp.path)
    end
  end
end
