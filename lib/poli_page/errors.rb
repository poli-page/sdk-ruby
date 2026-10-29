# frozen_string_literal: true

require_relative "internal/constants"

module PoliPage
  # Base for all SDK-raised errors. Inherits from `StandardError` so that
  # `rescue => e` catches it (whereas inheriting from `Exception` would
  # bypass the default rescue and surprise callers).
  #
  # The rescue-friendly path is the class hierarchy
  # (`rescue PoliPage::AuthenticationError`). The predicate methods below
  # follow sdk-specification.md §8.1: they read `status` and `code`, not the
  # class, so they give the same answer in every SDK.
  class Error < StandardError
    attr_reader :code, :status, :request_id

    # @param cause [Exception, nil] the lower-level error behind this one
    #   (the HTTP library's exception for a network failure or a timeout).
    #   Returned by {#cause} even when the error is raised outside the
    #   `rescue` that caught it.
    def initialize(message = nil, code:, status: nil, request_id: nil, cause: nil)
      super(message)
      @code       = code
      @status     = status
      @request_id = request_id
      @sdk_cause  = cause
    end

    # The error behind this one, if any (see {#initialize}).
    def cause
      @sdk_cause || super
    end

    # `status` is 401 or 403.
    def auth_error?
      [401, 403].include?(@status)
    end

    # `status` is 429.
    def rate_limit_error?
      @status == 429
    end

    # `status` is 400.
    def validation_error?
      @status == 400
    end

    # `code` is `network_error` or `timeout`.
    def network_error?
      %w[network_error timeout].include?(@code)
    end

    # A network error, a timeout, a 5xx or a 429, except the codes the SDK
    # never retries: `QUOTA_EXCEEDED`, `OVERAGE_CAP_EXCEEDED`,
    # `STORAGE_ACCESS_DENIED`, and `DOWNLOAD_FAILED` whatever the storage
    # status (the presigned-URL download is never retried).
    def retryable?
      return false if Internal::Constants::NON_RETRYABLE_CODES.include?(@code) || @code == "DOWNLOAD_FAILED"
      return true if network_error?

      !@status.nil? && (@status >= 500 || @status == 429)
    end

    # Canonical wire payload for framework integrations:
    # `{code:, message:, status:, request_id:}`. `status` surfaces 503 for
    # connection failures, 504 for timeouts, the API HTTP status for
    # status-bearing errors, and nil when unknown. The {#status} reader
    # itself stays nil for transport-error instances — only the payload
    # surfaces 503/504.
    def to_payload
      {
        code: @code,
        message: message,
        status: payload_status,
        request_id: @request_id
      }
    end

    def payload_status
      @status
    end
  end

  # API status errors. `status` carries the HTTP status; `code` is the
  # machine-readable string from the response body. The subclass picked for a
  # given status is decided by `PoliPage::Internal::HTTP.classify`.
  #
  #   400 → ValidationError
  #   401 → AuthenticationError
  #   403 → PermissionDeniedError
  #   404 → NotFoundError
  #   410 → GoneError
  #   429 → RateLimitError
  #   other 4xx / 5xx → APIError
  class ValidationError       < Error; end
  class AuthenticationError   < Error; end
  class PermissionDeniedError < Error; end
  class NotFoundError         < Error; end
  class GoneError             < Error; end
  class RateLimitError        < Error; end
  class APIError              < Error; end

  # --- SDK-internal errors. `status` is nil except where the SDK observed a
  # status from a non-API hop (e.g., the S3 second-hop for DownloadError). ---

  # `invalid_options` (`apiKey is required`), and `PROJECT_REQUIRED_FOR_DOCUMENT`
  # (`project is required`) raised before any request.
  class InvalidOptionsError < Error
    def initialize(message, code: "invalid_options")
      super(message, code: code, status: nil, request_id: nil)
    end
  end

  # `network_error`: DNS, connection or TLS failure, or a connection dropped
  # before the whole answer arrived. Message `Network request failed`; the
  # HTTP library's exception is {#cause}.
  class ConnectionError < Error
    def initialize(message: Internal::Constants::MESSAGE_NETWORK_ERROR, cause: nil)
      super(message, code: "network_error", status: nil, request_id: nil, cause: cause)
    end

    def payload_status
      503
    end
  end

  # `timeout`: an attempt exceeded the client's `timeout:` (seconds). Message
  # `Request timed out after <ms>ms`.
  class TimeoutError < Error
    attr_reader :timeout

    def initialize(timeout:, cause: nil)
      super(format(Internal::Constants::MESSAGE_TIMEOUT, timeout_ms: (timeout * 1000).round),
            code: "timeout", status: nil, request_id: nil, cause: cause)
      @timeout = timeout
    end

    def payload_status
      504
    end
  end

  # `DOWNLOAD_FAILED`: the presigned-URL download failed. With the storage's
  # `status` when it answered (`Failed to download PDF: HTTP <status>`),
  # without one when no complete answer came (`Failed to download PDF:
  # network error`, the HTTP library's exception as {#cause}). Never retried.
  class DownloadError < Error
    def initialize(status: nil, cause: nil, message: nil)
      message ||= if status
                    format(Internal::Constants::MESSAGE_DOWNLOAD_FAILED, status: status)
                  else
                    Internal::Constants::MESSAGE_DOWNLOAD_FAILED_NETWORK
                  end
      super(message, code: "DOWNLOAD_FAILED", status: status, request_id: nil, cause: cause)
    end
  end

  class InternalError < Error
    def initialize(message, status: nil, cause: nil)
      super(message, code: "INTERNAL_ERROR", status: status, request_id: nil, cause: cause)
    end
  end

  # Known API codes, with the HTTP status the API answers them with. The
  # list is not a closed set: `Error#code` is whatever string the API
  # returns, and new codes appear without an SDK release. Note:
  # `STORAGE_REQUIRED` was retired from the deployed API and is NOT exported.
  module ErrorCodes
    MISSING_API_KEY               = "MISSING_API_KEY"               # 401
    INVALID_API_KEY               = "INVALID_API_KEY"               # 401
    ORGANIZATION_PAYMENT_GRACE    = "ORGANIZATION_PAYMENT_GRACE"    # 403
    ORGANIZATION_CANCELLED        = "ORGANIZATION_CANCELLED"        # 403
    FORBIDDEN                     = "FORBIDDEN"                     # 403
    ENVIRONMENT_PROTECTED         = "ENVIRONMENT_PROTECTED"         # 403
    THUMBNAILS_NOT_AVAILABLE      = "THUMBNAILS_NOT_AVAILABLE"      # 403
    VALIDATION_ERROR              = "VALIDATION_ERROR"              # 400
    MISSING_DATA                  = "MISSING_DATA"                  # 400
    MISSING_TEMPLATE_SLUG         = "MISSING_TEMPLATE_SLUG"         # 400
    PROJECT_REQUIRED_FOR_DOCUMENT = "PROJECT_REQUIRED_FOR_DOCUMENT" # 400
    TEMPLATE_ERROR                = "TEMPLATE_ERROR"                # 400
    TEMPLATE_UNSAFE               = "TEMPLATE_UNSAFE"               # 400
    EMPTY_DOCUMENT                = "EMPTY_DOCUMENT"                # 400
    ENVIRONMENT_MISMATCH          = "ENVIRONMENT_MISMATCH"          # 400
    NOT_FOUND                     = "NOT_FOUND"                     # 404
    PROJECT_NOT_FOUND             = "PROJECT_NOT_FOUND"             # 404
    PROJECT_NOT_IN_ENVIRONMENT    = "PROJECT_NOT_IN_ENVIRONMENT"    # 404
    TEMPLATE_NOT_FOUND            = "TEMPLATE_NOT_FOUND"            # 404
    DOCUMENT_NOT_FOUND            = "DOCUMENT_NOT_FOUND"            # 404
    DOCUMENT_GONE                 = "DOCUMENT_GONE"                 # 410
    ORGANIZATION_PURGED           = "ORGANIZATION_PURGED"           # 410
    RENDER_BODY_TOO_LARGE         = "RENDER_BODY_TOO_LARGE"         # 413
    DOCUMENT_TOO_LARGE            = "DOCUMENT_TOO_LARGE"            # 413
    RATE_LIMIT_EXCEEDED           = "RATE_LIMIT_EXCEEDED"           # 429
    QUOTA_EXCEEDED                = "QUOTA_EXCEEDED"                # 429
    OVERAGE_CAP_EXCEEDED          = "OVERAGE_CAP_EXCEEDED"          # 429
    INTERNAL_ERROR                = "INTERNAL_ERROR"                # 500
    STORAGE_ACCESS_DENIED         = "STORAGE_ACCESS_DENIED"         # 502
    PUBLISH_IN_PROGRESS           = "PUBLISH_IN_PROGRESS"           # 503
    ORGANIZATION_MIGRATING        = "ORGANIZATION_MIGRATING"        # 503
    RENDER_TIMEOUT                = "RENDER_TIMEOUT"                # 504
  end
end
