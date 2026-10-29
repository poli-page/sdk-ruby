# frozen_string_literal: true

require_relative "../../support/mock_http_server"

# `Net::HTTP` sends a GET, HEAD, PUT, DELETE, OPTIONS or TRACE a second time
# by itself (`max_retries`, default 1) after a read error, a dropped
# connection or a read timeout, on a fresh connection. That attempt is not
# counted by the SDK's `max_retries` nor reported to `on_request`. The SDK
# sets `max_retries = 0`, so every resend is its own retry. Real sockets,
# WebMock off.
RSpec.describe PoliPage::Internal::Transport do
  describe "no hidden resend" do
    around { |example| PoliPageSpec::RealNetwork.around(example) }

    let(:drop) { { "fault" => "drop" } }
    let(:ok) { { "status" => 200, "json" => JSON.parse(DocumentDescriptorJSON.build) } }

    # `{{mock}}` in a step's headers or JSON is the server's origin.
    def with_server(steps)
      server = PoliPageSpec::MockHTTPServer.new(
        steps, render: ->(value) { JSON.parse(JSON.generate(value).gsub("{{mock}}", server.origin)) }
      )
      yield server
    ensure
      server&.close
    end

    def client(server, **options)
      PoliPage::Client.new(api_key: "pp_sandbox_test", base_url: server.origin, max_retries: 0, timeout: 2,
                           **options)
    end

    it "control: a bare Net::HTTP resends a dropped GET on its own" do
      with_server([drop, ok]) do |server|
        uri = URI("#{server.origin}/v1/documents/doc_abc123")
        response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(Net::HTTP::Get.new(uri)) }
        expect(response.code).to eq("200")
        expect(server.requests.size).to eq(2)
      end
    end

    it "sends a dropped GET once per attempt" do
      with_server([drop, ok]) do |server|
        expect { client(server).documents.get("doc_abc123") }.to raise_error(PoliPage::ConnectionError)
        expect(server.requests.map(&:verb)).to eq(%w[GET])
      end
    end

    it "sends a dropped DELETE once per attempt" do
      with_server([drop, { "status" => 204 }]) do |server|
        expect { client(server).documents.delete("doc_abc123") }.to raise_error(PoliPage::ConnectionError)
        expect(server.requests.map(&:verb)).to eq(%w[DELETE])
      end
    end

    it "sends a dropped POST once per attempt" do
      with_server([drop, ok]) do |server|
        expect { client(server).render.document(project: "p", template: "t", data: {}) }
          .to raise_error(PoliPage::ConnectionError)
        expect(server.requests.map(&:verb)).to eq(%w[POST])
      end
    end

    it "sends a GET that times out once per attempt" do
      with_server([{ "fault" => "hang" }, ok]) do |server|
        expect { client(server, timeout: 0.2).documents.get("doc_abc123") }.to raise_error(PoliPage::TimeoutError)
        expect(server.requests.size).to eq(1)
      end
    end

    it "never resends the presigned-URL download" do
      render = JSON.parse(DocumentDescriptorJSON.build).merge("presignedPdfUrl" => "{{mock}}/storage/x.pdf")
      with_server([{ "status" => 200, "json" => render }, drop, { "status" => 200, "text" => "%PDF" }]) do |server|
        expect { client(server).render.pdf(project: "p", template: "t", data: {}) }
          .to raise_error(PoliPage::DownloadError, "Failed to download PDF: network error")
        expect(server.requests.map(&:target)).to eq(["/v1/render", "/storage/x.pdf"])
      end
    end

    it "opens a fresh connection for each attempt, so no attempt goes out on a reused one" do
      error = { "status" => 503, "json" => { "error" => "PUBLISH_IN_PROGRESS" }, "headers" => { "Retry-After" => "0" } }
      with_server([error, ok]) do |server|
        client(server, max_retries: 1).documents.get("doc_abc123")
        peers = server.requests.map(&:peer)
        expect(peers.size).to eq(2)
        expect(peers.uniq.size).to eq(2)
      end
    end
  end
end
