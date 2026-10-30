#!/usr/bin/env bash
# release.sh — local pre-flight and tag push for `poli-page`.
#
# This script does NOT publish the gem. Publishing is done by
# .github/workflows/release.yml, which runs on the pushed `vX.Y.Z` tag and
# pushes to RubyGems via Trusted Publishing, behind the `rubygems-release`
# environment's required-reviewer approval. No RubyGems credentials are
# needed (or used) here.
#
# Maintainer-driven: runs the checks below, prompts for confirmation, then
# creates and pushes the tag, which starts the workflow.
#
# Pre-flight:
#   - working tree clean
#   - on `main`
#   - HEAD is exactly `origin/main` (nothing unpushed, nothing behind)
#   - CHANGELOG.md has a `## [X.Y.Z]` section for the version
#   - target tag does not yet exist locally or on `origin`
#
# Verify (gates the release on local CI):
#   - bundle config set --local frozen true && bundle install
#   - bundle exec rubocop
#   - bundle exec rbs validate
#   - bundle exec rspec spec   (with the pinned API contract, see below)
#   - bundle exec yard --fail-on-warning
#   - bundle exec bundle-audit check --update
#   - INTEGRATION=1 bundle exec rspec spec/integration   (if POLI_PAGE_API_KEY set)
#   - ruby examples/demo.rb                              (smoke; optional, requires key)
#   - gem build poli-page.gemspec
#
# Pack inspect:
#   - gem unpack the built gem into a temp dir and show contents + size
#
# Tag (on confirmation):
#   - git tag vX.Y.Z && git push origin vX.Y.Z
#   - the release workflow then publishes after reviewer approval
#
# Flags:
#   --dry-run   Run everything except the tag push.
#   --skip-demo Skip the examples/demo.rb smoke (useful in CI-like contexts).

set -euo pipefail

DRY_RUN=0
SKIP_DEMO=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1 ;;
    --skip-demo) SKIP_DEMO=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# ─ helpers ───────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
  c_bold=$'\e[1m'; c_dim=$'\e[2m'; c_red=$'\e[31m'; c_green=$'\e[32m'
  c_yellow=$'\e[33m'; c_cyan=$'\e[36m'; c_reset=$'\e[0m'
else
  c_bold=""; c_dim=""; c_red=""; c_green=""; c_yellow=""; c_cyan=""; c_reset=""
fi

say()  { echo "${c_cyan}${c_bold}==>${c_reset} $*"; }
note() { echo "    ${c_dim}$*${c_reset}"; }
ok()   { echo "    ${c_green}✓${c_reset} $*"; }
fail() { echo "${c_red}✗${c_reset} $*" >&2; exit 1; }

# ─ extract version ───────────────────────────────────────────────────────
VERSION="$(ruby -r./lib/poli_page/version -e 'print PoliPage::VERSION')"
TAG="v${VERSION}"
GEM_FILE="poli-page-${VERSION}.gem"

say "Releasing ${c_bold}poli-page ${VERSION}${c_reset} (tag: ${TAG})"
[[ "$DRY_RUN" -eq 1 ]] && note "DRY RUN — will skip the tag push"
echo

# ─ pre-flight ────────────────────────────────────────────────────────────
say "Pre-flight"
branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || fail "must release from main (currently on '$branch')"
ok "on main"

[[ -z "$(git status --porcelain)" ]] || fail "working tree not clean — commit or stash first"
ok "working tree clean"

git fetch --quiet origin main || fail "could not fetch origin/main"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || fail "HEAD is not origin/main — push or pull first (the tag would publish this commit)"
ok "HEAD is origin/main"

grep -q "^## \[${VERSION}\]" CHANGELOG.md \
  || fail "CHANGELOG.md has no '## [${VERSION}]' section — move [Unreleased] first"
ok "CHANGELOG has a ${VERSION} section"

if git rev-parse --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  fail "tag ${TAG} already exists locally — bump VERSION first"
fi
if git ls-remote --tags origin 2>/dev/null | grep -qE "refs/tags/${TAG}\$"; then
  fail "tag ${TAG} already exists on origin"
fi
ok "tag ${TAG} does not yet exist"

# ─ API contract ──────────────────────────────────────────────────────────
# The contract version CI pins (poli-page/api-contract action in
# .github/workflows/ci.yml). Keep the two in step when Dependabot bumps it.
CONTRACT_SHA="0eba96c1ecf9a28b7e259f444f3ca5b7c059d5fd" # v1.3.0
echo
say "API contract"
if [[ -n "${POLI_CONTRACT:-}" ]]; then
  [[ -f "$POLI_CONTRACT" ]] || fail "POLI_CONTRACT=${POLI_CONTRACT} is not a file"
  note "using POLI_CONTRACT=${POLI_CONTRACT}"
else
  contract_dir="$(mktemp -d)"
  POLI_CONTRACT="${contract_dir}/contract.json"
  curl -fsSL "https://raw.githubusercontent.com/poli-page/api-contract/${CONTRACT_SHA}/contract.json" \
    -o "$POLI_CONTRACT" || fail "could not download the API contract ${CONTRACT_SHA}"
  ok "downloaded contract ${CONTRACT_SHA}"
fi
export POLI_CONTRACT

# ─ verify (local CI) ─────────────────────────────────────────────────────
echo
say "Verify (lint + types + tests + audit + build)"
bundle config set --local frozen true
bundle install
bundle exec rubocop
bundle exec rbs validate
CI=true bundle exec rspec spec
bundle exec yard --fail-on-warning
bundle exec bundle-audit check --update

if [[ -n "${POLI_PAGE_API_KEY:-}" ]]; then
  note "POLI_PAGE_API_KEY set — running integration suite"
  INTEGRATION=1 bundle exec rspec spec/integration

  if [[ "$SKIP_DEMO" -eq 0 ]]; then
    note "running examples/demo.rb against develop"
    ruby examples/demo.rb
  fi
else
  note "POLI_PAGE_API_KEY not set — skipping integration + demo (set it for full coverage)"
fi

# ─ build + pack inspect ──────────────────────────────────────────────────
echo
say "Build and inspect gem"
rm -f poli-page-*.gem
gem build poli-page.gemspec
[[ -f "$GEM_FILE" ]] || fail "gem build did not produce ${GEM_FILE}"
ls -lh "$GEM_FILE"

inspect_dir="$(mktemp -d)"
gem unpack "$GEM_FILE" --target "$inspect_dir" >/dev/null
unpacked_root="$(find "$inspect_dir" -maxdepth 1 -mindepth 1 -type d)"
echo
echo "Contents of ${c_cyan}${GEM_FILE}${c_reset}:"
(cd "$unpacked_root" && find . -type f | sort)
total_size_kb="$(du -sk "$unpacked_root" | awk '{print $1}')"
echo "Total size: ${c_bold}${total_size_kb} KB${c_reset}"
rm -rf "$inspect_dir"

# ─ tag ───────────────────────────────────────────────────────────────────
echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "${c_yellow}Dry run complete${c_reset} — skipping the tag push"
  rm -f "$GEM_FILE"
  exit 0
fi

say "About to tag"
echo "    git tag ${TAG} && git push origin ${TAG}"
echo "    (the release workflow publishes after reviewer approval)"
echo
read -r -p "${c_bold}Confirm tag push? [y/N]${c_reset} " reply
[[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "aborted"; rm -f "$GEM_FILE"; exit 1; }

say "Tagging ${TAG}"
git tag -a "$TAG" -m "poli-page ${VERSION}"
git push origin "$TAG"

echo
ok "${c_bold}Pushed ${TAG}${c_reset}"
note "next: approve the \`rubygems-release\` deployment in the Actions run to publish"
note "run:      https://github.com/poli-page/sdk-ruby/actions/workflows/release.yml"
note "rubygems: https://rubygems.org/gems/poli-page/versions/${VERSION}  (after approval)"
note "rubydoc:  https://rubydoc.info/gems/poli-page/${VERSION}  (builds within ~5 min of publish)"

rm -f "$GEM_FILE"
