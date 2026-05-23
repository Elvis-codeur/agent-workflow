#!/usr/bin/env bash
# aw-run-tests.sh — project-agnostic test runner called by the Archon workflow.
# Outputs "PASS" on stdout if all relevant tests pass, otherwise prints the
# failing output and exits non-zero. Override by dropping a `scripts/aw-test-<scope>.sh`
# in your project and we'll prefer it.
set -uo pipefail
SCOPE="${1:-}"; EPIC="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"

if [[ -x "$ROOT/scripts/aw-test-$SCOPE.sh" ]]; then
    exec "$ROOT/scripts/aw-test-$SCOPE.sh" "$EPIC"
fi

# Fallbacks
if [[ -f "$ROOT/pnpm-workspace.yaml" || -f "$ROOT/package.json" ]] && command -v pnpm >/dev/null; then
    pnpm -w test && echo PASS && exit 0
fi
if [[ -f "$ROOT/pyproject.toml" ]] && command -v uv >/dev/null; then
    uv run pytest -q && echo PASS && exit 0
fi
echo "no test runner detected for scope=$SCOPE" >&2
exit 1
