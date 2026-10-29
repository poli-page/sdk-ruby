# frozen_string_literal: true

require_relative "../../support/mock_http_server"

# The client's `timeout` bounds each whole attempt, body included, and an
# answer's body is read inside its attempt (sdk-specification.md §8.2, §9.1,
# §9.4). Real sockets, WebMock off.
RSpec.describe PoliPage::Internal::Transport do
  describe "attempt timeout and body reads" do
    around { |example| PoliPageSpec::RealNetwork.around(example) }

    let(:ok) { { "status" => 200, "json" => JSON.parse(DocumentDescriptorJSON.build) } }

    def with_server(steps)
      server = PoliPageSpec::MockHTTPServer.new(steps)
      yield server
    ensure
      server&.close
    end

    def client(server, **options)
      PoliPage::Client.new(api_key: "pp_sandbox_test", base_url: server.origin, max_retries: 0, timeout: 1,
                           **options)
    end

    def elapsed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    # Answers the headers and `sent` of a `length`-byte body, then closes.
    def cut_body(status, length:, sent:)
      lambda do |socket, _request|
        socket.write("HTTP/1.1 #{status} Mock\r\nContent-Type: application/json\r\nx-request-id: req_cut\r\n" \
                     "Content-Length: #{length}\r\n\r\n#{sent}")
      end
    end

    # Answers the headers, then one body byte every `every` seconds.
    def drip(every:, bytes:)
      lambda do |socket, _request|
        socket.write("HTTP/1.1 200 Mock\r\nContent-Type: application/json\r\nContent-Length: #{bytes}\r\n\r\n")
        bytes.times do
          sleep(every)
          socket.write(" ")
        end
      end
    end

    it "ends a hung attempt with the timeout error in well under 3 s" do
      with_server([{ "fault" => "hang" }]) do |server|
        error = nil
        took = elapsed do
          client(server, timeout: 0.2).documents.get("doc_abc123")
        rescue PoliPage::Error => e
          error = e
        end
        expect(error).to be_a(PoliPage::TimeoutError)
        expect(error.message).to eq("Request timed out after 200ms")
        expect(took).to be < 3
        expect(server.requests.size).to eq(1)
      end
    end

    it "ends an attempt whose body drips slower than its timeout, though each byte comes in time" do
      with_server([drip(every: 0.1, bytes: 40)]) do |server|
        error = nil
        took = elapsed do
          client(server, timeout: 0.5).documents.get("doc_abc123")
        rescue PoliPage::Error => e
          error = e
        end
        expect(error).to be_a(PoliPage::TimeoutError)
        expect(error.message).to eq("Request timed out after 500ms")
        expect(took).to be < 2
      end
    end

    it "retries a 2xx whose body is cut as a network_error" do
      with_server([cut_body(200, length: 500, sent: '{"documentId"'), ok]) do |server|
        doc = client(server, max_retries: 1, retry_delay: 0.01).documents.get("doc_abc123")
        expect(doc.document_id).to eq("doc_abc123")
        expect(server.requests.size).to eq(2)
      end
    end

    it "raises network_error for a cut 2xx body, the read error as cause" do
      with_server([cut_body(200, length: 500, sent: "{")]) do |server|
        expect { client(server).documents.get("doc_abc123") }
          .to raise_error(PoliPage::ConnectionError, "Network request failed") { |e| expect(e.cause).to be_a(EOFError) }
      end
    end

    it "handles a non-2xx whose body is cut as a body that is not JSON, keeping status and request id" do
      with_server([cut_body(503, length: 500, sent: '{"error":"PUBLISH_IN_PROGRESS"'), ok]) do |server|
        expect { client(server).documents.get("doc_abc123") }
          .to raise_error(PoliPage::APIError) { |e|
            expect([e.code, e.message, e.status, e.request_id]).to eq(["INTERNAL_ERROR", "HTTP 503", 503, "req_cut"])
            expect(e.retryable?).to be true
            expect(e.cause).to be_a(EOFError)
          }
      end
    end

    it "retries a cut 503 body by its status, and does not retry a cut 400 body" do
      with_server([cut_body(503, length: 50, sent: "{"), ok]) do |server|
        client(server, max_retries: 1, retry_delay: 0.01).documents.get("doc_abc123")
        expect(server.requests.size).to eq(2)
      end
      with_server([cut_body(400, length: 50, sent: "{"), ok]) do |server|
        expect { client(server, max_retries: 1, retry_delay: 0.01).documents.get("doc_abc123") }
          .to raise_error(PoliPage::ValidationError, "HTTP 400")
        expect(server.requests.size).to eq(1)
      end
    end

    it "handles a non-2xx whose body stalls past the timeout as INTERNAL_ERROR with its status" do
      stall = lambda do |socket, request|
        cut_body(502, length: 50, sent: "{").call(socket, request)
        sleep(1)
      end
      with_server([stall]) do |server|
        expect { client(server, timeout: 0.2).documents.get("doc_abc123") }
          .to raise_error(PoliPage::APIError, "HTTP 502") { |e| expect(e.status).to eq(502) }
      end
    end

    it "lets a caller's Timeout.timeout around the call reach the caller as is" do
      with_server([{ "fault" => "hang" }, ok]) do |server|
        expect { Timeout.timeout(0.2) { client(server, timeout: 5, max_retries: 2).documents.get("doc_abc123") } }
          .to raise_error(Timeout::Error) { |e| expect(e).not_to be_a(PoliPage::Error) }
        expect(server.requests.size).to eq(1)
      end
    end

    it "fires on_response only once the body is read" do
      responses = []
      with_server([cut_body(200, length: 50, sent: "{")]) do |server|
        expect { client(server, on_response: ->(e) { responses << e }).documents.get("doc_abc123") }
          .to raise_error(PoliPage::ConnectionError)
      end
      expect(responses).to eq([])
    end
  end
end
