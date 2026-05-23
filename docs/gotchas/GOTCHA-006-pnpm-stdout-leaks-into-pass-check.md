---
id: GOTCHA-006
discovered: 2026-05-23
discovered_by: human
scope:
  - "scripts/aw-test-frontend.sh"
  - "scripts/aw-test-*.sh"
severity: medium
status: mitigated
reproducibility: always
tags: [pnpm, stdout, bash, workflow, frontend]
---

# GOTCHA-006 — pnpm install stdout leaks "Scope:" preamble before PASS, breaking exact-match condition

## Symptom

Frontend tests pass (57/217 ✓) but `fix-blocked` fires unnecessarily and
`commit` is skipped:

```
[run-tests] Completed (7.5s)
[fix-blocked] Started   ← wrong — tests passed
[commit] Skipped (when_condition)
```

The coder in `fix-blocked` correctly observes *"The tester reports PASS on
all 4 workspace projects"* from `$run-tests.output`, but the workflow graph
had already routed incorrectly.

## Root cause

`aw-test-frontend.sh` contained:

```bash
pnpm install --frozen-lockfile --quiet 2>/dev/null || \
  pnpm install --quiet 2>/dev/null || true
```

`2>/dev/null` suppresses stderr but leaves **stdout open**. Before
running the child command, `pnpm` writes workspace scope info to its own
stdout:

```
Scope: all 4 workspace projects

Done in 583ms
```

This output went directly to the script's stdout **before** the `echo "PASS"`
line. The final stdout captured by Archon was:

```
Scope: all 4 workspace projects

Done in 583ms
PASS
```

The workflow condition `$run-tests.output == 'PASS'` is an **exact string
match**. `"Scope:…\nPASS"` ≠ `"PASS"` → condition false → `fix-blocked` ran.

## Fix

Use `&>/dev/null` (suppress both stdout and stderr) on the install lines:

```bash
# BEFORE — stderr suppressed but stdout leaks
pnpm install --frozen-lockfile --quiet 2>/dev/null || ...

# AFTER — both streams suppressed
pnpm install --frozen-lockfile --quiet &>/dev/null || ...
```

**Verification:**
```bash
bash scripts/aw-test-frontend.sh 2>/dev/null | xxd | head -2
# expected:  50 41 53 53 0a   (PASS\n)
# broken:    53 63 6f 70 65…  (Scope:…)
```

## Prevention

After any change to a `scripts/aw-test-*.sh` file, verify the raw stdout
with `xxd`. The only byte sequence allowed on success is `50 41 53 53 0a`
(`PASS\n`). Any other preamble will break the `== 'PASS'` condition.

The same risk applies to any tool (e.g. `npm`, `yarn`, `cargo`, `maven`)
that writes workspace/build preamble to stdout before the test output.
Always redirect both streams from setup/install commands.

## History

- 2026-05-23: Discovered during FE-02 run. Tests passed 57/217 but
  `fix-blocked` fired; coder wasted ~2 min diagnosing. (— human)
- 2026-05-23: `aw-test-frontend.sh` fixed with `&>/dev/null`. Status → mitigated.
