# frozen_string_literal: true

module PoliPage
  # Event payload for the `on_response` constructor hook. Fired immediately
  # after a 2xx response is received from the transport (NOT fired on
  # non-2xx — those go through `on_retry` / `on_error` instead).
  # Parity with sdk-node `ResponseEvent` (src/types.ts:177-181).
  #
  # - `status`      [Integer]      HTTP status code (always 200-299).
  # - `request_id`  [String, nil]  value of the `x-request-id` response
  #                                header, or nil if the server didn't send one.
  # - `duration_ms` [Integer]      wall-clock duration of the HTTP attempt,
  #                                measured around `@transport.execute`.
  ResponseEvent = Data.define(:status, :request_id, :duration_ms)
end
