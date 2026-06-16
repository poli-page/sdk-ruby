# frozen_string_literal: true

module PoliPage
  # Event payload for the `on_request` constructor hook. Fired immediately
  # before each HTTP attempt — including the first one and every retry.
  # Parity with sdk-node `RequestEvent` (src/types.ts:171-175).
  #
  # - `method`  [String]  uppercase HTTP verb ("GET" / "POST" / "DELETE").
  # - `url`     [String]  fully-resolved request URL (base_url + path).
  # - `attempt` [Integer] 1-based attempt counter — first send is `1`, the
  #                       first retry is `2`, etc.
  #
  # Naming `:method` shadows `Object#method`, but the field name is fixed by
  # Node-SDK parity (`RequestEvent.method` is the public payload shape).
  # Callers won't reach for `event.method(:foo)` on a value-typed event.
  RequestEvent = Data.define(:method, :url, :attempt) # rubocop:disable Lint/DataDefineOverride
end
