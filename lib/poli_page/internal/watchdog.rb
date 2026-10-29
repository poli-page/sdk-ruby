# frozen_string_literal: true

require_relative "http"

module PoliPage
  module Internal
    # @api private
    #
    # Runs `on_expire` once, on its own thread, if {#disarm} is not called
    # within `seconds`. {Transport} uses it to close an attempt's connection at
    # the attempt's deadline: the request thread, blocked in a read or a write
    # on that socket, then gets an `IOError` at once, so no answer however
    # slowly it arrives can outlive the timeout. Closing the socket, unlike
    # `Timeout.timeout`, never raises inside arbitrary code of the request
    # thread.
    #
    # One short-lived thread per attempt; it ends as soon as the attempt does.
    class Watchdog
      def initialize(seconds, &on_expire)
        @mutex = Mutex.new
        @wakeup = ConditionVariable.new
        @done = false
        @fired = false
        deadline = HTTP.monotonic_now + seconds
        @thread = Thread.new { watch(deadline, on_expire) }
        @thread.name = "poli-page-timeout"
      end

      # Stops the watch. Once it returns, `on_expire` has either run to its
      # end or will never run.
      def disarm
        @mutex.synchronize do
          @done = true
          @wakeup.signal
        end
        @thread.join
        nil
      end

      # Whether `on_expire` ran.
      def fired?
        @mutex.synchronize { @fired }
      end

      private

      def watch(deadline, on_expire)
        @mutex.synchronize do
          until @done
            left = deadline - HTTP.monotonic_now
            if left.positive?
              @wakeup.wait(@mutex, left)
            else
              @fired = true
              expire(on_expire)
              break
            end
          end
        end
      end

      def expire(on_expire)
        on_expire.call
      rescue StandardError
        # The connection was already closing on its own: nothing left to stop.
        nil
      end
    end
  end
end
