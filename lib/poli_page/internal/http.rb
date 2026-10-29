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

      # Parse a non-2xx response body into a `[code, message]` pair
      # (sdk-specification.md §8.2). A body that is not a JSON object gives
      # `INTERNAL_ERROR` / `HTTP <status>`; the caller keeps the real status.
      # Otherwise `code` is the body's `code`, else `error`, else
      # `unknown_error`, and `message` its `detail`, else `title`, else
      # `message`, else `HTTP <status>`. The code is copied verbatim: it is
      # never inferred from the status or the message.
      #
      # @param body   [String]
      # @param status [Integer]
      # @return       [Array(String, String)] `[code, message]`
      def parse_error_body(body, status)
        parsed = parse_json_or_nil(body)
        return ["INTERNAL_ERROR", "HTTP #{status}"] unless parsed.is_a?(Hash)

        code = parsed.values_at("code", "error").compact.first || "unknown_error"
        message = parsed.values_at("detail", "title", "message").compact.first || "HTTP #{status}"
        [code, message]
      end

      def parse_json_or_nil(body)
        JSON.parse(body)
      rescue JSON::ParserError, TypeError
        nil
      end

      # Parse the `Retry-After` response header: integer seconds or an
      # HTTP-date (IMF-fixdate, RFC 850 or asctime), nothing else. Returns the
      # delay in **seconds** (Ruby's `Kernel#sleep` unit), clamped to
      # 0..`RETRY_AFTER_CAP` (30 s); a date keeps its sub-second remainder and
      # a past date gives 0. Returns `nil` when the header is missing or
      # unparseable, so the backoff applies. `Retry-After-Ms` is never read.
      def parse_retry_after(header_value)
        value = header_value.to_s.strip
        return nil if value.empty?

        # An Integer of any size: a huge value clamps, it never overflows.
        return value.to_i.clamp(0, Constants::RETRY_AFTER_CAP) if /\A\d+\z/.match?(value)

        begin
          target = Time.httpdate(value)
        rescue ArgumentError
          return nil
        end
        (target - Time.now).to_f.clamp(0.0, Constants::RETRY_AFTER_CAP.to_f)
      end

      # Compute the delay (in seconds) before the next retry attempt. When
      # `retry_after` is non-nil, it is returned as-is (server-explicit, no
      # jitter). Otherwise: `base_delay * 2**(attempt-1) * j`, `j` uniform in
      # `[0.5, 1.5)`. `attempt` is 1-based: 1 means the first retry.
      def compute_backoff(attempt:, base_delay:, retry_after: nil)
        return retry_after unless retry_after.nil?

        exp = base_delay * (2**(attempt - 1))
        exp * (0.5 + rand)
      end

      # Sleep `seconds`, and sleep again for the rest whenever the sleep
      # returns early, so a retry wait is never shorter than its delay
      # (sdk-specification.md §9.2). Measured on the monotonic clock.
      def sleep_at_least(seconds)
        deadline = monotonic_now + seconds
        loop do
          left = deadline - monotonic_now
          break if left <= 0

          sleep(left)
        end
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Map an API response (status + parsed code/message) to the most
      # specific `PoliPage::Error` subclass (sdk-ruby-plan.md §7).
      #
      # @param status     [Integer]
      # @param code       [String]
      # @param message    [String]
      # @param request_id [String, nil]
      # @param cause      [Exception, nil]
      # @return           [PoliPage::Error]
      def classify(status:, code:, message:, request_id:, cause: nil)
        klass = STATUS_MAP.fetch(status, PoliPage::APIError)
        klass.new(message, code: code, status: status, request_id: request_id, cause: cause)
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
