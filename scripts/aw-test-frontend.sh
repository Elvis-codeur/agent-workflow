#!/usr/bin/env bash
# aw-test-frontend.sh — project-specific frontend test runner for general-simulator.
# Called by scripts/aw-run-tests.sh when scope=frontend.
# Outputs bare "PASS" on stdout when the frontend vitest suite passes;
# exits non-zero with full vitest output on failure.
#
# Pre-existing failures from PLANNED (not yet implemented) epics are
# expected — the arbitrate node will classify them correctly.
# The stdout/stderr split matches aw-test-backend.sh so the workflow
# condition `$run-tests.output == 'PASS'` works as an exact match.
set -euo pipefail
EPIC="${1:-}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Ensure node_modules are present (worktrees share the workspace venv
# but pnpm links may be missing after a fresh worktree checkout).
pnpm install --frozen-lockfile --quiet 2>/dev/null || \
  pnpm install --quiet 2>/dev/null || true

TMPOUT=$(mktemp)

if pnpm --filter frontend test > "$TMPOUT" 2>&1; then
  # All tests pass — send vitest progress to stderr (visible in Archon UI)
  # and emit bare PASS to stdout (captured as the workflow node output).
  cat "$TMPOUT" >&2
  rm -f "$TMPOUT"
  echo "PASS"
else
  # Failures — send full output to stdout so the coder/arbitrate nodes
  # can read the error detail from $run-tests.output.
  cat "$TMPOUT"
  rm -f "$TMPOUT"
  exit 1
fi
