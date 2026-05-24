#!/usr/bin/env bash
# install-hooks.sh — wire .git/hooks/pre-push to run the local CI gates
# before every push (sdk-ruby-plan.md §16.4). Idempotent: re-run safely.
#
#   - RuboCop
#   - RBS validate
#   - RSpec unit suite (spec/integration excluded; opt-in via RUN_INTEGRATION=1)
#
# To bypass the hook for a one-off push (e.g. doc-only): `git push --no-verify`.
# To run integration tests on push, set `RUN_INTEGRATION=1` in the
# environment when invoking `git push`.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hook="${repo_root}/.git/hooks/pre-push"

cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# poli-page pre-push hook — installed by scripts/install-hooks.sh.
set -euo pipefail

echo "→ poli-page pre-push: rubocop"
bundle exec rubocop

echo "→ poli-page pre-push: rbs validate"
bundle exec rbs validate

echo "→ poli-page pre-push: rspec (unit)"
bundle exec rspec spec

if [[ "${RUN_INTEGRATION:-0}" == "1" ]]; then
  echo "→ poli-page pre-push: rspec (integration)"
  INTEGRATION=1 bundle exec rspec spec/integration
fi
HOOK

chmod +x "$hook"
echo "✓ installed pre-push hook at $hook"
echo "  bypass with 'git push --no-verify' (doc-only or emergency)"
echo "  enable integration tests with 'RUN_INTEGRATION=1 git push'"
