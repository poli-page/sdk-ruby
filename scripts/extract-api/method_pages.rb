# frozen_string_literal: true

require "json"

# Build one MDX page per public SDK method.
module MethodPages
  module_function

  HERE      = File.expand_path(__dir__)
  REPO_ROOT = File.expand_path("../..", HERE)
  EXAMPLES  = File.join(REPO_ROOT, "examples")

  # Each entry maps to a YARD path + a slug + an example file. The example
  # file MUST exist; the extractor fails if it doesn't (spec §4b).
  METHODS = [
    {
      slug: "render-pdf",
      display: "client.render.pdf",
      yard_path: "PoliPage::Resources::Render#pdf",
      example: "render-pdf.rb",
      error_classes: %w[
        ValidationError NotFoundError RateLimitError TimeoutError
        ConnectionError DownloadError InternalError APIError
      ]
    },
    {
      slug: "render-pdf-stream",
      display: "client.render.pdf_stream",
      yard_path: "PoliPage::Resources::Render#pdf_stream",
      example: "render-pdf-stream.rb",
      error_classes: %w[
        ValidationError NotFoundError RateLimitError TimeoutError
        ConnectionError DownloadError InternalError APIError
      ]
    },
    {
      slug: "render-preview",
      display: "client.render.preview",
      yard_path: "PoliPage::Resources::Render#preview",
      example: "render-preview.rb",
      error_classes: %w[
        ValidationError NotFoundError AuthenticationError RateLimitError
        InternalError APIError
      ]
    },
    {
      slug: "render-document",
      display: "client.render.document",
      yard_path: "PoliPage::Resources::Render#document",
      example: "render-document.rb",
      error_classes: %w[
        ValidationError NotFoundError RateLimitError InternalError APIError
      ]
    },
    {
      slug: "documents-get",
      display: "client.documents.get",
      yard_path: "PoliPage::Resources::Documents#get",
      example: "documents-get.rb",
      error_classes: %w[NotFoundError GoneError AuthenticationError InternalError APIError]
    },
    {
      slug: "documents-preview",
      display: "client.documents.preview",
      yard_path: "PoliPage::Resources::Documents#preview",
      example: "documents-preview.rb",
      error_classes: %w[NotFoundError GoneError AuthenticationError InternalError APIError]
    },
    {
      slug: "documents-thumbnails",
      display: "client.documents.thumbnails",
      yard_path: "PoliPage::Resources::Documents#thumbnails",
      example: "documents-thumbnails.rb",
      error_classes: %w[
        NotFoundError ValidationError PermissionDeniedError AuthenticationError
        InternalError APIError
      ]
    },
    {
      slug: "documents-delete",
      display: "client.documents.delete",
      yard_path: "PoliPage::Resources::Documents#delete",
      example: "documents-delete.rb",
      error_classes: %w[NotFoundError GoneError AuthenticationError InternalError APIError]
    },
    {
      slug: "render-to-file",
      display: "client.render_to_file",
      yard_path: "PoliPage::Client#render_to_file",
      example: "render-to-file.rb",
      error_classes: %w[
        InvalidOptionsError ValidationError NotFoundError RateLimitError
        TimeoutError ConnectionError DownloadError InternalError APIError
      ]
    }
  ].freeze

  def build
    METHODS.map do |m|
      example_path = File.join(EXAMPLES, m[:example])
      unless File.exist?(example_path)
        raise "extractor: missing example file #{example_path} for #{m[:display]}"
      end

      meth = YARD::Registry.at(m[:yard_path])
      raise "extractor: YARD path not found: #{m[:yard_path]}" if meth.nil?

      [m[:slug], render_page(m, meth, File.read(example_path))]
    end
  end

  def render_page(target, meth, example)
    description = first_sentence(meth.docstring.to_s)
    description = "#{target[:display]} method." if description.empty?

    parameters = parameter_rows(meth)
    return_lines = return_lines_for(meth)

    parameters_block =
      if parameters.empty?
        ""
      else
        "\n## Parameters\n\n<ParamsTable params={#{JSON.generate(parameters)}} />\n"
      end

    returns_block =
      if return_lines.empty?
        ""
      else
        "\n## Returns\n\n#{return_lines.join("\n\n")}\n"
      end

    errors_block =
      if target[:error_classes].empty?
        ""
      else
        rows = target[:error_classes].map do |klass|
          { code: "PoliPage::#{klass}", when: "See [errors](../../../production/errors/) for the full description." }
        end
        "\n## Errors\n\n<ErrorTable errors={#{JSON.generate(rows)}} />\n"
      end

    desc_line = escape_frontmatter(description)
    signature = render_signature(target[:display], meth)
    lede      = first_paragraph(meth.docstring.to_s)
    lede      = description if lede.empty?

    <<~MDX
      ---
      title: #{quote_yaml(target[:display])}
      description: #{quote_yaml(desc_line)}
      sidebar:
        label: #{quote_yaml(target[:display])}
      ---

      import MethodSignature from '@preset/components/MethodSignature.astro';
      import ParamsTable from '@preset/components/ParamsTable.astro';
      import ErrorTable from '@preset/components/ErrorTable.astro';

      <MethodSignature lang="ruby" code={`#{signature}`} />

      #{lede}
      #{parameters_block}#{returns_block}#{errors_block}
      ## Example

      ```ruby
      #{example.rstrip}
      ```

      ## See also
      - [Errors](../../../production/errors/)
      - [Configuration](../../../concepts/configuration/)
    MDX
  end

  def parameter_rows(meth)
    param_tags = meth.tags(:param)
    return [] if param_tags.empty?

    # YARD's `meth.parameters` exposes the kwarg list as [["name:", default], …].
    # Required kwargs come back with a nil default (no source-level expression).
    # Optional kwargs come back with the source token as a string (e.g. "nil",
    # "60", "Internal::Constants::DEFAULT_TIMEOUT").
    defaults = {}
    Array(meth.parameters).each do |name, default|
      next unless name.to_s.end_with?(":")

      key = name.to_s.delete_suffix(":")
      defaults[key] = default
    end

    param_tags.map do |tag|
      name = tag.name.to_s
      types = Array(tag.types).join(", ")
      types = "Object" if types.empty?
      required = defaults.key?(name) && defaults[name].nil?
      default_str = defaults[name]

      row = {
        name: name,
        type: types,
        required: required,
        description: tag.text.to_s.strip.empty? ? "(no description)" : tag.text.to_s.strip
      }
      row[:default] = default_str if default_str && default_str != "nil"
      row
    end
  end

  def return_lines_for(meth)
    meth.tags(:return).map do |tag|
      types = Array(tag.types).map { |t| "`#{t}`" }.join(", ")
      desc = tag.text.to_s.strip
      desc.empty? ? types : "#{types} — #{desc}"
    end
  end

  def render_signature(display_name, meth)
    params = Array(meth.parameters).map do |name, default|
      key = name.to_s
      if key.end_with?(":")
        default.nil? ? key : "#{key.delete_suffix(':')}: #{default}"
      else
        # positional
        default.nil? ? key : "#{key} = #{default}"
      end
    end
    "#{display_name}(#{params.join(', ')})"
  end

  def first_sentence(doc)
    flat = doc.to_s.gsub(/\s+/, " ").strip
    return "" if flat.empty?

    dot = flat.index(/(?<=\.)\s/)
    sentence = dot ? flat[0..dot] : flat
    sentence.strip
  end

  def first_paragraph(doc)
    para = doc.to_s.split(/\n\s*\n/, 2).first.to_s.strip
    para
  end

  def escape_frontmatter(str)
    flat = str.to_s.gsub(/\s+/, " ").strip
    flat.length > 150 ? flat[0, 147] + "..." : flat
  end

  # Wrap any value that contains YAML-sensitive characters (':', '#', '"', '[',
  # '{', etc.) in double quotes, escaping embedded quotes. Letters, digits, and
  # dot-separated identifiers pass through untouched so simple titles like
  # `client.render.pdf` stay readable.
  def quote_yaml(str)
    plain = str.to_s
    return plain if plain.match?(/\A[A-Za-z0-9_.\- ]+\z/)

    "\"#{plain.gsub('\\', '\\\\').gsub('"', '\\"')}\""
  end
end
