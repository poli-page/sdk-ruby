# Contributing to `poli-page`

Thanks for your interest. A few short rules:

## Working method

We use **TDD**: write a failing spec first, then the minimum code to pass.

The Node SDK (`@poli-page/sdk` at
[github.com/poli-page/sdk-node](https://github.com/poli-page/sdk-node)) is
the behavioural reference. When in doubt, port the Node test 1:1 and
preserve byte-for-byte behaviour parity.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

## Local development

```bash
bundle install
bundle exec rake          # rubocop + rbs validate + steep check + rspec
bundle exec rspec         # unit specs only
bundle exec rubocop       # lint
bundle exec steep check   # type-check against sig/*.rbs
bundle exec rbs validate  # validate sig/ syntax
bundle exec yard          # docs to doc/
bundle exec bundle-audit  # advisory scan
```

Run all of the above before pushing — `scripts/install-hooks.sh` writes a
`pre-push` hook that runs the same gates locally on every push.

```bash
./scripts/install-hooks.sh
```

## API contract tests

`spec/contract` checks the SDK against the
[Poli Page API contract](https://github.com/poli-page/api-contract): every
`sdk` case runs against a local mock server over real sockets, and compares
the requests, the `on_request` / `on_retry` events and the result with the
case. CI runs them against the contract version pinned in
`.github/workflows/ci.yml`; Dependabot proposes each new version as a PR. To
run them locally, download that version's `contract.json` and point
`POLI_CONTRACT` at it:

```bash
curl -fsSLo /tmp/contract.json \
  https://raw.githubusercontent.com/poli-page/api-contract/<pinned sha>/contract.json
POLI_CONTRACT=/tmp/contract.json bundle exec rspec
```

Without `POLI_CONTRACT` the suite is pending locally and fails in CI.
`spec/contract-skip.json` lists the case ids allowed to fail, each with its
reason; a listed case that passes fails the run until it is removed.

## Integration tests

Integration tests hit the live API. They're skipped by default; opt in
with `INTEGRATION=1`:

```bash
export POLI_PAGE_API_KEY=pp_sandbox_...   # a sandbox key; the specs render getting-started/welcome
INTEGRATION=1 bundle exec rspec spec/integration
```

## Adding a public method

1. Port the corresponding test from `sdk-node/tests/` into a new spec
   under `spec/poli_page/`. Watch it fail.
2. Implement the minimum to make it pass.
3. Add YARD `@param` / `@return` / `@raise` / `@example` blocks.
4. Add the matching RBS signature in `sig/poli_page/` and run
   `bundle exec steep check`.
5. Update `README.md` (Methods table) and `CHANGELOG.md` (`[Unreleased]`).

## Releasing

See `scripts/release.sh`. Releases are gated
on `main`, a clean tree, and the full local CI suite. The maintainer runs
the script, confirms at the prompt, and the tag is pushed only **after**
`gem push` succeeds.
