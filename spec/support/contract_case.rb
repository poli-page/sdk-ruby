# frozen_string_literal: true

module PoliPageContract
  # One run of one `kind: "sdk"` case: a mock server answering the case's
  # `responses`, a client built with its `options`, the call, and what was
  # observed (recorded requests, `on_request` / `on_retry` events, result).
  class CaseRun
    # sdk-specification.md §7.1, the descriptor fields (N-DESCRIPTOR): wire
    # name to reader (§2: Ruby casing).
    DESCRIPTOR_FIELDS = {
      "documentId" => :document_id, "organizationId" => :organization_id, "projectId" => :project_id,
      "projectSlug" => :project_slug, "templateId" => :template_id, "templateSlug" => :template_slug,
      "environment" => :environment, "apiKeyId" => :api_key_id, "format" => :format,
      "orientation" => :orientation, "locale" => :locale, "pageCount" => :page_count,
      "sizeBytes" => :size_bytes, "createdAt" => :created_at, "metadata" => :metadata,
      "presignedPdfUrl" => :presigned_pdf_url, "expiresAt" => :expires_at
    }.freeze

    THUMBNAIL_FIELDS = {
      "page" => :page, "width" => :width, "height" => :height, "contentType" => :content_type, "data" => :data
    }.freeze

    UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

    attr_reader :origin, :result, :events, :recorded

    def initialize(kase)
      @case = kase
      @api_key = kase.fetch("apiKey", TEST_API_KEY)
      @stop_after = kase["stopAfterRetryEvents"]
      @events = []
      @retries = 0
    end

    def run
      check_runnable!
      server = start_server
      begin
        @result = invoke
      ensure
        server.close
      end
      raise server.errors.first if server.errors.any?

      @recorded = server.requests
      self
    end

    # The recorded requests in the shape of `expected`. A field that breaks
    # the expectation keeps the observed value, so the diff shows it.
    def describe_requests(expected)
      first_key = @recorded.map { |request| request.headers["idempotency-key"] }.find { |key| key&.match?(UUID_V4) }
      @recorded.each_with_index.map do |request, index|
        describe_request(request, index, expected[index] || {}, first_key)
      end
    end

    # The observed events, a delay inside an expected `{min, max}` range
    # shown as that range.
    def describe_events(expected)
      @events.each_with_index.map do |event, index|
        range = expected.dig(index, "delayMs")
        next event unless event["type"] == "retry" && range.is_a?(Hash)
        next event unless range["min"] <= event["delayMs"] && event["delayMs"] < range["max"]

        event.merge("delayMs" => range)
      end
    end

    private

    def check_runnable!
      if @case["call"].key?("cancelAfterMs")
        raise ContractError, "this SDK has no cancellation: cancelAfterMs cannot run"
      end

      PoliPageContract.substitute(@case, "http://127.0.0.1") # an unknown placeholder fails before any request
    end

    def start_server
      server = PoliPageSpec::MockHTTPServer.new(@case.fetch("responses"),
                                                render: ->(value) { PoliPageContract.substitute(value, server.origin) })
      @origin = server.origin
      server
    end

    def describe_request(request, index, want, first_key)
      item = { "method" => request.verb, "path" => request.target, "auth" => auth(request),
               "idempotencyKey" => idempotency(request.headers["idempotency-key"], first_key) }
      item["json"] = json_body(request) if want.key?("json")
      item["minGapMsBefore"] = gap(index, want["minGapMsBefore"]) if want.key?("minGapMsBefore")
      item
    end

    def invoke
      catch(:poli_contract_stop) do
        client = PoliPage::Client.new(**client_options)
        { "ok" => true, "value" => call(client) }
      rescue ContractError
        raise
      rescue StandardError => e
        { "ok" => false, "error" => normalize_error(e) }
      end
    end

    def client_options
      options = @case.fetch("options")
      {
        api_key: @api_key, base_url: @origin,
        max_retries: options.fetch("maxRetries"),
        retry_delay: options.fetch("retryDelayMs") / 1000.0,
        timeout: options.fetch("timeoutMs") / 1000.0,
        on_request: ->(event) { @events << { "type" => "request", "attempt" => event.attempt } },
        on_retry: method(:on_retry)
      }
    end

    # `delay_ms` is already integer milliseconds (N-DURATION-MS). The SDK has
    # no cancellation: the call is abandoned with `throw`, which the SDK's
    # hook guard (`rescue StandardError`) lets through.
    def on_retry(event)
      @events << { "type" => "retry", "attempt" => event.attempt, "delayMs" => event.delay_ms }
      @retries += 1
      throw :poli_contract_stop if @retries == @stop_after
    end

    def call(client)
      method = @case.dig("call", "method")
      args = PoliPageContract.substitute(@case.dig("call", "args"), @origin)
      invoker = INVOKERS.fetch(method) { raise ContractError, "unknown SDK method in the contract: #{method}" }
      instance_exec(client, args, &invoker)
    end

    INVOKERS = {
      "render.pdf" => ->(client, args) { bytes(client.render.pdf(**kwargs(args, 0))) },
      "render.pdfStream" => lambda do |client, args|
        body = +""
        client.render.pdf_stream(**kwargs(args, 0)) { |chunk| body << chunk }
        bytes(body)
      end,
      "render.document" => ->(client, args) { descriptor(client.render.document(**kwargs(args, 0))) },
      "documents.get" => ->(client, args) { descriptor(client.documents.get(string_arg(args, 0))) },
      "documents.preview" => ->(client, args) { preview(client.documents.preview(string_arg(args, 0))) },
      "documents.thumbnails" => lambda do |client, args|
        thumbnails(client.documents.thumbnails(string_arg(args, 0), **kwargs(args, 1)))
      end,
      "documents.delete" => lambda do |client, args|
        client.documents.delete(string_arg(args, 0))
        nil # N-DELETE-NULL
      end
    }.freeze
    private_constant :INVOKERS

    # An input object as Ruby keyword arguments: its top-level keys in Ruby
    # casing (§2), nested values unchanged.
    def kwargs(args, index)
      value = args[index]
      return {} if value.nil?
      raise ContractError, "call.args[#{index}] must be an object" unless value.is_a?(Hash)

      value.to_h { |key, item| [PoliPage::Internal::Wire.camel_to_snake(key).to_sym, item] }
    end

    def string_arg(args, index)
      value = args[index]
      raise ContractError, "call.args[#{index}] must be a string" unless value.is_a?(String)

      value
    end

    # N-BYTES.
    def bytes(data)
      { "sha256" => Digest::SHA256.hexdigest(data), "length" => data.bytesize }
    end

    # N-DESCRIPTOR. `metadata` goes back through the SDK's own key translation
    # (`Wire.to_wire`, the inverse of the `from_wire` it applied), so a key
    # that does not survive the round trip shows in the diff.
    def descriptor(value)
      fields = DESCRIPTOR_FIELDS.transform_values { |reader| value.public_send(reader) }
      fields.merge("metadata" => PoliPage::Internal::Wire.to_wire(value.metadata))
    end

    # N-PREVIEW.
    def preview(value)
      { "html" => value.html, "pageCount" => value.page_count }
    end

    # N-THUMBS-ARRAY: the SDK already returns the unwrapped array.
    def thumbnails(value)
      value.map { |thumb| THUMBNAIL_FIELDS.transform_values { |reader| thumb.public_send(reader) } }
    end

    # N-STATUS-NULL, N-REQID-NULL: `status` and `request_id` are already nil
    # when absent. Anything that is not a PoliPage::Error shows in the diff.
    def normalize_error(error)
      return foreign_error(error) unless error.is_a?(PoliPage::Error)

      {
        "code" => error.code, "status" => error.status, "message" => error.message,
        "requestId" => error.request_id, "retryable" => error.retryable?,
        "isAuthError" => error.auth_error?, "isRateLimitError" => error.rate_limit_error?,
        "isValidationError" => error.validation_error?, "isNetworkError" => error.network_error?
      }
    end

    def foreign_error(error)
      {
        "code" => "not a PoliPage::Error", "status" => nil, "message" => "#{error.class}: #{error.message}",
        "requestId" => nil, "retryable" => false, "isAuthError" => false, "isRateLimitError" => false,
        "isValidationError" => false, "isNetworkError" => false
      }
    end

    def auth(request)
      authorization = request.headers["authorization"]
      return "none" if authorization.nil?
      return "bearer" if authorization == "Bearer #{@api_key}"

      "unexpected Authorization: #{authorization}"
    end

    def idempotency(key, first_key)
      return "absent" if key.nil?
      return "not a lowercase UUID v4: #{key}" unless key.match?(UUID_V4)
      return "stable" if key == first_key

      "changed: #{first_key} then #{key}"
    end

    def json_body(request)
      JSON.parse(request.body)
    rescue JSON::ParserError
      "body is not JSON: #{request.body.inspect}"
    end

    # N-DURATION-MS: the gap is compared in integer milliseconds, so a timer
    # waking a fraction of a millisecond early is not a short wait.
    def gap(index, min_gap)
      gap_ms = index.positive? ? ((@recorded[index].at - @recorded[index - 1].at) * 1000).round : 0
      gap_ms >= min_gap ? min_gap : "only #{gap_ms} ms"
    end
  end

  # (events, requests, check_result) of `kase`, cut at its
  # `stopAfterRetryEvents`-th retry event: compare those, not the result.
  def self.expected_prefix(kase)
    events = kase.dig("expect", "events")
    requests = kase.dig("expect", "requests")
    stop = kase["stopAfterRetryEvents"]
    return [events, requests, true] if stop.nil?

    cut = events[0..retry_event_index(events, stop)]
    [cut, requests.first(cut.count { |event| event["type"] == "request" }), false]
  end

  def self.retry_event_index(events, stop)
    indexes = events.each_index.select { |index| events[index]["type"] == "retry" }
    indexes[stop - 1] or raise ContractError, "stopAfterRetryEvents #{stop}: the case has fewer retries"
  end
end
