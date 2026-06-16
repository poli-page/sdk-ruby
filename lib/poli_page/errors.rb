# frozen_string_literal: true

module PoliPage
  # Base for all SDK-raised errors. Inherits from `StandardError` so that
  # `rescue => e` catches it (whereas inheriting from `Exception` would
  # bypass the default rescue and surprise callers).
  #
  # The rescue-friendly path is the class hierarchy
  # (`rescue PoliPage::AuthenticationError`); the predicate methods below are
  # kept for spec parity with the Node SDK and for callers who want a single
  # rescue clause backed by introspection.
  class Error < StandardError
    attr_reader :code, :status, :request_id

    def initialize(message = nil, code:, status: nil, request_id: nil)
      super(message)
      @code       = code
      @status     = status
      @request_id = request_id
    end

    def auth_error?
      is_a?(AuthenticationError) || is_a?(PermissionDeniedError)
    end

    def rate_limit_error?
      is_a?(RateLimitError)
    end

    def validation_error?
      is_a?(ValidationError)
    end

    def network_error?
      is_a?(ConnectionError) || is_a?(TimeoutError)
    end

    def retryable?
      return true if network_error?
      return true if status && (status >= 500 || status == 429)

      false
    end

    # Canonical wire payload for framework integrations:
    # {code:, message:, status:, request_id:}. `status` surfaces 503 for
    # connection failures, 504 for timeouts, the API HTTP status for
    # status-bearing errors. The {#status} reader itself stays nil for
    # transport-error instances — only the payload surfaces 503/504.
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

  class InvalidOptionsError < Error
    def initialize(message, code: "invalid_options")
      super(message, code: code, status: nil, request_id: nil)
    end
  end

  class ConnectionError < Error
    attr_reader :cause

    def initialize(message:, cause: nil)
      super(message, code: "network_error", status: nil, request_id: nil)
      @cause = cause
    end

    def payload_status
      503
    end
  end

  class TimeoutError < Error
    attr_reader :timeout

    def initialize(timeout:)
      super("request timed out after #{timeout}s",
            code: "timeout", status: nil, request_id: nil)
      @timeout = timeout
    end

    def payload_status
      504
    end
  end

  class DownloadError < Error
    def initialize(message:, status: nil)
      super(message, code: "DOWNLOAD_FAILED", status: status, request_id: nil)
    end
  end

  class InternalError < Error
    def initialize(message, status: nil)
      super(message, code: "INTERNAL_ERROR", status: status, request_id: nil)
    end
  end

  # Known API codes (sdk-ruby-plan.md §7.4). The SDK passes through whatever
  # the API returns — callers may still see codes not in this list. Note:
  # `STORAGE_REQUIRED` was retired from the deployed API and is NOT exported.
  module ErrorCodes
    MISSING_API_KEY               = "MISSING_API_KEY"
    INVALID_API_KEY               = "INVALID_API_KEY"
    PAYMENT_REQUIRED              = "PAYMENT_REQUIRED"
    FORBIDDEN                     = "FORBIDDEN"
    ORGANIZATION_CANCELLED        = "ORGANIZATION_CANCELLED"
    ORGANIZATION_PURGED           = "ORGANIZATION_PURGED"
    NOT_FOUND                     = "NOT_FOUND"
    VERSION_NOT_FOUND             = "VERSION_NOT_FOUND"
    DOCUMENT_NOT_FOUND            = "DOCUMENT_NOT_FOUND"
    GONE                          = "GONE"
    VALIDATION_ERROR              = "VALIDATION_ERROR"
    MISSING_DATA                  = "MISSING_DATA"
    MISSING_PROJECT_OR_TEMPLATE   = "MISSING_PROJECT_OR_TEMPLATE"
    MISSING_TEMPLATE_SLUG         = "MISSING_TEMPLATE_SLUG"
    PROJECT_REQUIRED_FOR_DOCUMENT = "PROJECT_REQUIRED_FOR_DOCUMENT"
    INVALID_VERSION_FORMAT        = "INVALID_VERSION_FORMAT"
    VERSION_REQUIRED              = "VERSION_REQUIRED"
    INVALID_VERSION_FOR_KEY_ENV   = "INVALID_VERSION_FOR_KEY_ENV"
    QUOTA_EXCEEDED                = "QUOTA_EXCEEDED"
    OVERAGE_CAP_EXCEEDED          = "OVERAGE_CAP_EXCEEDED"
    INTERNAL_ERROR                = "INTERNAL_ERROR"
  end
end
