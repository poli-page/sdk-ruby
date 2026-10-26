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
    # `{code:, message:, status:, request_id:}`. `status` surfaces 503 for
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
