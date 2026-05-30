# frozen_string_literal: true

module RuntimeSupportPage
  module_function

  def build(gem_version)
    <<~MDX
      ---
      title: Runtime support
      description: Supported Ruby versions and operating systems for poli-page v#{gem_version}.
      ---

      import RuntimeMatrix from '@preset/components/RuntimeMatrix.astro';

      The Ruby SDK is built and tested against the matrix below.

      <RuntimeMatrix matrix={{
        runtimes: ['3.2', '3.3', '3.4'],
        os: ['linux', 'macos', 'windows'],
        cells: {
          '3.2': { linux: 'tested', macos: 'tested', windows: 'supported' },
          '3.3': { linux: 'tested', macos: 'tested', windows: 'supported' },
          '3.4': { linux: 'tested', macos: 'tested', windows: 'supported' },
        },
      }} />

      The minimum supported Ruby version is **3.2**. The gem has zero runtime dependencies — only the Ruby stdlib (`net/http`, `json`, `uri`, `securerandom`, `logger`, `openssl`).

      ## Implementations other than CRuby

      The SDK is CRuby/MRI-first. JRuby 9.4+ is supported on a best-effort basis (CI does not run it). TruffleRuby has not been validated. File an issue if you hit a runtime-specific problem.
    MDX
  end
end
