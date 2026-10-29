# frozen_string_literal: true

require "json"
require "socket"
require "webmock"

module PoliPageSpec
  # Runs the example with WebMock switched off, so the SDK goes through the
  # real `Net::HTTP` class and real sockets.
  module RealNetwork
    def self.around(example)
      WebMock.disable!
      example.run
    ensure
      WebMock.enable!
    end
  end

  # A local HTTP/1.1 server on 127.0.0.1 that answers its `steps` in order,
  # one request per connection, and records every request.
  #
  # A step is a Hash in the API contract's format (`status` with `headers`
  # and one of `json`, `text` or `base64`, or `fault` `drop` / `hang`), or a
  # Proc called with the client socket and the recorded request, for the
  # answers no contract case describes (a body cut short, a drip). A request
  # with no step left gets `599 MOCK_EXHAUSTED`, so it shows in a diff.
  class MockHTTPServer
    Recorded = Struct.new(:verb, :target, :headers, :body, :at, :peer, keyword_init: true)

    # Raised for a step this server cannot answer (a bad case).
    class StepError < StandardError; end

    attr_reader :origin, :errors

    # @param steps  [Array<Hash, Proc>]
    # @param render [Proc] applied to a step's `headers` and `json` when it is
    #   answered (the contract's placeholders).
    def initialize(steps, render: ->(value) { value })
      @steps = steps
      @render = render
      @requests = []
      @errors = []
      @threads = []
      @lock = Mutex.new
      @released = ConditionVariable.new
      @closed = false
      @server = TCPServer.new("127.0.0.1", 0)
      @origin = "http://127.0.0.1:#{@server.addr[1]}"
      @acceptor = Thread.new { accept_loop }
    end

    def requests
      @lock.synchronize { @requests.dup }
    end

    # Ends every `hang`, stops accepting and waits for the connections.
    def close
      @lock.synchronize do
        @closed = true
        @released.broadcast
      end
      @server.close
      @acceptor.join(5)
      @lock.synchronize { @threads.dup }.each { |thread| thread.join(5) }
    end

    # Blocks until `close` (a `hang`).
    def wait_until_closed
      @lock.synchronize { @released.wait(@lock) until @closed }
    end

    # A complete answer, for steps written as a Proc.
    def self.response(status, headers, body)
      lines = ["HTTP/1.1 #{status} Mock"]
      headers.each { |name, value| lines << "#{name}: #{value}" }
      lines << "Content-Length: #{body.bytesize}" unless body.nil?
      lines << "Connection: close"
      "#{lines.join("\r\n")}\r\n\r\n#{body}"
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        @lock.synchronize { @threads << Thread.new { serve(socket) } }
      end
    rescue IOError, SystemCallError
      nil # the server was closed
    end

    def serve(socket)
      request = read_request(socket)
      answer(socket, request, record(request)) if request
    rescue IOError, SystemCallError
      nil # the client went away first (a timeout)
    rescue StandardError => e
      @lock.synchronize { @errors << e }
    ensure
      socket.close
    end

    def read_request(socket)
      line = socket.gets("\r\n")
      return nil if line.nil?

      at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      method, target = line.split
      headers = read_headers(socket)
      length = headers.fetch("content-length", "0").to_i
      body = length.positive? ? socket.read(length) : ""
      Recorded.new(verb: method, target: target, headers: headers, body: body, at: at,
                   peer: socket.peeraddr[1])
    end

    def read_headers(socket)
      headers = {}
      while (line = socket.gets("\r\n")) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.strip.downcase] = value.to_s.strip
      end
      headers
    end

    def record(request)
      @lock.synchronize do
        @requests << request
        @steps[@requests.size - 1]
      end
    end

    def answer(socket, request, step)
      case step
      when nil then socket.write(self.class.response(599, { "Content-Type" => "application/json" },
                                                     '{"error":"MOCK_EXHAUSTED"}'))
      when Proc then step.call(socket, request)
      else answer_step(socket, step)
      end
    end

    def answer_step(socket, step)
      case step["fault"]
      when nil then socket.write(serialize(step))
      when "drop" then nil # `serve` closes the socket without a byte
      when "hang" then wait_until_closed
      else raise StepError, "unknown fault #{step["fault"].inspect}"
      end
    end

    def serialize(step)
      headers = @render.call(step.fetch("headers", {})).dup
      body = step_body(step, headers)
      body = "" if body.nil? && ![204, 304].include?(step.fetch("status"))
      self.class.response(step.fetch("status"), headers, body)
    end

    def step_body(step, headers)
      if step.key?("json")
        headers["Content-Type"] = "application/json" unless headers.keys.any? { |k| k.casecmp?("content-type") }
        JSON.generate(@render.call(step["json"]))
      elsif step.key?("text")
        step["text"].b
      elsif step.key?("base64")
        step["base64"].unpack1("m")
      end
    end
  end
end
