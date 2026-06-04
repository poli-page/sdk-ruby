# frozen_string_literal: true

module PoliPage
  # Event payload for the `on_retry` constructor hook (sdk-ruby-plan.md §10.2).
  #
  # - `attempt`  [Integer]         1-based — the attempt about to be made.
  # - `delay_ms` [Integer]         sleep duration in milliseconds before this
  #                                attempt. Canonical units across the SDK fleet
  #                                (Plan 0 / roadmap D3).
  # - `reason`   [PoliPage::Error] error that triggered the retry.
  RetryEvent = Data.define(:attempt, :delay_ms, :reason)
end
