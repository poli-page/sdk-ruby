# frozen_string_literal: true

# Shared helpers for examples/demo.rb. Ports sdk-node/demo/_shared.mjs.
#
# Resolves the API key in this order:
#   1. ENV["POLI_PAGE_API_KEY"] (host shell wins, useful in CI).
#   2. `examples/.env` (the canonical project file — survives across runs).
#   3. Interactive prompt. On a successful paste the key is appended to
#      `examples/.env` so future runs skip the prompt.
#
# Resolves the base URL the same way without the prompt — defaulting to
# `https://api.poli.page`.

require "fileutils"
require "pathname"

module Demo
  ENV_FILE = Pathname(__dir__).join(".env").freeze

  USE_COLOR = $stdout.tty? && ENV["NO_COLOR"] != "1"

  module_function

  # ─ Tiny ANSI helpers ──────────────────────────────────────────────────────
  def colorize(code, text)
    USE_COLOR ? "\e[#{code}m#{text}\e[0m" : text.to_s
  end

  def bold(text)   = colorize("1", text)
  def dim(text)    = colorize("2", text)
  def red(text)    = colorize("31", text)
  def green(text)  = colorize("32", text)
  def yellow(text) = colorize("33", text)
  def cyan(text)   = colorize("36", text)

  def step(index, total, name)
    puts
    puts cyan(bold("[#{index}/#{total}] #{name}"))
  end

  def file_link(path)
    cyan("file://#{File.expand_path(path)}")
  end

  # ─ .env parsing (~20 LOC; no `dotenv` dep) ────────────────────────────────
  def read_env_file(path)
    return {} unless File.exist?(path)

    result = {}
    File.foreach(path) do |raw_line|
      line = raw_line.strip
      next if line.empty? || line.start_with?("#")

      eq = line.index("=")
      next unless eq

      key = line[0...eq].strip
      value = line[(eq + 1)..].to_s.strip
      if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
        value = value[1..-2]
      end
      result[key] = value
    end
    result
  end

  def append_to_env_file(path, key, value)
    existing = File.exist?(path) ? File.read(path) : ""
    needs_leading_newline = !existing.empty? && !existing.end_with?("\n")
    File.open(path, "a") do |io|
      io.write("\n") if needs_leading_newline
      io.write("#{key}=#{value}\n")
    end
  end

  # ─ Resolvers ──────────────────────────────────────────────────────────────
  def resolve_base_url
    return ENV["POLI_PAGE_BASE_URL"] if ENV["POLI_PAGE_BASE_URL"] && !ENV["POLI_PAGE_BASE_URL"].empty?

    from_file = read_env_file(ENV_FILE)["POLI_PAGE_BASE_URL"]
    return from_file if from_file && !from_file.empty?

    "https://api.poli.page"
  end

  def ensure_api_key
    return ENV["POLI_PAGE_API_KEY"] if ENV["POLI_PAGE_API_KEY"] && !ENV["POLI_PAGE_API_KEY"].empty?

    from_file = read_env_file(ENV_FILE)["POLI_PAGE_API_KEY"]
    if from_file && !from_file.empty?
      puts dim("  using POLI_PAGE_API_KEY from #{ENV_FILE}")
      return from_file
    end

    print_api_key_help
    key = prompt_for_api_key
    append_to_env_file(ENV_FILE, "POLI_PAGE_API_KEY", key)
    puts "  #{green("✔")} saved to #{cyan(ENV_FILE.to_s)}"
    puts
    key
  end

  def print_api_key_help
    rule = dim("  ─────────────────────────────────────────────────────────────────────")
    puts
    puts rule
    puts bold(yellow("   No POLI_PAGE_API_KEY found."))
    puts rule
    puts
    puts "   This demo needs a test key (#{cyan("pp_test_*")}) to talk to the"
    puts "   Poli Page API. Test keys never bill or send real documents."
    puts
    puts bold("   How to get one:")
    puts "     1. Sign in at #{cyan("https://app.poli.page")}"
    puts "     2. Go to your organization's API keys page:"
    puts "          #{cyan("https://app.poli.page/orgs/{YOUR_ORG}/keys")}"
    puts dim("        (replace {YOUR_ORG} with your org slug — visible in the")
    puts dim("         dashboard URL when you're inside your organization)")
    puts "     3. Click \"Create key\" and copy the value (starts with #{cyan("pp_test_")})."
    puts
    puts "   Paste it below — we'll save it to #{cyan("examples/.env")} so future"
    puts "   runs pick it up automatically. (You can also set"
    puts "   #{dim("POLI_PAGE_API_KEY")} in your shell — that wins over the file.)"
    puts
  end

  def prompt_for_api_key
    print bold("   Paste your pp_test_* key") + " (or Ctrl-C to cancel): "
    key = $stdin.gets&.strip.to_s

    unless key.start_with?("pp_test_")
      warn
      warn "  #{red("✗")} Expected a key starting with `pp_test_`. Aborting."
      warn
      exit 1
    end
    key
  end
end
