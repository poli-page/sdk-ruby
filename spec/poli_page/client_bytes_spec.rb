# frozen_string_literal: true

# Phase 3 additions to PoliPage::Client: `fetch_bytes(url)` and
# `stream_bytes(url) { |chunk| ... }` — both used by DocumentDescriptor
# and the streaming render methods. The presigned URL is fetched
# unauthenticated, with NO SDK retry policy (sdk-ruby-plan.md §5.5).

RSpec.describe PoliPage::Client do
  let(:client) { described_class.new(api_key: "pp_test_abc", max_retries: 0) }
  let(:url)    { "https://s3.example/presigned/x.pdf" }

  describe "#fetch_bytes" do
    it "GETs the URL and returns the raw body bytes" do
      stub_request(:get, url).to_return(status: 200, body: "%PDF-1.4 stub",
                                        headers: { "Content-Type" => "application/pdf" })
      bytes = client.fetch_bytes(url)
      expect(bytes).to eq("%PDF-1.4 stub")
    end

    it "does NOT send the Authorization header (presigned URL is unauthenticated)" do
      stub = stub_request(:get, url).with do |req|
        !req.headers.key?("Authorization")
      end.to_return(status: 200, body: "stub")
      client.fetch_bytes(url)
      expect(stub).to have_been_requested
    end

    it "raises DownloadError on non-2xx" do
      stub_request(:get, url).to_return(status: 403, body: "<Error/>")
      expect { client.fetch_bytes(url) }
        .to raise_error(PoliPage::DownloadError) { |e|
          expect(e.code).to eq("DOWNLOAD_FAILED")
          expect(e.status).to eq(403)
        }
    end

    it "raises DownloadError on connection failure" do
      stub_request(:get, url).to_raise(SocketError.new("dns"))
      expect { client.fetch_bytes(url) }.to raise_error(PoliPage::DownloadError, /dns/)
    end

    it "does NOT retry on 5xx (presigned fetch is outside the retry policy)" do
      stub = stub_request(:get, url).to_return(status: 503, body: "down")
      expect { client.fetch_bytes(url) }.to raise_error(PoliPage::DownloadError)
      expect(stub).to have_been_requested.times(1)
    end
  end

  describe "#stream_bytes" do
    it "yields the response body in chunks to the block" do
      stub_request(:get, url).to_return(status: 200, body: "AAAABBBBCCCC")
      collected = +""
      client.stream_bytes(url) { |chunk| collected << chunk }
      expect(collected).to eq("AAAABBBBCCCC")
    end

    it "raises DownloadError on non-2xx" do
      stub_request(:get, url).to_return(status: 404, body: "missing")
      expect { client.stream_bytes(url) { |_c| nil } }
        .to raise_error(PoliPage::DownloadError) { |e|
          expect(e.status).to eq(404)
        }
    end

    it "raises InternalError when the response has no body (Content-Length: 0)" do
      stub_request(:get, url).to_return(status: 200, body: "", headers: { "Content-Length" => "0" })
      expect { client.stream_bytes(url) { |_c| nil } }
        .to raise_error(PoliPage::InternalError, /no body/i)
    end
  end
end
