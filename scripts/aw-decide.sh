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
#   $2 run-tests output    (PASS or test failure text)
#   $3 rerun-tests output  (PASS or test failure text; "" if not run)
#   $4 commit node status  (the bash node printed nothing; we infer from $5)
#   $5 arbitrate JSON      (the structured-output JSON; "" if not run)
#   $6 ask-human output    (the human's final word; "" if not run)
set -euo pipefail

EPIC="${1:?epic id required}"
RUN_OUT="${2:-}"
RERUN_OUT="${3:-}"
COMMIT_STATUS="${4:-}"
ARB_JSON="${5:-}"
HUMAN_OUT="${6:-}"

ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="$ROOT/.archon/state"
mkdir -p "$STATE_DIR"
MARKER="$STATE_DIR/iterate-decision-${EPIC//[^A-Za-z0-9]/_}"

decide() {
    # Green path: a test phase passed AND we didn't fall into arbitration.
    if [[ -z "$ARB_JSON" ]] && \
       { [[ "$RUN_OUT" == *PASS* ]] || [[ "$RERUN_OUT" == *PASS* ]]; }; then
        echo CONVERGED; return
    fi

    # Hard stop: master signalled arbitration cap reached.
    if [[ "$ARB_JSON" == *'"exhausted": true'* ]] || \
       [[ "$ARB_JSON" == *'"exhausted":true'* ]]; then
        echo EXHAUSTED; return
    fi

    # Iterate: arbitration produced a decisive verdict (coder/tester right),
    # OR the human picked one in the ask-human node.
    if [[ "$ARB_JSON" == *'"verdict": "coder_right"'* ]] || \
       [[ "$ARB_JSON" == *'"verdict": "tester_right"'* ]] || \
       [[ -n "$HUMAN_OUT" ]]; then
        echo ITERATE; return
    fi

    # Unknown / real failure.
    echo FAILED
}

STATE="$(decide)"
echo "$STATE" > "$MARKER"
echo "$STATE"
