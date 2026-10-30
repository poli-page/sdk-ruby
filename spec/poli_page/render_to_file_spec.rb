# frozen_string_literal: true

# Ports sdk-node/tests/node.test.ts. Client#render_to_file streams the PDF
# bytes from `render.pdf_stream` straight to disk.

require "fileutils"
require "pathname"
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
  it "raises InvalidOptionsError when the path is unwritable", skip: Gem.win_platform? do
    expect do
      client.render_to_file("/no-such-root-i-promise/x.pdf",
                            project: "billing", template: "invoice", data: {})
    end.to raise_error(PoliPage::InvalidOptionsError)
  end

  it "propagates render errors from the underlying render.pdf_stream call" do
    WebMock.reset!
    stub_request(:post, "https://api.poli.page/v1/render")
      .to_return(status: 400, body: '{"code":"VALIDATION_ERROR","message":"bad"}')
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.pdf")
      expect { client.render_to_file(path, project: "billing", template: "invoice", data: {}) }
        .to raise_error(PoliPage::ValidationError)
      expect(File.exist?(path)).to be false
    end
  end
end
