#!/usr/bin/env bash
# aw-decide.sh — final-node decision logic for the aw-master-loop workflow.
#
# Reads the outcomes of the upstream nodes, writes a one-word state to
# .archon/state/iterate-decision-<epic>, and prints the same word to stdout.
#
# States:
#   CONVERGED  tests pass AND commit succeeded -> aw-run exits 0 + cleanup
#   EXHAUSTED  arbitrate.flags.exhausted == true -> aw-run exits 42 + keep wt
#   ITERATE    coder/tester or human gave a verdict; another DAG run is due
#   FAILED     anything else -> aw-run breaks the loop with its own RC
#
# Args (positional, all strings, may be empty):
#   $1 epic id
#   $2 commit node output  (non-empty when commit ran)
#   $3 arbitrate JSON      (the structured-output JSON; "" if not run)
#   $4 ask-human output    (the human's final word; "" if not run)
#
# NOTE: We intentionally do NOT pass run-tests/rerun-tests outputs here.
# Those can be very large (vitest/pytest logs) and may exceed OS argv limits
# for the final decide bash node (E2BIG).
set -euo pipefail

# When read-epic upstream returns empty JSON (model rate-limited / silent
# failure), every $node.output substitution becomes empty string and we land
# here with EPIC="". Surface a clear diagnostic and propagate FAILED so the
# DAG aborts cleanly (rather than the bash :? error which is unhelpful).
EPIC="${1:-}"
if [[ -z "$EPIC" ]]; then
  echo "aw-decide: epic id missing — upstream read-epic likely returned empty output" >&2
  echo "FAILED"
  exit 1
fi
COMMIT_OUT="${2:-}"
ARB_JSON="${3:-}"
HUMAN_OUT="${4:-}"

# Use --git-common-dir instead of --show-toplevel.
# In a git worktree, --show-toplevel returns the WORKTREE path; aw-run
# (running in the main repo) would then read a different directory and
# never find the marker file → state=UNKNOWN forever.
# --git-common-dir returns the main repo's .git dir from any worktree.
ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
STATE_DIR="$ROOT/.archon/state"
mkdir -p "$STATE_DIR"
MARKER="$STATE_DIR/iterate-decision-${EPIC//[^A-Za-z0-9]/_}"

decide() {
    # Green path: commit ran successfully (which only happens after
    # tests + ci-check pass) and no arbitration was needed.
    if [[ -z "$ARB_JSON" ]] && [[ -n "$COMMIT_OUT" ]]; then
        echo CONVERGED; return
    fi

    # Hard stop: master signalled arbitration cap reached.
    if [[ "$ARB_JSON" == *'"exhausted": true'* ]] || \
       [[ "$ARB_JSON" == *'"exhausted":true'* ]]; then
        echo EXHAUSTED; return
    fi

    # Iterate: arbitration produced a decisive verdict (coder/tester right),
    # OR the human picked one in the ask-human node.
    if [[ "$ARB_JSON" == *coder_right* ]] || \
       [[ "$ARB_JSON" == *tester_right* ]] || \
       [[ -n "$HUMAN_OUT" ]]; then
        echo ITERATE; return
    fi

    # Unknown / real failure.
    echo FAILED
}

STATE="$(decide)"
echo "$STATE" > "$MARKER"
echo "$STATE"
