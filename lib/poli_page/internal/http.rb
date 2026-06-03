# frozen_string_literal: true

require "json"
require "time"

require_relative "constants"

module PoliPage
  module Internal
    # @api private
    #
    # Pure transport helpers — no I/O, no socket access. Mirrors
    # `sdk-node/src/internal/http.ts` (sdk-ruby-plan.md §13 Phase 1).
    module HTTP
      module_function

      # @param base [String] e.g. "https://api.poli.page"
      # @param path [String] e.g. "/v1/render"
      # @return [String] the joined URL with exactly one slash between the two
      def build_url(base, path)
        "#{base.chomp("/")}/#{path.sub(%r{\A/}, "")}"
      end

      # @param method         [Symbol] :get, :post, or :delete
      # @param api_key        [String]
      # @param idempotency_key [String, nil] only used on POST
      # @param user_agent     [String]
      # @return [Hash{String=>String}]
      def build_headers(method:, api_key:, idempotency_key:, user_agent:)
        headers = {
          Constants::HEADER_ACCEPT        => "application/json",
          Constants::HEADER_AUTHORIZATION => "Bearer #{api_key}",
          Constants::HEADER_USER_AGENT    => user_agent
        }
        if method == :post
          headers[Constants::HEADER_CONTENT_TYPE] = "application/json"
          headers[Constants::HEADER_IDEMPOTENCY_KEY] = idempotency_key if idempotency_key
        end
        headers
      end

      # Parse a non-2xx response body into a `[code, message]` pair. Falls
      # back to `INTERNAL_ERROR` when the body is not parseable JSON. The
      # fallback chain (`code → message → error → 'unknown_error'`) is
      # ported verbatim from Node `parseErrorBody` (sdk-ruby-plan.md §7.3).
      #
      # @param body   [String]
      # @param status [Integer]
      # @return       [Array(String, String)] `[code, message]`
      def parse_error_body(body, status)
        parsed = begin
          JSON.parse(body)
        rescue JSON::ParserError, TypeError
          nil
        end
        unless parsed.is_a?(Hash)
          return ["INTERNAL_ERROR",
                  "HTTP #{status}: response body was not valid JSON"]
        end

        # RFC 7807: prefer `detail` (specific reason) over `title` (generic name)
        # over the legacy `message` field; fall back to a canned status string.
        # Code is verbatim from the API — never inferred from message.
        code = parsed["code"] || parsed["error"] || "unknown_error"
        message = parsed["detail"] || parsed["title"] || parsed["message"] || "HTTP #{status}"
        [code, message]
      end

      # Parse the `Retry-After` response header. Accepts an integer number
      # of seconds or an HTTP-date. Returns the delay in **seconds** (Ruby's
      # `Kernel#sleep` and `Net::HTTP#*_timeout` units), capped at
      # `RETRY_AFTER_CAP` (30 s). Returns `nil` when the header is missing or
      # unparseable. Mirrors Node `parseRetryAfter` modulo unit (ms → s).
      def parse_retry_after(header_value)
        return nil if header_value.nil? || header_value.empty?

        return header_value.to_i.clamp(0, Constants::RETRY_AFTER_CAP) if /\A\d+\z/.match?(header_value)

        begin
          target = Time.httpdate(header_value)
        rescue ArgumentError
          return nil
        end
        (target - Time.now).floor.clamp(0, Constants::RETRY_AFTER_CAP)
      end

      # Compute the delay (in seconds) before the next retry attempt. When
      # `retry_after` is non-nil, it is returned as-is (server-explicit, no
      # jitter). Otherwise: `base_delay * 2**(attempt-1) * (0.5 + rand)`.
      # `attempt` is 1-based: 1 means the first retry.
      def compute_backoff(attempt:, base_delay:, retry_after: nil)
        return retry_after unless retry_after.nil?

        exp = base_delay * (2**(attempt - 1))
        exp * (0.5 + rand)
      end

      # Map an API response (status + parsed code/message) to the most
      # specific `PoliPage::Error` subclass (sdk-ruby-plan.md §7).
      #
      # @param status     [Integer]
      # @param code       [String]
      # @param message    [String]
      # @param request_id [String, nil]
      # @return           [PoliPage::Error]
      def classify(status:, code:, message:, request_id:)
        klass = STATUS_MAP.fetch(status, PoliPage::APIError)
        klass.new(message, code: code, status: status, request_id: request_id)
      end

      STATUS_MAP = {
        400 => PoliPage::ValidationError,
        401 => PoliPage::AuthenticationError,
        403 => PoliPage::PermissionDeniedError,
        404 => PoliPage::NotFoundError,
        410 => PoliPage::GoneError,
        429 => PoliPage::RateLimitError
      }.freeze
    end
  end
end
