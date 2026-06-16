# frozen_string_literal: true

require "json"

require_relative "errors"
require_relative "retry_event"
require_relative "internal/constants"
require_relative "internal/http"
require_relative "internal/presigned_fetch"
require_relative "internal/transport"
require_relative "internal/uuid"
require_relative "internal/wire"
require_relative "render"
require_relative "documents"

module PoliPage
  # Main entry point — orchestrates retries, fires hooks, and delegates HTTP
  # execution to `PoliPage::Internal::Transport`. The `render` and `documents`
  # resource namespaces hold a reference to this client and delegate request
  # execution back through it.
  #
  # Thread-safety: configuration is immutable after `#initialize`; each
  # request opens its own `Net::HTTP` connection. A single `Client` may be
  # safely shared across threads — build one at boot and reuse it.
  #
  # @example Construct with defaults
  #   client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))
  #
  # @example Construct with full configuration
  #   client = PoliPage::Client.new(
  #     api_key:     ENV.fetch("POLI_PAGE_API_KEY"),
  #     base_url:    "https://api.example.com",
  #     max_retries: 3,
  #     retry_delay: 0.5,                            # seconds
  #     timeout:     30,                             # seconds
  #     logger:      Logger.new($stdout),
  #     on_retry:    ->(e) { metrics.increment("polipage.retry") },
  #     on_error:    ->(err) { Sentry.capture_exception(err) },
  #     proxy:       "http://user:pass@proxy.example.com:8080",
  #     ca_file:     "/etc/ssl/corp-mitm-ca.pem"
  #   )
  #
  # @example Behind a corporate egress proxy (env-detected)
  #   # `http_proxy` / `https_proxy` / `no_proxy` env vars are honoured
  #   # automatically — no `proxy:` kwarg needed.
  #   client = PoliPage::Client.new(api_key: ENV.fetch("POLI_PAGE_API_KEY"))
  class Client
    include Internal::PresignedFetch

    attr_reader :base_url, :max_retries, :retry_delay, :timeout, :render, :documents

    def initialize(api_key:, base_url: Internal::Constants::DEFAULT_BASE_URL,
                   max_retries: Internal::Constants::DEFAULT_MAX_RETRIES,
                   retry_delay: Internal::Constants::DEFAULT_RETRY_DELAY,
                   timeout: Internal::Constants::DEFAULT_TIMEOUT,
                   logger: nil, on_request: nil, on_response: nil,
                   on_retry: nil, on_error: nil,
                   proxy: nil, ca_file: nil, ca_path: nil)
      raise InvalidOptionsError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key     = api_key
      @base_url    = base_url
      @max_retries = max_retries
      @retry_delay = retry_delay
      @timeout     = timeout
      @logger      = logger
      @on_request  = on_request
      @on_response = on_response
      @on_retry    = on_retry
      @on_error    = on_error
      @proxy       = proxy
      @ca_file     = ca_file
      @ca_path     = ca_path
      init_collaborators
    end

    # Redacted `#inspect`. Ruby's default would dump `@api_key` into any
    # `puts client` or exception backtrace — that's how secrets end up in
    # logs (sdk-ruby-plan.md §10.1 redaction rule).
    def inspect
      "#<PoliPage::Client base_url=#{@base_url.inspect} timeout=#{@timeout} max_retries=#{@max_retries}>"
    end
    alias to_s inspect

    # Execute a POST request against `path` with `body` (snake_case hash;
    # caller's responsibility to compact nils). Returns the parsed
    # snake_case-symbol-keyed Hash on 2xx, or raises a `PoliPage::Error`.
    #
    # @api private
    def execute_post(path, body:, idempotency_key: nil)
      wire_body = JSON.generate(Internal::Wire.to_wire(body))
      response = run_with_retry(method: :post, path: path, body: wire_body,
                                idempotency_key: idempotency_key || Internal::UUID.generate)
      parse_json_response(response)
    end

    # Execute a GET request against `path`. Returns the parsed
    # snake_case-symbol-keyed Hash on 2xx, or raises a `PoliPage::Error`.
    #
    # @api private
    def execute_get(path)
      response = run_with_retry(method: :get, path: path, body: nil, idempotency_key: nil)
      parse_json_response(response)
    end

    # Execute a DELETE request against `path`. Returns nil on 2xx; the
    # response body is ignored. Raises `PoliPage::Error` on non-2xx.
    #
    # @api private
    def execute_delete(path)
      run_with_retry(method: :delete, path: path, body: nil, idempotency_key: nil)
      nil
    end

    # Execute a GET request and return the raw `Internal::Transport::Response`
    # (body + headers) without JSON parsing. Used by `documents.preview` which
    # gets `text/html` directly plus the page count via the
    # `X-Document-Page-Count` response header.
    #
    # @api private
    def execute_get_raw(path)
      run_with_retry(method: :get, path: path, body: nil, idempotency_key: nil)
    end

    private

    def init_collaborators
      @transport = Internal::Transport.new(base_url: @base_url, timeout: @timeout,
                                           proxy: @proxy, ca_file: @ca_file, ca_path: @ca_path)
      @render = Resources::Render.new(self)
      @documents = Resources::Documents.new(self)
    end

    def run_with_retry(method:, path:, body:, idempotency_key:)
      state = { last_error: nil, next_retry_after: nil }

      (0..@max_retries).each do |attempt|
        sleep_before_retry(attempt, state) if attempt.positive?
        result = send_once(method: method, path: path, body: body,
                           idempotency_key: idempotency_key, attempt: attempt + 1)
        return result[:response] if result[:ok]

        record_failure(state, result)
        raise_terminal(state[:last_error]) unless result[:retryable]
      end

      raise_terminal(state[:last_error])
    end

    def record_failure(state, result)
      state[:last_error] = result[:error]
      state[:next_retry_after] = result[:retry_after]
    end

    def sleep_before_retry(attempt, state)
      delay = Internal::HTTP.compute_backoff(attempt: attempt, base_delay: @retry_delay,
                                             retry_after: state[:next_retry_after])
      fire_hook(@on_retry,
                RetryEvent.new(attempt: attempt + 1, delay_ms: (delay * 1000).round,
                               reason: state[:last_error]))
      sleep(delay)
    end

    def raise_terminal(error)
      fire_hook(@on_error, error)
      raise error
    end

    def send_once(method:, path:, body:, idempotency_key:, attempt:)
      headers = build_request_headers(method, idempotency_key)
      url = Internal::HTTP.build_url(@base_url, path)
      fire_hook(@on_request,
                RequestEvent.new(method: method.to_s.upcase, url: url, attempt: attempt))
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @transport.execute(method: method, path: path, headers: headers, body: body)
      return success_result(response, started_at) if (200..299).cover?(response.status)

      build_error_result(response)
    rescue PoliPage::TimeoutError, PoliPage::ConnectionError => e
      { ok: false, error: e, retry_after: nil, retryable: true }
    end

    def build_request_headers(method, idempotency_key)
      Internal::HTTP.build_headers(
        method: method, api_key: @api_key,
        idempotency_key: idempotency_key,
        user_agent: "poli-page-sdk-ruby/#{PoliPage::VERSION}"
      )
    end

    def success_result(response, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      fire_hook(@on_response,
                ResponseEvent.new(
                  status: response.status,
                  request_id: response.headers[Internal::Constants::HEADER_REQUEST_ID],
                  duration_ms: duration_ms
                ))
      { ok: true, response: response }
    end

    def build_error_result(response)
      status = response.status
      request_id = response.headers[Internal::Constants::HEADER_REQUEST_ID]
      code, message = Internal::HTTP.parse_error_body(response.body.to_s, status)
      error = Internal::HTTP.classify(status: status, code: code, message: message, request_id: request_id)
      retryable = status >= 500 || status == 429
      retry_after_header = response.headers[Internal::Constants::HEADER_RETRY_AFTER]
      retry_after = retryable ? Internal::HTTP.parse_retry_after(retry_after_header) : nil
      { ok: false, error: error, retry_after: retry_after, retryable: retryable }
    end

    def parse_json_response(response)
      parsed = JSON.parse(response.body)
      Internal::Wire.from_wire(parsed)
    rescue JSON::ParserError => e
      raise PoliPage::InternalError.new("response body was not valid JSON: #{e.message}", status: response.status)
    end

    def fire_hook(hook, event)
      return unless hook

      hook.call(event)
    rescue StandardError => e
      @logger&.warn("polipage hook raised: #{e.class}: #{e.message}")
    end
  end
end
