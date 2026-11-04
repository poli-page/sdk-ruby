# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require_relative "../../support/mock_http_server"

# The client's `timeout` bounds the presigned-URL download: the whole download
# for `fetch_bytes` (`download_pdf`, `render.pdf`), and the wait for the
# answer's head and each gap between two chunks for `stream_bytes`
# (`render.pdf_stream`, `render_to_file`). Past it, `DOWNLOAD_FAILED` with the
# message `Failed to download PDF: timeout`. Real sockets, WebMock off; the
# timeouts are short and the bounds on elapsed time generous, so that a slow CI
# runner cannot turn a pass into a failure.
RSpec.describe PoliPage::Internal::PresignedFetch do
  around { |example| PoliPageSpec::RealNetwork.around(example) }

  let(:pdf) { "%PDF-1.4 #{"x" * 64}" }
  let(:input) { { project: "billing", template: "invoice", data: {} } }

  # A render answer whose presigned URL points at the same local server.
  let(:rendered) do
    descriptor = JSON.parse(DocumentDescriptorJSON.build)
    { "status" => 200, "json" => descriptor.merge("presignedPdfUrl" => "{{origin}}/storage/doc_abc123.pdf") }
  end

  def with_server(steps)
    server = PoliPageSpec::MockHTTPServer.new(steps)
    yield server
  ensure
    server&.close
  end

  def client(timeout:)
    PoliPage::Client.new(api_key: "pp_sandbox_test", max_retries: 0, timeout: timeout)
  end

  def with_api_server(steps)
    server = PoliPageSpec::MockHTTPServer.new(
      steps, render: ->(value) { value.is_a?(Hash) ? value.transform_values { |v| fill_origin(v, server) } : value }
    )
    yield server
  ensure
    server&.close
  end

  def fill_origin(value, server)
    value.is_a?(String) ? value.sub("{{origin}}", server.origin) : value
  end

  def api(server, timeout:, max_retries: 0)
    PoliPage::Client.new(api_key: "pp_sandbox_test", base_url: server.origin, max_retries: max_retries,
                         timeout: timeout)
  end

  def url(server)
    "#{server.origin}/storage/doc_abc123.pdf?X-Amz-Signature=abc"
  end

  def head(length)
    "HTTP/1.1 200 Mock\r\nContent-Type: application/pdf\r\nContent-Length: #{length}\r\nConnection: close\r\n\r\n"
  end

  # The head, then the body one `slice` at a time, `every` seconds apart.
  def drip_body(body, every:, slice: 8)
    lambda do |socket, _request|
      socket.write(head(body.bytesize))
      body.scan(/.{1,#{slice}}/m).each do |part|
        sleep(every)
        socket.write(part)
      end
    end
  end

  # The head and `sent` bytes of `body`, then nothing for `stall` seconds.
  def stall_after(body, sent:, stall:)
    lambda do |socket, _request|
      socket.write(head(body.bytesize) + body.byteslice(0, sent))
      sleep(stall)
    end
  end

  # The head and `sent` bytes of `body`, then the connection closes.
  def cut_after(body, sent:)
    ->(socket, _request) { socket.write(head(body.bytesize) + body.byteslice(0, sent)) }
  end

  def failure
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = nil
    begin
      yield
    rescue PoliPage::Error => e
      error = e
    end
    [error, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end

  def expect_timeout(error)
    expect(error).to be_a(PoliPage::DownloadError)
    expect([error.code, error.message, error.status])
      .to eq(["DOWNLOAD_FAILED", "Failed to download PDF: timeout", nil])
    expect(error.retryable?).to be false
    expect(error.network_error?).to be false
  end

  describe "#fetch_bytes (download_pdf, render.pdf): the timeout bounds the whole download" do
    it "fails with the timeout message when the storage never answers" do
      with_server([{ "fault" => "hang" }]) do |server|
        error, took = failure { client(timeout: 0.3).fetch_bytes(url(server)) }
        expect_timeout(error)
        expect(took).to be < 3
        expect(server.requests.size).to eq(1)
      end
    end

    it "fails with the timeout message when the body outlasts the timeout, though each chunk comes in time" do
      with_server([drip_body(pdf, every: 0.1)]) do |server|
        error, took = failure { client(timeout: 0.4).fetch_bytes(url(server)) }
        expect_timeout(error)
        expect(took).to be < 3
      end
    end

    it "returns the whole body when it comes within the timeout" do
      with_server([drip_body(pdf, every: 0.01)]) do |server|
        expect(client(timeout: 5).fetch_bytes(url(server))).to eq(pdf)
      end
    end

    it "fails with the network message, not the timeout one, for a body cut short of its Content-Length" do
      with_server([cut_after(pdf, sent: 10)]) do |server|
        error, = failure { client(timeout: 5).fetch_bytes(url(server)) }
        expect(error).to be_a(PoliPage::DownloadError)
        expect([error.message, error.status]).to eq(["Failed to download PDF: network error", nil])
        expect(error.cause).to be_a(EOFError)
      end
    end

    it "fails with the network message, not the timeout one, when the connection is refused" do
      port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
      error, = failure { client(timeout: 5).fetch_bytes("http://127.0.0.1:#{port}/x.pdf") }
      expect(error).to be_a(PoliPage::DownloadError)
      expect(error.message).to eq("Failed to download PDF: network error")
    end

    it "fails at once with the timeout message for a timeout of zero, as an API call does" do
      with_server([{ "status" => 200, "text" => pdf }]) do |server|
        error, took = failure { client(timeout: 0).fetch_bytes(url(server)) }
        expect_timeout(error)
        expect(took).to be < 1
      end
    end

    it "times out the download of render.pdf with the timeout message, after one render" do
      with_api_server([rendered, { "fault" => "hang" }]) do |server|
        error, = failure { api(server, timeout: 0.3, max_retries: 2).render.pdf(**input) }
        expect_timeout(error)
        expect(server.requests.size).to eq(2)
      end
    end
  end

  describe "#stream_bytes (render.pdf_stream, render_to_file): the timeout is an idle timeout" do
    it "fails before the first chunk with the timeout message when the storage never answers" do
      with_server([{ "fault" => "hang" }]) do |server|
        chunks = []
        error, took = failure { client(timeout: 0.3).stream_bytes(url(server)) { |c| chunks << c } }
        expect_timeout(error)
        expect(chunks).to be_empty
        expect(took).to be < 3
      end
    end

    it "bounds the wait for the answer's head as a whole, even when it drips in time" do
      drip_head = lambda do |socket, _request|
        head(pdf.bytesize).each_char do |char|
          sleep(0.05)
          socket.write(char)
        end
      end
      with_server([drip_head]) do |server|
        error, took = failure { client(timeout: 0.4).stream_bytes(url(server)) { |_c| nil } }
        expect_timeout(error)
        expect(took).to be < 3
      end
    end

    it "bounds the head and the first byte together: a late head leaves less time for the first byte" do
      late_head_then_stall = lambda do |socket, _request|
        sleep(0.8)
        socket.write(head(pdf.bytesize))
        sleep(3)
      end
      with_server([late_head_then_stall]) do |server|
        chunks = []
        error, took = failure { client(timeout: 1).stream_bytes(url(server)) { |c| chunks << c } }
        expect_timeout(error)
        expect(chunks).to be_empty
        # One shared timeout ends it at about 1 s; a fresh one after the head
        # would have waited until about 1.8 s.
        expect(took).to be_between(0.9, 1.5)
      end
    end

    it "streams a body that outlasts the timeout as long as each gap is shorter" do
      with_server([drip_body(pdf, every: 0.1)]) do |server|
        received = +""
        client(timeout: 0.5).stream_bytes(url(server)) { |c| received << c }
        expect(received).to eq(pdf)
      end
    end

    it "does not count the time the caller's block takes" do
      with_server([drip_body(pdf, every: 0.01, slice: 32)]) do |server|
        received = +""
        client(timeout: 0.3).stream_bytes(url(server)) do |c|
          sleep(0.4) if received.empty?
          received << c
        end
        expect(received).to eq(pdf)
      end
    end

    it "fails mid-stream with the timeout message when a gap outlasts the timeout" do
      with_server([stall_after(pdf, sent: 16, stall: 2)]) do |server|
        received = +""
        error, took = failure { client(timeout: 0.3).stream_bytes(url(server)) { |c| received << c } }
        expect_timeout(error)
        expect(received).to eq(pdf.byteslice(0, 16))
        expect(took).to be < 2
      end
    end

    it "fails with the network message, not the timeout one, for a body cut short of its Content-Length" do
      with_server([cut_after(pdf, sent: 10)]) do |server|
        error, = failure { client(timeout: 5).stream_bytes(url(server)) { |_c| nil } }
        expect(error).to be_a(PoliPage::DownloadError)
        expect(error.message).to eq("Failed to download PDF: network error")
      end
    end
  end

  describe "Client#render_to_file and the download" do
    def render_to(path, download, timeout: 5)
      with_api_server([rendered, download]) do |server|
        failure { api(server, timeout: timeout).render_to_file(path, **input) }.first
      end
    end

    it "never writes a body cut short of its Content-Length to the target" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.pdf")
        File.write(path, "previous")
        error = render_to(path, cut_after(pdf, sent: 10))
        expect(error).to be_a(PoliPage::DownloadError)
        expect(File.read(path)).to eq("previous")
        expect(Dir.children(dir)).to eq(["out.pdf"])
      end
    end

    it "leaves a missing target missing when the download times out mid-stream" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.pdf")
        error = render_to(path, stall_after(pdf, sent: 16, stall: 2), timeout: 0.3)
        expect_timeout(error)
        expect(Dir.children(dir)).to be_empty
      end
    end

    it "writes the whole PDF once the download completes" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "out.pdf")
        expect(render_to(path, drip_body(pdf, every: 0.01))).to be_nil
        expect(File.binread(path)).to eq(pdf)
        expect(Dir.children(dir)).to eq(["out.pdf"])
      end
    end
  end
end
