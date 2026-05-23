---
id: GOTCHA-005
discovered: 2026-05-23
discovered_by: human
scope:
  - "scripts/aw-decide.sh"
  - "scripts/aw-run"
  - "scripts/aw-run-all.sh"
severity: high
status: mitigated
reproducibility: always
tags: [archon, worktree, git, state, merge]
---

# GOTCHA-005 — aw-decide.sh writes the state marker to the worktree, not the main repo

## Symptom

Archon reports "Workflow completed successfully" and `archon workflow run`
exits 0. But `aw-run` reads `state=UNKNOWN` from the marker file, so it
treats the run as failed and `aw-run-all.sh` skips the branch merge:

```
iteration 1 finished: rc=0 state=UNKNOWN
workflow failed (rc=0) after 1 iteration(s) — worktree preserved
  ⚠ could not locate worktree for BE-32 — skipping merge
  ✓ BE-32 DONE
```

The epic was actually complete; the merge was silently skipped every time.

## Root cause

`aw-decide.sh` computed the state directory with:

```bash
ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="$ROOT/.archon/state"
```

In a git worktree, `--show-toplevel` returns the **worktree path**
(`~/.archon/workspaces/…/worktrees/archon/task-archon-epic-be-32`),
not the original project path.

`aw-run` runs in the **main repo** and reads the marker from the main
repo's state directory — a completely different path. The marker written by
`aw-decide.sh` is invisible to `aw-run`.

## Fix

Use `--git-common-dir` instead of `--show-toplevel`. It always points to
the main repo's `.git` directory regardless of whether the command runs
in the main checkout or any worktree:

```bash
# OLD — returns worktree path inside a worktree
ROOT="$(git rev-parse --show-toplevel)"

# NEW — always returns main repo root
ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
```

`--git-common-dir` returns `.git` (relative) in the main repo and
`/path/to/repo/.git` (absolute) in any worktree. Navigating one level up
gives the repo root in both cases.

Added as a safety net in `aw-run`: if the marker is still UNKNOWN but
`archon workflow run` stdout contains "Workflow completed successfully",
treat the run as CONVERGED anyway.

## Prevention

`aw-regression-test` Suite 5 (`test_aw_decide_converged`) creates a
temp git repo, runs `aw-decide.sh EPIC-X PASS '' done '' ''` inside it,
and verifies stdout is `CONVERGED`. A worktree-specific test would catch
this regression earlier — consider adding one.

## History

- 2026-05-23: Discovered after BE-31, BE-32, BE-34 converged but were
  never merged — all had `state=UNKNOWN`. (— human)
- 2026-05-23: `aw-decide.sh` fixed to use `--git-common-dir`.
  `aw-run` fallback added. Status → mitigated.
