# frozen_string_literal: true

# Build `reference/client.mdx` — the `PoliPage::Client` overview.
module ClientPage
  module_function

  def build
    cls  = YARD::Registry.at("PoliPage::Client")
    lede =
      if cls && !cls.docstring.empty?
        first_paragraph(cls.docstring.to_s)
      else
        "The Poli Page client — the single entry point to the Ruby SDK."
      end

    <<~MDX
      ---
      title: Client
      description: The PoliPage::Client class — the only entry point to the Ruby SDK.
      ---

      import MethodSignature from '@preset/components/MethodSignature.astro';

      <MethodSignature lang="ruby" code={`PoliPage::Client.new(api_key:, base_url: ..., max_retries: 2, retry_delay: 0.5, timeout: 60, logger: nil, on_retry: nil, on_error: nil, proxy: nil, ca_file: nil, ca_path: nil)`} />

      #{lede}

      ## Constructor

      The constructor takes a required `api_key:` plus a set of optional keyword arguments — see [Configuration](../../concepts/configuration/) for every field, or [`PoliPage::Client`](../types/) for the typed reference. The same client is safe to share across threads; build one at boot and reuse it.

      ## Resource namespaces

      The client exposes two resource namespaces:

      - [`client.render`](./methods/render-pdf/) — render PDFs (in memory, streaming, or as a stored document).
      - [`client.documents`](./methods/documents-get/) — fetch, preview, thumbnail, or delete stored documents.

      The standalone helper [`client.render_to_file`](./methods/render-to-file/) is defined directly on `PoliPage::Client`.

      ## See also
      - [Types](../types/)
      - [Errors](../errors/)
      - [Runtime support](../runtime-support/)
    MDX
  end

  def first_paragraph(doc)
    para = doc.to_s.split(/\n\s*\n/, 2).first.to_s.strip
    para.empty? ? "The Poli Page Ruby SDK client." : para
  end
end
