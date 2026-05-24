# frozen_string_literal: true

module PoliPage
  # Event payload for the `on_retry` constructor hook (sdk-ruby-plan.md §10.2).
  #
  # - `attempt` [Integer] 1-based — the attempt about to be made.
  # - `delay`   [Float]   sleep duration in seconds before this attempt.
  # - `reason`  [PoliPage::Error] error that triggered the retry.
  RetryEvent = Data.define(:attempt, :delay, :reason)
end
