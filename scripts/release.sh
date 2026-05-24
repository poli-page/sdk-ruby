#!/usr/bin/env bash
# release.sh — primary publishing path for `poli-page`.
#
# Per sdk-ruby-plan.md §12.5 / §16.3. Maintainer-driven: prompts for
# confirmation before `gem push`, then pushes the tag *after* publish
# succeeds (so we never tag an unpublished commit).
#
# Pre-flight:
#   - working tree clean
#   - on `main`
#   - target tag does not yet exist locally or on `origin`
#   - ~/.gem/credentials present (gem push will use it)
#
# Verify (gates the release on local CI):
#   - bundle install --frozen
#   - bundle exec rubocop
#   - bundle exec rbs validate
#   - bundle exec rspec spec
#   - bundle exec yard --fail-on-warning
#   - bundle exec bundle-audit check --update
#   - INTEGRATION=1 bundle exec rspec spec/integration   (if POLI_PAGE_API_KEY set)
#   - ruby examples/demo.rb                              (smoke; optional, requires key)
#   - gem build poli-page.gemspec
#
# Pack inspect:
#   - gem unpack the built gem into a temp dir and show contents + size
#
# Publish (on confirmation):
#   - gem push poli-page-X.Y.Z.gem
#   - git tag vX.Y.Z && git push origin vX.Y.Z
#
# Flags:
#   --dry-run   Run everything except `gem push` and the tag push.
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
[[ "$DRY_RUN" -eq 1 ]] && note "DRY RUN — will skip gem push and tag push"
echo

# ─ pre-flight ────────────────────────────────────────────────────────────
say "Pre-flight"
branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || fail "must release from main (currently on '$branch')"
ok "on main"

[[ -z "$(git status --porcelain)" ]] || fail "working tree not clean — commit or stash first"
ok "working tree clean"

if git rev-parse --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  fail "tag ${TAG} already exists locally — bump VERSION first"
fi
if git ls-remote --tags origin 2>/dev/null | grep -qE "refs/tags/${TAG}\$"; then
  fail "tag ${TAG} already exists on origin"
fi
ok "tag ${TAG} does not yet exist"

if [[ "$DRY_RUN" -eq 0 ]] && [[ ! -f "$HOME/.gem/credentials" ]]; then
  fail "~/.gem/credentials missing — gem push will fail. Run 'gem signin' first."
fi

# ─ verify (local CI) ─────────────────────────────────────────────────────
echo
say "Verify (lint + types + tests + audit + build)"
bundle install --frozen
bundle exec rubocop
bundle exec rbs validate
bundle exec rspec spec
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

# ─ publish ───────────────────────────────────────────────────────────────
echo
if [[ "$DRY_RUN" -eq 1 ]]; then
  say "${c_yellow}Dry run complete${c_reset} — skipping gem push and tag push"
  rm -f "$GEM_FILE"
  exit 0
fi

say "About to publish"
echo "    gem push ${GEM_FILE}"
echo "    git tag ${TAG} && git push origin ${TAG}"
echo
read -r -p "${c_bold}Confirm publish? [y/N]${c_reset} " reply
[[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "aborted"; rm -f "$GEM_FILE"; exit 1; }

say "gem push ${GEM_FILE}"
gem push "$GEM_FILE"

say "Tagging ${TAG}"
git tag "$TAG"
git push origin "$TAG"

echo
ok "${c_bold}Released ${VERSION}${c_reset}"
note "rubygems: https://rubygems.org/gems/poli-page/versions/${VERSION}"
note "rubydoc:  https://rubydoc.info/gems/poli-page/${VERSION}  (builds within ~5 min)"
note "github:   https://github.com/poli-page/sdk-ruby/releases/tag/${TAG}  (optional: gh release create)"

rm -f "$GEM_FILE"
