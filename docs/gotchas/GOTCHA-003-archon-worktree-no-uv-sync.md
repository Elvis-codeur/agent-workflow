---
id: GOTCHA-003
discovered: 2026-05-23
discovered_by: human
scope:
  - "scripts/aw-test-*.sh"
severity: medium
status: mitigated
reproducibility: always
tags: [archon, uv, worktree, python, venv, import]
---

# GOTCHA-003 — Archon worktree venv has no packages installed; pytest sees `ModuleNotFoundError` → xfail

## Symptom

All Python tests in a fresh Archon worktree are marked `xfail` instead of
running. Inside each test file, the import is guarded:

```python
try:
    from simulator.compiler.gsim_sch_loader import load
except ImportError:
    pytest.xfail("simulator not yet implemented")
```

pytest reports e.g. `63 xfailed` and exits 0. `aw-run-tests.sh` outputs
nothing that matches `PASS`, so `run-tests` is treated as a failure, and
`fix-blocked` / `arbitrate` run unnecessarily.

## Root cause

Archon creates a worktree with `git worktree add` and starts running DAG
nodes immediately. It does **not** run any project setup (no `uv sync`,
no `pip install`, no `pnpm install`). The worktree shares the workspace
root's `.venv`, but the virtual environment was created for the main checkout
and the workspace packages may not be installed in it at worktree-creation
time.

`uv sync` is workspace-aware and idempotent — it resolves and installs all
packages declared in `[tool.uv.workspace]` in ~100 ms when already up to
date, and only downloads/builds what is missing. Calling it at the top of
the test runner costs nothing on subsequent runs.

## Fix

Add `uv sync --all-packages --quiet 2>/dev/null || true` at the top of
`scripts/aw-test-backend.sh` (and any other `scripts/aw-test-*.sh` files
for other scopes).

## Prevention

- Every new `scripts/aw-test-<scope>.sh` file should start with the `uv sync`
  (or equivalent package-manager install) guard.
- Document this in the `aw-test-backend.sh` header comment.

## References

- `uv` workspace documentation: https://docs.astral.sh/uv/concepts/workspaces/

## History

- 2026-05-23: Observed during BE-30 run; arbitrate ran with
  `confidence: 0.97` correctly diagnosing the environment issue.
  Root fix: added `uv sync --all-packages` to `aw-test-backend.sh`. (— human)
- 2026-05-23: Status → mitigated.
