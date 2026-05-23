#!/usr/bin/env bash
# aw-run-tests.sh — project-agnostic test runner called by the Archon workflow.
# Outputs "PASS" on stdout if all relevant tests pass, otherwise prints the
# always exits 0 (failure signalled by stdout content != PASS). Override by dropping a `scripts/aw-test-<scope>.sh`
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
# ALWAYS EXIT 0: workflow detects failure by output content (!= PASS),
# not by exit code. Exiting 1 marks the node FAILED, skipping fix-blocked.
echo "RUNNER_ERROR: no test runner detected for scope=$SCOPE" >&2
# Output to stdout so coder node sees it
echo "ERROR: no test runner for scope=$SCOPE. Create scripts/aw-test-$SCOPE.sh"
