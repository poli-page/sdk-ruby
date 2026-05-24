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
  # execution to `PoliPage::Internal::Transport`. The `render` and (future)
  # `documents` resource namespaces hold a reference to this client and
  # delegate request execution back through it (sdk-ruby-plan.md §3.1 + §6 +
  # §10).
  #
  # Thread-safety: configuration is immutable after `#initialize`; each
  # request opens its own `Net::HTTP` connection. A single `Client` may be
  # safely shared across threads.
  class Client
    include Internal::PresignedFetch

    attr_reader :base_url, :max_retries, :retry_delay, :timeout, :render, :documents

    def initialize(api_key:, base_url: Internal::Constants::DEFAULT_BASE_URL,
                   max_retries: Internal::Constants::DEFAULT_MAX_RETRIES,
                   retry_delay: Internal::Constants::DEFAULT_RETRY_DELAY,
                   timeout: Internal::Constants::DEFAULT_TIMEOUT,
                   logger: nil, on_retry: nil, on_error: nil)
      raise InvalidOptionsError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key     = api_key
      @base_url    = base_url
      @max_retries = max_retries
      @retry_delay = retry_delay
      @timeout     = timeout
      @logger      = logger
      @on_retry    = on_retry
      @on_error    = on_error
      @transport   = Internal::Transport.new(base_url: base_url, timeout: timeout)
      @render      = Resources::Render.new(self)
      @documents   = Resources::Documents.new(self)
    end

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

    def run_with_retry(method:, path:, body:, idempotency_key:)
      state = { last_error: nil, next_retry_after: nil }

      (0..@max_retries).each do |attempt|
        sleep_before_retry(attempt, state) if attempt.positive?
        result = send_once(method: method, path: path, body: body, idempotency_key: idempotency_key)
        return result[:response] if result[:ok]

        state[:last_error] = result[:error]
        state[:next_retry_after] = result[:retry_after]
        raise_terminal(state[:last_error]) unless result[:retryable]
      end

      raise_terminal(state[:last_error])
    end

    def sleep_before_retry(attempt, state)
      delay = Internal::HTTP.compute_backoff(attempt: attempt, base_delay: @retry_delay,
                                             retry_after: state[:next_retry_after])
      fire_hook(@on_retry,
                RetryEvent.new(attempt: attempt + 1, delay: delay, reason: state[:last_error]))
      sleep(delay)
    end

    def raise_terminal(error)
      fire_hook(@on_error, error)
      raise error
    end

    def send_once(method:, path:, body:, idempotency_key:)
      headers = Internal::HTTP.build_headers(
        method: method, api_key: @api_key,
        idempotency_key: idempotency_key,
        user_agent: "poli-page-sdk-ruby/#{PoliPage::VERSION}"
      )
      response = @transport.execute(method: method, path: path, headers: headers, body: body)
      return { ok: true, response: response } if (200..299).cover?(response.status)

      build_error_result(response)
    rescue PoliPage::TimeoutError, PoliPage::ConnectionError => e
      { ok: false, error: e, retry_after: nil, retryable: true }
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
