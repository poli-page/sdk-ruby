# frozen_string_literal: true

# Ports sdk-node/tests/node.test.ts. Client#render_to_file streams the PDF
# bytes from `render.pdf_stream` to a temporary file next to the target, and
# renames it over the target once the PDF is complete.

require "fileutils"
require "pathname"
require "tempfile"
require "tmpdir"

RSpec.describe PoliPage::Client, "#render_to_file" do
  let(:client) { described_class.new(api_key: "pp_sandbox_abc", max_retries: 0) }

  let(:descriptor_json) { DocumentDescriptorJSON.build }

  before do
    stub_request(:post, "https://api.poli.page/v1/render").to_return(status: 200, body: descriptor_json)
    stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 200, body: "%PDF-1.4 stub data")
  end

  it "writes the streamed PDF bytes to the given path (String)" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      client.render_to_file(path, project: "billing", template: "invoice", data: {})
      expect(File.binread(path)).to eq("%PDF-1.4 stub data")
    end
  end

  it "accepts a Pathname argument" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("out.pdf")
      client.render_to_file(path, project: "billing", template: "invoice", data: {})
      expect(path.binread).to eq("%PDF-1.4 stub data")
    end
  end

  it "creates parent directories that don't exist" do
    Dir.mktmpdir do |dir|
      nested = File.join(dir, "deeply", "nested", "out.pdf")
      client.render_to_file(nested, project: "billing", template: "invoice", data: {})
      expect(File.exist?(nested)).to be true
    end
  end

  it "overwrites an existing file at the path" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      File.write(path, "previous contents — should be replaced")
      client.render_to_file(path, project: "billing", template: "invoice", data: {})
      expect(File.binread(path)).to eq("%PDF-1.4 stub data")
    end
  end

  it "returns nil on success" do
    Dir.mktmpdir do |dir|
      result = client.render_to_file(File.join(dir, "out.pdf"),
                                     project: "billing", template: "invoice", data: {})
      expect(result).to be_nil
    end
  end

  # POSIX-only: on Windows, '/no-such-root-i-promise/x.pdf' resolves to a
  # drive-relative path on a writable volume (e.g. D:\no-such-root-i-promise\x.pdf
  # on the CI runner), so mkdir_p succeeds and no error is raised.
  it "raises io_error before any render when the path is unwritable", skip: Gem.win_platform? do
    expect do
      client.render_to_file("/no-such-root-i-promise/x.pdf",
                            project: "billing", template: "invoice", data: {})
    end.to raise_error(PoliPage::FileWriteError, /\AFailed to write PDF: /) { |e|
      expect([e.code, e.status, e.request_id, e.retryable?]).to eq(["io_error", nil, nil, false])
      expect(e.cause).to be_a(SystemCallError)
      expect(e.message).to eq("Failed to write PDF: #{e.cause.message}")
    }
    expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
  end

  it "raises io_error before any render when the path is a directory" do
    Dir.mktmpdir do |dir|
      target = File.realpath(dir)
      expect { client.render_to_file(dir, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError, "Failed to write PDF: #{target}: not a regular file") { |e|
          expect([e.code, e.status]).to eq(["io_error", nil])
          expect(e.cause).to be_a(IOError)
        }
      expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
      expect(Dir.children(dir)).to be_empty
    end
  end

  it "raises io_error before any render, and keeps the FIFO, when the path is a FIFO", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      File.mkfifo(path)
      target = File.realpath(path)
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError, "Failed to write PDF: #{target}: not a regular file")
      expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
      expect(File.pipe?(path)).to be true
      expect(Dir.children(dir)).to eq(["out.pdf"])
    end
  end

  it "raises io_error before any render for a link to a directory", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir(File.join(dir, "real"))
      File.symlink("real", File.join(dir, "link.pdf"))
      target = File.realpath(File.join(dir, "real"))
      expect { client.render_to_file(File.join(dir, "link.pdf"), project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError, "Failed to write PDF: #{target}: not a regular file")
      expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
      expect(File.symlink?(File.join(dir, "link.pdf"))).to be true
    end
  end

  it "raises io_error when a parent of the path is a file", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "file"), "x")
      path = File.join(dir, "file", "out.pdf")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError) { |e| expect(e.cause).to be_a(SystemCallError) }
    end
  end

  # A temporary file whose writes fail, as on a full disk.
  def failing_writes
    allow(Tempfile).to receive(:create).and_wrap_original do |create, *args, **kwargs|
      create.call(*args, **kwargs).tap do |file|
        allow(file).to receive(:write).and_raise(Errno::ENOSPC, "while writing the PDF")
      end
    end
  end

  it "raises io_error with the write error as cause, leaving an existing target untouched" do
    failing_writes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      File.write(path, "previous")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError, /\AFailed to write PDF: .* - while writing the PDF\z/) { |e|
          expect(e.cause).to be_a(Errno::ENOSPC)
          expect(e.message).to eq("Failed to write PDF: #{e.cause.message}")
          expect(e.status).to be_nil
        }
      expect(File.read(path)).to eq("previous")
      expect(Dir.children(dir)).to eq(["out.pdf"])
    end
  end

  it "keeps the original error, and removes the temporary file, when closing it fails too" do
    allow(Tempfile).to receive(:create).and_wrap_original do |create, *args, **kwargs|
      create.call(*args, **kwargs).tap do |file|
        allow(file).to receive(:write).and_raise(Errno::ENOSPC, "while writing the PDF")
        allow(file).to receive(:close).and_wrap_original do |close|
          close.call
          raise IOError, "close failed"
        end
      end
    end
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError) { |e| expect(e.cause).to be_a(Errno::ENOSPC) }
      expect(Dir.children(dir)).to be_empty
    end
  end

  it "raises io_error when the file cannot be moved into place, and creates no target" do
    allow(File).to receive(:rename).and_raise(Errno::EXDEV, "rename")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError) { |e| expect(e.cause).to be_a(Errno::EXDEV) }
      expect(Dir.children(dir)).to be_empty
    end
  end

  it "propagates render errors from the underlying render.pdf_stream call" do
    WebMock.reset!
    stub_request(:post, "https://api.poli.page/v1/render")
      .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::ValidationError)
      expect(Dir.children(dir)).to be_empty
    end
  end

  it "leaves an existing target untouched when the render or the download fails" do
    stub_request(:get, "https://s3.example/presigned/x.pdf").to_return(status: 403, body: "<Error/>")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      File.write(path, "previous")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::DownloadError)
      expect(File.read(path)).to eq("previous")
      expect(Dir.children(dir)).to eq(["out.pdf"])
    end
  end

  # Creating a symbolic link needs a privilege Windows runners lack.
  it "writes through a symbolic link to the file it points to, the link kept", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir(File.join(dir, "real"))
      real = File.join(dir, "real", "out.pdf")
      File.write(real, "previous")
      link = File.join(dir, "link.pdf")
      File.symlink(File.join("real", "out.pdf"), link)
      client.render_to_file(link, project: "billing", template: "invoice", data: {})
      expect(File.symlink?(link)).to be true
      expect(File.readlink(link)).to eq(File.join("real", "out.pdf"))
      expect(File.binread(real)).to eq("%PDF-1.4 stub data")
      expect(Dir.children(File.join(dir, "real"))).to eq(["out.pdf"])
    end
  end

  it "creates the file a dangling symbolic link points to, and follows chains of links", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      real = File.join(dir, "new.pdf")
      File.symlink(real, File.join(dir, "first.pdf"))
      File.symlink("first.pdf", File.join(dir, "second.pdf"))
      client.render_to_file(File.join(dir, "second.pdf"), project: "billing", template: "invoice", data: {})
      expect(File.binread(real)).to eq("%PDF-1.4 stub data")
      expect([File.symlink?(File.join(dir, "first.pdf")), File.symlink?(File.join(dir, "second.pdf"))])
        .to eq([true, true])
    end
  end

  # `sym -> real/dir` and `real/dir/link -> ../a.pdf`: the link's `..` leaves
  # `real/dir`, the directory `sym` points to, so `sym/link` is `real/a.pdf`.
  def linked_directory(dir)
    FileUtils.mkdir_p(File.join(dir, "real", "dir"))
    File.symlink(File.join("real", "dir"), File.join(dir, "sym"))
    File.symlink(File.join("..", "a.pdf"), File.join(dir, "real", "dir", "link"))
    File.join(dir, "sym", "link")
  end

  it "reads a link's .. against the link's real directory, for an existing file", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      path = linked_directory(dir)
      File.write(File.join(dir, "real", "a.pdf"), "previous")
      client.render_to_file(path, project: "billing", template: "invoice", data: {})
      expect(File.binread(File.join(dir, "real", "a.pdf"))).to eq("%PDF-1.4 stub data")
      expect(File.symlink?(File.join(dir, "real", "dir", "link"))).to be true
      expect(File.exist?(File.join(dir, "a.pdf"))).to be false
    end
  end

  it "reads a link's .. against the link's real directory, for a file not there yet", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      path = linked_directory(dir)
      client.render_to_file(path, project: "billing", template: "invoice", data: {})
      expect(File.binread(File.join(dir, "real", "a.pdf"))).to eq("%PDF-1.4 stub data")
      expect(File.symlink?(File.join(dir, "real", "dir", "link"))).to be true
      expect(Dir.children(dir).sort).to eq(%w[real sym])
    end
  end

  it "raises io_error before any render for a loop of symbolic links", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      File.symlink("b.pdf", File.join(dir, "a.pdf"))
      File.symlink("a.pdf", File.join(dir, "b.pdf"))
      expect { client.render_to_file(File.join(dir, "a.pdf"), project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError) { |e| expect(e.cause).to be_a(Errno::ELOOP) }
      expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
    end
  end

  # As root, every file is writable.
  it "raises io_error before any render, and keeps the file, when the target is read-only",
     skip: Process.respond_to?(:euid) && Process.euid.zero? do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      File.write(path, "previous")
      File.chmod(0o444, path)
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::FileWriteError, /\AFailed to write PDF: /) { |e|
          expect(e.cause).to be_a(Errno::EACCES)
          expect(e.status).to be_nil
        }
      expect(a_request(:post, "https://api.poli.page/v1/render")).not_to have_been_made
      expect(File.read(path)).to eq("previous")
      expect(Dir.children(dir)).to eq(["out.pdf"])
    ensure
      File.chmod(0o644, path) if path && File.exist?(path)
    end
  end

  it "gives a new file the umask's default mode and keeps an existing file's mode", skip: Gem.win_platform? do
    Dir.mktmpdir do |dir|
      fresh = File.join(dir, "new.pdf")
      client.render_to_file(fresh, project: "billing", template: "invoice", data: {})
      expect(File.stat(fresh).mode & 0o777).to eq(0o666 & ~File.umask)

      kept = File.join(dir, "kept.pdf")
      File.write(kept, "previous")
      File.chmod(0o640, kept)
      client.render_to_file(kept, project: "billing", template: "invoice", data: {})
      expect(File.stat(kept).mode & 0o777).to eq(0o640)
    end
  end
end
