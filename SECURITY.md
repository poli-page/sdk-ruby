# Security Policy

## Reporting a Vulnerability

Report suspected vulnerabilities **privately** to **security@poli.page**.

Please do **not** file a public GitHub issue, open a pull request that
demonstrates the flaw on `main`, or discuss the issue in public channels
until a fix has shipped.

Useful information to include:

- A short description of the issue and its impact.
- Affected versions (run `bundle info poli-page` or check `Gemfile.lock`).
- Reproduction steps or a proof-of-concept (minimal Ruby script
  preferred).
- Suggested remediation, if you have one.

GitHub's **private vulnerability reporting** is also enabled on this
repository — see
[Report a vulnerability](https://github.com/poli-page/sdk-ruby/security/advisories/new).
Either channel reaches the same maintainers.

## Response Timeline

| Stage                 | Target                                        |
| --------------------- | --------------------------------------------- |
| Acknowledgement       | within **2 business days** of the report      |
| Triage decision       | within **5 business days**                    |
| Fix released          | typically within **30 days** of triage        |
| Public advisory       | published alongside the fix release           |
| Coordinated disclosure| up to **90 days** by default; negotiable      |

We will keep the reporter informed at each stage and credit them in the
published advisory unless they prefer to remain anonymous.

## Supported Versions

Only the **latest minor version** of `poli-page` receives security
updates. Older minors do not receive backports — please upgrade.

| Version       | Supported          |
| ------------- | ------------------ |
| `1.x` (latest)| Yes                |
| `< 1.x`       | No                 |

## Scope

**In scope** — issues in code shipped by this gem:

- Credential leakage through logs, exceptions, or `#inspect` output.
- Request-forgery via SDK-constructed URLs, headers, or bodies.
- TLS / certificate validation defects in the transport layer.
- Retry / idempotency invariants that could cause unintended side effects.
- Denial-of-service via malformed API responses or unbounded resource use.
- Supply-chain integrity issues in the published `.gem` artifact.

**Out of scope:**

- Vulnerabilities in the deployed Poli Page API (`api.poli.page`) —
  report those at <https://poli.page/security>.
- Issues that require running the SDK against an untrusted Poli Page
  base URL (`base_url:` is a trust boundary; pointing the client at a
  malicious host is the caller's call).
- Issues in development-only dependencies (Gemfile group `:development,
  :test`) that do not ship in the published `.gem`.
- Findings from automated scanners without a demonstrated impact.

## Hardening This Project Applies

- **Zero runtime dependencies** — the SDK uses only the Ruby stdlib for
  HTTP, JSON, randomness, and TLS. The runtime attack surface is what
  ships with Ruby itself.
- **Lockfile committed and frozen in CI** — `Gemfile.lock` is checked
  in, and CI installs run with `bundle config set --local frozen true`.
- **Advisory scan in CI** — `bundle-audit check --update` runs on every
  push and PR.
- **CodeQL "security-and-quality" suite** — runs on push, PR, and
  weekly schedule.
- **GitHub Actions pinned to commit SHAs** — every third-party Action
  is pinned to a 40-character SHA, not a floating tag.
- **Dependabot** — weekly updates for `bundler` and `github-actions`.
- **MFA-required publishing** — the gemspec declares
  `rubygems_mfa_required: "true"`; the per-gem RubyGems API key is
  scoped to `poli-page` only.
- **Restricted workflow permissions** — every workflow declares the
  minimum `permissions:` block (most are `contents: read`).

## Verifying a Published Release

```sh
gem fetch poli-page -v <version>
gem unpack poli-page-<version>.gem
gem spec poli-page-<version>.gem
```

The unpacked `.gem` contains the full source — diff it against the
matching git tag on
[`github.com/poli-page/sdk-ruby`](https://github.com/poli-page/sdk-ruby)
to verify the published artifact matches the public history.
