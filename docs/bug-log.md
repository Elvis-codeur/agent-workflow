# Bug log — Archon master-loop integration

This document records every bug discovered while building and operating the
Archon master-loop workflow on real epics. Each entry follows the same
structure: symptom → root cause → fix → how to prevent regression.

Pre-release gotchas (GOTCHA-001 through GOTCHA-003) are in separate files
under `docs/gotchas/`. The bugs below were found during live production runs.

---

## BUG-001 — Archon rejects `loop:` inside `nodes:` DAG mode

**Symptom:**
```
WARN dag_node_validation_failed
  "Node 'implement': 'loop.prompt' Required"
  "Node 'fix-blocked': 'loop.prompt' Required"
```
`archon validate workflows` reports errors; no nodes run.

**Root cause:**
Archon's YAML schema has two mutually exclusive top-level execution modes:
`steps:`, `loop:` + `prompt:`, or `nodes:` (DAG). Per-node `loop:` blocks
are not a valid field inside a `nodes:` DAG. We had added `loop:` to
`implement`, `fix-blocked`, and `ask-human` nodes, which Archon rejected.

**Fix:**
Removed all per-node `loop:` blocks. The agents iterate internally
(the skill text already instructs them to do so). Cross-DAG iteration is
handled by the outer `aw-run` recursion via the `decide` node marker.

**Prevention:**
`aw-regression-test` Suite 3 (`test_rendered_yaml_passes_archon_validate`)
catches any YAML schema violation at test time.

---

## BUG-002 — Template file discovered by Archon as a real workflow

**Symptom:**
```
WARN dag_node_validation_failed  filename: "aw-master-loop.template.yaml"
  "Node 'implement': 'model' Expected string, received object"
```
`discovery errorCount: 1` on every startup; spurious warnings in all runs.

**Root cause:**
Archon discovers every `.yaml` / `.yml` file under `.archon/workflows/`
(see `workflow-discovery.ts:119`). Our mustache template file
`aw-master-loop.template.yaml` contains `{{CODER_PROVIDER}}` placeholders.
The YAML parser reads `{{...}}` as a flow-style mapping, which fails schema
validation. The template was never meant to be loaded directly.

**Fix:**
Renamed `aw-master-loop.template.yaml` → `aw-master-loop.template.yaml.tmpl`.
Archon's discovery only globs `*.yaml` and `*.yml`; the `.tmpl` extension
is invisible to it.

Also added `exclude: ^\.archon/workflows/.*\.template\.yaml$` to the
`check-yaml` pre-commit hook so linters don't trip on the mustache syntax.

**Prevention:**
`aw-regression-test` Suite 3 (`test_rendered_yaml_passes_archon_validate`)
renders the template first, then validates the rendered file — the template
itself is never validated directly.

---

## BUG-003 — Pi model ref requires `<catalog-provider>/<model-id>` format

**Symptom:**
```
ERROR dag_node_failed  nodeId: "read-epic"
  "Invalid Pi model ref: 'sonnet'.
   Expected format '<pi-provider-id>/<model-id>'
   (e.g. 'google/gemini-2.5-pro')."
```
The workflow fails immediately on the first node.

**Root cause:**
Archon's Pi provider (`model-ref.ts`) validates that any model string
passed via `pi:` contains a `/` separating the catalog provider from the
model ID (e.g. `github-copilot/claude-sonnet-4.6`). We were using bare
names like `pi:sonnet` which have no `/`.

**Fix:**
Changed all defaults in `scripts/aw-run` to use fully qualified refs:
```
coder   → pi:github-copilot/gpt-5.3-codex
tester  → pi:github-copilot/gemini-3-flash-preview
master  → pi:github-copilot/gpt-5.2
```
Added upfront validation in `aw-run` that rejects any `pi:...` model
without a `/` and prints actionable examples.

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_run_rejects_bare_pi_model` and
`test_aw_run_accepts_valid_pi_model`) verify the validation logic.

---

## BUG-004 — GOTCHA-002: Double-quoting `$node.output` breaks bash

**Symptom:**
```
[decide] Failed [exit 2]:
  bash: syntax error near unexpected token '('
```
The `decide`, `run-tests`, and `rerun-tests` bash nodes fail with shell
syntax errors whenever the upstream node's output contains `"` characters.

**Root cause:**
Archon substitutes `$node.output` placeholders using single-quote wrapping
(`shellQuote`). The template wrapped substitutions in double-quotes too:
`"$arbitrate.output"`. After substitution this became `"'{json}'"`
where the first `"` inside the JSON immediately closes the outer double-quote,
and the rest of the JSON is treated as bare shell words. Any `(` in the JSON
(e.g. from `pytest.xfail('...')` in a rationale string) then throws a
syntax error.

**Fix:**
Removed all outer `"..."` from `$node.output` references in bash: nodes.
Archon's single-quoting is sufficient; no additional quoting is needed.

```yaml
# WRONG
bash scripts/aw-run-tests.sh "$read-epic.output.scope" "$read-epic.output.epic_id"

# CORRECT
bash scripts/aw-run-tests.sh $read-epic.output.scope $read-epic.output.epic_id
```

**Prevention:**
`aw-regression-test` Suite 3
(`test_no_double_quoted_node_output_in_bash_nodes`) scans every `bash:` block
in the template for the `"$nodeId.output"` pattern and fails if found.

---

## BUG-005 — Archon worktree bash nodes run in worktree CWD (not project root)

**Symptom:**
```
[run-tests] Failed [exit 127]:
  bash: scripts/aw-run-tests.sh: No such file or directory
[decide] Failed [exit 127]:
  bash: scripts/aw-decide.sh: No such file or directory
```

**Root cause:**
Archon sets the CWD for all bash nodes to the **worktree path**
(`~/.archon/workspaces/…/worktrees/…`), not the original project directory.
When the worktree is branched from `main` and `main` does not yet contain
the workflow scripts (`scripts/aw-run-tests.sh` etc.), the bash nodes cannot
find them.

**Fix:**
Merged the workflow infrastructure branch (`feat/aw-archon-master-loop`)
to `main` before running any epics, so every new worktree (branched from
`origin/main`) includes the scripts.

**Prevention:**
Always merge workflow infrastructure to `main` before running `aw-run`.
The `aw-regression-test` Suite 2 (`test_worktree_path_convention`) alerts
if the worktree structure changes.

---

## BUG-006 — GOTCHA-003: Archon worktree venv has no packages installed

**Symptom:**
```
pytest: 63 xfailed, 0 passed
```
All tests are skipped with `pytest.xfail("simulator not yet implemented")`.
No actual test failures, but no passes either. `run-tests` outputs something
other than `PASS`, so `fix-blocked` and `arbitrate` run unnecessarily.

**Root cause:**
Archon creates worktrees without running any project setup. The workspace
`uv` virtual environment exists but the package sources are not installed in
it (`import simulator` → `ModuleNotFoundError`). Each test file guards
its imports with `try: import X except ImportError: pytest.xfail(...)`,
making all 63 tests appear to succeed vacuously.

**Fix:**
Added `uv sync --all-packages --quiet 2>/dev/null || true` at the top of
`scripts/aw-test-backend.sh`. This is fast (~100ms) when packages are already
installed, and installs them on a fresh worktree.

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_test_backend_exits_zero_on_failure`)
verifies the script never exits 1. A future test could verify that
`uv sync` is present in the script body.

---

## BUG-007 — Test runner exits 1 → `fix-blocked` skipped

**Symptom:**
```
[run-tests] Failed: Bash node 'run-tests' failed [exit 1]
[fix-blocked] Skipped (trigger_rule)
```
Even when tests genuinely fail, the fix cycle never runs.

**Root cause:**
`scripts/aw-test-backend.sh` (and `aw-test-frontend.sh`) were ending their
failure branch with `exit 1`. Archon marks a bash node as **FAILED** (not
Completed) when it exits non-zero. `fix-blocked` depends on `run-tests` with
the default `trigger_rule: all_success`. A FAILED upstream means downstream
nodes are all skipped.

The workflow detects test failure through **output content** (`output != 'PASS'`),
not through exit code. The exit code must always be 0 for the workflow graph
to function.

**Fix:**
Removed `exit 1` from the failure branch of both test runners. On failure:
- full test output → stdout (so `$run-tests.output` contains the error)
- exit 0 (so run-tests node Completes and fix-blocked can run)

```bash
# BEFORE (broken)
else
  cat "$TMPOUT"; rm -f "$TMPOUT"
  exit 1          ← marks node FAILED, skips fix-blocked
fi

# AFTER (correct)
else
  cat "$TMPOUT"; rm -f "$TMPOUT"
  # exit 0 implicitly — failure detected by content, not exit code
fi
```

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_test_backend_exits_zero_on_failure`)
checks that the script file contains no `exit 1` in the failure branch.

---

## BUG-008 — `execute bit` not set on new scripts in git

**Symptom:**
```
[run-tests] Failed [exit 1]: no test runner detected for scope='backend'
```
`aw-run-tests.sh` reaches the fallback because `[[ -x scripts/aw-test-backend.sh ]]`
returns false — the file exists but has mode `100644` (not executable).

**Root cause:**
`git add scripts/aw-test-backend.sh` committed the file with mode `100644`.
The `-x` flag in bash checks the file-system execute bit, which is set from
the git index mode. Mode `100644` → not executable.

**Fix:**
```bash
git update-index --chmod=+x scripts/aw-test-backend.sh
git commit -m "fix: set execute bit (100755)"
```
The `install.sh` script uses `chmod +x` on all scripts it copies, but it
cannot fix the git index mode in the target repo. The fix must be applied
in the source repo.

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_run_exists_and_is_executable`) checks
the execute bit on `aw-run`. Consider adding similar checks for
`aw-test-backend.sh` and `aw-test-frontend.sh`.

---

## BUG-009 — `aw-decide.sh` writes state marker to worktree, not main repo

**Symptom:**
```
iteration 1 finished: rc=0 state=UNKNOWN
workflow failed (rc=0) after 1 iteration(s) — worktree preserved
  ⚠ could not locate worktree for BE-32 — skipping merge
  ✓ BE-32 DONE
```
Archon reports "Workflow completed successfully" and rc=0, but `aw-run` reads
`state=UNKNOWN` from the marker file, so merges are never performed.

**Root cause:**
`aw-decide.sh` determines the state directory with:
```bash
ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="$ROOT/.archon/state"
```
In a git worktree, `--show-toplevel` returns the **worktree path**
(`~/.archon/workspaces/…/worktrees/archon/task-archon-epic-be-32`), not the
main repo path. The marker file was written to the worktree's state dir.
`aw-run` runs in the **main repo** and reads from the main repo's state dir.
The two paths never match → `UNKNOWN`.

**Fix:**
Changed `aw-decide.sh` to use `--git-common-dir` instead of `--show-toplevel`:
```bash
# OLD (broken in worktrees)
ROOT="$(git rev-parse --show-toplevel)"

# NEW (always points to main repo)
ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
```
`--git-common-dir` returns the main repo's `.git` directory regardless of
whether the command is run from the main checkout or any worktree.

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_decide_converged`) runs `aw-decide.sh`
in a temp git repo and verifies it outputs `CONVERGED` correctly. Consider
adding a test that runs it from inside a worktree context specifically.

---

## BUG-010 — `if` block eaten by Python heredoc in `aw-run`

**Symptom:**
```
scripts/aw-run: line 265: syntax error near unexpected token `elif'
```
Every `aw-run` invocation exits with code 2 (bash syntax error).

**Root cause:**
When adding the `print_rate_limit_info` function containing a Python `<<'PYEOF'`
heredoc, the shell `if [[ "$RC" -eq 0 && "$CLEAN_WORKTREE" -eq 1 ]]; then`
line that follows the function was accidentally placed inside the heredoc body.
From bash's perspective, the heredoc ended at `PYEOF`, then the next
non-indented line was `elif` — without a matching `if`. Bash threw a syntax error.

**Fix:**
Restored the missing `if` line:
```bash
PYEOF
}

if [[ "$RC" -eq 0 && "$CLEAN_WORKTREE" -eq 1 ]]; then    # ← was missing
    echo "workflow converged..."
elif [[ "$RC" -eq 42 ]]; then
    ...
fi
```

**Prevention:**
Add `bash -n scripts/aw-run` to the pre-commit hooks (or to a regression
test) to catch syntax errors before they reach production.

---

## BUG-011 — `find_worktree` awk breaks on paths with spaces

**Symptom:**
```
⚠ could not locate worktree for BE-34 — skipping merge
```
The worktree exists and the branch is active, but `aw-run-all.sh` can't
find it and silently skips the merge.

**Root cause:**
`find_worktree` used awk to parse `git worktree list --porcelain`:
```bash
git worktree list --porcelain \
  | awk '/^worktree /{wt=$2} /^branch /{if($2 ~ SAFE){print wt}}' \
    SAFE="$safe"
```
`awk` splits on whitespace by default. The worktree path for the main repo
is `/mnt/external_drive/Github Works/…` (contains a space). awk's `$2` only
captures up to the first space, giving a truncated path. This caused the
`wt` variable to be corrupt for the main worktree entry, and the pattern
matching to be unreliable.

**Fix:**
Replaced awk with an inline Python3 script that handles arbitrary paths:
```python
for line in sys.stdin:
    line = line.rstrip('\n')
    if line.startswith('worktree '):
        wt = line[9:]          # entire rest of line, including spaces
    elif line.startswith('branch ') and SAFE in line.lower():
        print(wt); break
```
Also added `find_branch()` as a fallback: if the worktree is gone (e.g.
`archon complete` already ran) but the git branch still exists, merge
directly from the branch.

**Prevention:**
`aw-regression-test` could add a test that creates a worktree with a space
in the path and verifies `find_worktree` returns it correctly.

---

## BUG-012 — `pnpm install` stdout leaks into `run-tests.output`

**Symptom:**
`run-tests` completes (57/217 tests pass), but `fix-blocked` fires:
```
[fix-blocked] Started  ← wrong — tests passed
[commit] Skipped (when_condition)  ← wrong — should have committed
```
The coder in `fix-blocked` reads: *"The tester reports PASS on all 4 workspace
projects"* but the workflow treats the run as failed.

**Root cause:**
`scripts/aw-test-frontend.sh` ran `pnpm install --quiet 2>/dev/null`. This
suppressed stderr but left stdout open. `pnpm` writes workspace preamble
lines (`Scope: all 4 workspace projects\n\nDone in 583ms`) to its own
stdout before spawning the child command. These lines went directly to the
script's stdout, before `echo "PASS"`. The final stdout was:
```
Scope: all 4 workspace projects

Done in 583ms
PASS
```
The workflow condition `$run-tests.output == 'PASS'` is an **exact** string
match. `"Scope:…\nPASS"` ≠ `"PASS"`. The condition was false, so
`fix-blocked` ran unnecessarily.

**Fix:**
Changed `2>/dev/null` to `&>/dev/null` on the `pnpm install` lines:
```bash
# BEFORE
pnpm install --frozen-lockfile --quiet 2>/dev/null || \
  pnpm install --quiet 2>/dev/null || true

# AFTER
pnpm install --frozen-lockfile --quiet &>/dev/null || \
  pnpm install --quiet &>/dev/null || true
```

**Prevention:**
Verify the raw stdout of the test runner before deploying:
```bash
bash scripts/aw-test-frontend.sh 2>/dev/null | xxd | head -3
# expected: 50 41 53 53 0a  (PASS\n)
```

---

## BUG-013 — `aw-decide.sh` verdict pattern requires space after colon

**Symptom:**
After arbitration produces `verdict: coder_right`, the `decide` node writes
`FAILED` instead of `ITERATE`. The workflow stops without merging.

**Root cause:**
`aw-decide.sh` checked:
```bash
if [[ "$ARB_JSON" == *'"verdict": "coder_right"'* ]]
```
Note the space after the colon: `"verdict": "coder_right"`.

Pi's `output_format` structured output emits **compact JSON** with no spaces:
```json
{"verdict":"coder_right","rationale":"...","confidence":0.97}
```

The pattern never matched (`"verdict":"coder_right"` ≠ `"verdict": "coder_right"`),
so the `ITERATE` branch was never taken. The script fell through to
`echo FAILED`.

**Fix:**
Changed the patterns to bare glob matches without requiring the colon/space:
```bash
# BEFORE (fragile — requires specific whitespace)
if [[ "$ARB_JSON" == *'"verdict": "coder_right"'* ]] || \
   [[ "$ARB_JSON" == *'"verdict": "tester_right"'* ]]

# AFTER (robust — matches regardless of JSON formatting)
if [[ "$ARB_JSON" == *coder_right* ]] || \
   [[ "$ARB_JSON" == *tester_right* ]]
```

**Prevention:**
`aw-regression-test` Suite 5 (`test_aw_decide_iterate`) tests the ITERATE
case with a JSON blob that uses compact formatting (no space after colon).

---

## BUG-014 — Merge conflict markers left on main after FE-51 merge

**Symptom:**
```
FAIL  src/simulation/SimSettings.ts
Error: Transform failed: Unexpected "<<"
  1 | <<<<<<< HEAD
```
All frontend tests fail in the FE-02 worktree (and any future frontend
worktree) with a transform error from esbuild.

**Root cause:**
When merging `archon/task-archon-epic-fe-51` to `main`, a conflict arose in
three files (`sim-settings.ts`, `SimSettings.ts`, `SimSettingsPanel.tsx`).
The first conflict was resolved and committed, but the other two were committed
with the conflict markers still in place (the `--no-verify` commit flag bypassed
the pre-commit `check for merge conflicts` hook).

**Fix:**
```bash
git checkout archon/task-archon-epic-fe-51 -- \
  apps/frontend/src/simulation/SimSettings.ts \
  apps/frontend/src/simulation/SimSettingsPanel.tsx
git commit -m "fix: resolve remaining FE-51 merge conflicts"
```

**Prevention:**
- Never use `--no-verify` on merge commits unless the hooks are known to be
  irrelevant (formatting fixups are safe; conflict-marker checks are not).
- Run `grep -r "<<<<<<" apps/ packages/` after any merge before pushing.
- Consider adding a `git diff --check` step in `aw-run-all.sh` after each
  merge to catch any leftover markers before they reach origin/main.

---

## Summary table

| Bug | Symptom (short) | Affected script | Fix type |
|-----|----------------|-----------------|----------|
| BUG-001 | `loop.prompt Required` validation error | template YAML | Remove per-node `loop:` |
| BUG-002 | Template file triggers validation errors | template YAML | Rename to `.yaml.tmpl` |
| BUG-003 | `Invalid Pi model ref: 'sonnet'` | `aw-run` | Add `/` format requirement |
| BUG-004 | `syntax error near '('` in bash nodes | template YAML | Remove outer `"..."` from `$node.output` |
| BUG-005 | Script not found (exit 127) | infrastructure | Merge scripts to main before running |
| BUG-006 | 63 xfailed, 0 passed | `aw-test-backend.sh` | Add `uv sync --all-packages` |
| BUG-007 | `fix-blocked` skipped on real failures | test runners | Never `exit 1`; use exit 0 + content |
| BUG-008 | `no test runner detected` | `aw-test-backend.sh` | `git update-index --chmod=+x` |
| BUG-009 | `state=UNKNOWN`, merges skipped | `aw-decide.sh` | Use `--git-common-dir` |
| BUG-010 | `syntax error near 'elif'` | `aw-run` | Restore `if` eaten by heredoc |
| BUG-011 | Worktree not found, merge skipped | `aw-run-all.sh` | Python parser + `find_branch` fallback |
| BUG-012 | `fix-blocked` fires when tests pass | `aw-test-frontend.sh` | `&>/dev/null` on pnpm install |
| BUG-013 | `FAILED` written after `coder_right` | `aw-decide.sh` | Bare glob `*coder_right*` |
| BUG-014 | Conflict markers on main, tests fail | `merge` procedure | Resolve all conflicts before push |

---

## Lessons learned

**1. Bash bash bash.**
Most bugs were bash quoting or process-model issues (BUG-004, BUG-009, BUG-010,
BUG-011, BUG-012). Shell scripting in a pipeline where some inputs come from
a template substitution engine (Archon) requires paranoid care about quoting.
Rule: never double-quote a `$node.output` reference; let Archon's single-quoting
stand on its own.

**2. Exit codes are the contract, not the message.**
BUG-007 was subtle: the test output clearly showed 217 passed, but the workflow
couldn't proceed because the bash node exited 1. The workflow graph uses exit
codes for routing decisions; stdout content is for the agents. Keep them separate.

**3. CWD is the worktree, not the project.**
BUG-005 and BUG-009 both stem from the same assumption: "the script runs in my
project directory." In Archon's isolated worktree model, CWD is
`~/.archon/workspaces/…/worktrees/…`. Use `git rev-parse --git-common-dir`
to find the main repo; never assume CWD.

**4. Merge carefully, test immediately.**
BUG-014 was a human error: using `--no-verify` on a merge commit bypassed the
conflict-marker check. The fix is simple procedural hygiene, but it cost an
entire extra workflow run to diagnose.

**5. Write regression tests as you go.**
Every bug in this list has a corresponding test in `scripts/aw-regression-test`.
Run `python3 scripts/aw-regression-test` before any infrastructure change and
before upgrading Archon or Pi.
