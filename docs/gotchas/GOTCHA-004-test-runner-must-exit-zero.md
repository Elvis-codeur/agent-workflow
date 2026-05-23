---
id: GOTCHA-004
discovered: 2026-05-23
discovered_by: human
scope:
  - "scripts/aw-test-*.sh"
  - ".archon/workflows/*.yaml.tmpl"
severity: high
status: mitigated
reproducibility: always
tags: [archon, bash, exit-code, fix-blocked, workflow]
---

# GOTCHA-004 — Test runner scripts must always exit 0; exit 1 silently skips fix-blocked

## Symptom

Tests genuinely fail (e.g. `1 failed, 20 passed`) but the workflow skips
`fix-blocked` entirely and goes straight to arbitrate or decide:

```
[run-tests] Failed: Bash node 'run-tests' failed [exit 1]
[fix-blocked] Skipped (trigger_rule)
[rerun-tests] Skipped (trigger_rule)
```

The coder never gets a chance to fix the failing tests.

## Root cause

Archon marks a bash node as **FAILED** (not Completed) when it exits non-zero.
`fix-blocked` depends on `run-tests` with the default
`trigger_rule: all_success`, which requires all upstream nodes to be in
**Completed** state. A FAILED `run-tests` node causes every downstream node
to be skipped.

The workflow design uses **output content** to detect test failure
(`$run-tests.output != 'PASS'`), not exit code. Exit code is only used
by Archon for routing. These two mechanisms must not conflict:

| Exit code | Archon node state | fix-blocked triggered? |
|---|---|---|
| 0 | Completed | yes, if output != 'PASS' |
| 1 | **FAILED** | **no — skipped by trigger_rule** |

## Fix

Test runner scripts (`aw-test-backend.sh`, `aw-test-frontend.sh`) must
**always exit 0**:

```bash
# WRONG — marks run-tests node as FAILED, skips fix-blocked
else
  cat "$TMPOUT"; exit 1
fi

# CORRECT — Archon routes by content, not exit code
else
  cat "$TMPOUT"
  # (implicit exit 0 — failure signalled by stdout content)
fi
```

On failure, the full test output is sent to **stdout** (captured as
`$run-tests.output`) so the coder node can read the error details.
On success, only the bare word `PASS` is sent to stdout.

## Prevention

`aw-regression-test` Suite 5 (`test_aw_test_backend_exits_zero_on_failure`)
scans the script for `exit 1` in the failure branch and fails if found.

## History

- 2026-05-23: Discovered during BE-35 run — `run-tests` exited 1 with stale
  epic ID in stderr; `fix-blocked` was skipped. (— human)
- 2026-05-23: Both `aw-test-backend.sh` and `aw-test-frontend.sh` fixed.
  Status → mitigated.
