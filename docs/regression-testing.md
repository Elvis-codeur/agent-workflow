# Regression testing — protecting against Archon and Pi upgrades

`scripts/aw-regression-test` verifies every assumption our scripts make
about Archon and Pi. Run it before upgrading either tool, and after any
workflow-infrastructure change.

---

## Usage

```bash
python3 scripts/aw-regression-test           # all 45 tests (~70s)
python3 scripts/aw-regression-test archon    # Archon DB + CLI + YAML schema
python3 scripts/aw-regression-test pi        # Pi tools + extensions
python3 scripts/aw-regression-test scripts   # our own scripts
```

Exit 0 = all passed. Exit 1 = something broke. Every failure message names
the affected script and suggests a concrete fix.

---

## What each suite protects

### Suite 1 — Archon database (8 tests)

**Protects:** `scripts/aw-inspect`

| Test | What breaks if it fails |
|---|---|
| `remote_agent_workflow_runs` table exists | `aw-inspect` cannot find past runs |
| `remote_agent_workflow_events` table exists | `aw-inspect --events` and rate-limit parsing broken |
| `remote_agent_isolation_environments` table exists | `aw-run-all.sh` worktree discovery broken |
| `workflow_runs` has columns: id, workflow_name, user_message, status, started_at, working_path | `aw-inspect` crashes on column read |
| `workflow_events` has columns: id, workflow_run_id, event_type, step_name, data, created_at | `aw-inspect --events` crashes |
| event_type values include tool_called, tool_completed, node_completed, node_failed | `aw-inspect` cost/event summary returns empty |
| Per-run `.jsonl` log files exist in `~/.archon/workspaces/` | `print_rate_limit_info()` in `aw-run` never finds rate limit events |

**Trigger:** Archon renames tables, adds/removes columns, or changes event type strings between versions.

---

### Suite 2 — Archon CLI (8 tests)

**Protects:** `scripts/aw-run`, `scripts/aw-run-all.sh`

| Test | What breaks if it fails |
|---|---|
| `archon` in PATH | Everything |
| `archon workflow run --branch` flag exists | `aw-run` cannot create epic worktree |
| `archon workflow run --no-worktree` flag exists | `aw-run` iteration 2+ cannot reuse worktree |
| `archon workflow run --from-branch` flag exists | `aw-run --from-branch` flag silently ignored |
| `archon validate workflows` subcommand exists | `aw-run` skips validation, corrupt YAML runs silently |
| `archon isolation list` subcommand exists | `aw-run-all.sh` find_worktree() broken |
| `archon complete` subcommand exists | Worktree cleanup after convergence broken |

**Trigger:** Archon renames or removes subcommands/flags.

---

### Suite 3 — Archon workflow YAML schema (7 tests)

**Protects:** `.archon/workflows/aw-master-loop.template.yaml.tmpl`

| Test | What breaks if it fails |
|---|---|
| Template renders without error | No runs possible |
| Rendered YAML passes `archon validate` (0 errors) | Archon rejects the workflow at startup |
| All 11 nodes present (read-epic through decide) | Missing nodes silently skip the corresponding workflow phase |
| AI nodes have `idle_timeout` | Throttled model hangs the node for hours |
| No double-quoted `$node.output` in bash: blocks | GOTCHA-002 re-introduced: JSON with `"` breaks bash |
| AUTOCOMMIT markers present | `--no-autocommit` stops working; always commits |
| trigger_rule values are in {all_success, one_success, none_failed_min_one_success, all_done} | Archon rejects the workflow at validation |

**Trigger:** Archon adds required node fields, renames trigger_rule values, changes YAML schema. Also catches accidental re-introduction of GOTCHA-002 by us.

---

### Suite 4 — Pi contract (8 tests)

**Protects:** `.pi/extensions/*.ts`, `scripts/aw-run` (model validation)

| Test | What breaks if it fails |
|---|---|
| `pi` in PATH | All Pi sessions fail |
| Pi `bash` tool exists | `bash-normalize-exit.ts` intercepts nothing |
| Pi model ref format contains `/` | `aw-run` validation gives wrong advice; default models silently wrong |
| `~/.pi/agent/sessions/` exists | `aw-inspect --session` always returns "not found" |
| `.pi/extensions/` exists | All extensions silently not loaded |
| All extensions pass `biome check` | Pi refuses to load syntactically invalid extension |
| Events used in extensions exist: `tool_call`, `after_provider_response`, `message_end`, `agent_end` | Extensions silently don't fire; rate limits not detected |
| Extensions import from `@earendil-works/pi-coding-agent` | Extensions crash at load time with import error |

**Trigger:** Pi renames built-in tools, changes extension API events, renames the npm package, stops loading `.ts` files.

---

### Suite 5 — Our scripts (14 tests)

**Protects:** everything we ship

| Test | What breaks if it fails |
|---|---|
| `aw-run --dry-run` exits 0 | No runs possible |
| `aw-run` rejects `pi:sonnet` (bare model, no `/`) | Invalid model refs accepted silently |
| `aw-run` accepts `pi:github-copilot/claude-sonnet-4.6` | Valid models rejected |
| `aw-run-all.sh --dry-run` exits 0 | Orchestrator broken |
| `aw-decide.sh` CONVERGED / ITERATE / EXHAUSTED all work | Loop control broken; epics never converge or never stop |
| `aw-test-backend.sh` never exits 1 | GOTCHA-003 re-introduced: run-tests node marked FAILED, fix-blocked skipped |
| `update-codebase-summary.sh` runs and preserves markers | Context file corrupted; agents lose pre-digested facts |
| Rate limit log parser correctly extracts `claude.rate_limit_event` JSON | Rate limit diagnostics never fire |
| `aw-inspect` connects to DB without traceback | Observability broken |
| `gotchas-index.sh` regenerates INDEX.md | Gotchas lost; agents re-discover known bugs |

**Trigger:** Any regression introduced by our own changes, or by upstream changing the `claude.rate_limit_event` JSON format.

---

## When to run

```bash
# Before upgrading Archon
archon version   # check current
# ... upgrade ...
python3 scripts/aw-regression-test archon   # verify nothing broke

# Before upgrading Pi
pi --version
# ... upgrade ...
python3 scripts/aw-regression-test pi

# After any change to workflow infrastructure
python3 scripts/aw-regression-test scripts

# Full health check (e.g. after a long break)
python3 scripts/aw-regression-test
```

---

## Reading a failure

Every failed test prints three things:

```
FAIL: test_workflow_events_required_columns
----------------------------------------------------------------------
  MISSING: 'step_name'
  BREAKAGE: aw-inspect --events reads column 'step_name' from workflow_events
  FIX: Update aw-inspect to use the new column name for 'step_name'
```

- **MISSING / what was checked** — the exact value that wasn't found
- **BREAKAGE** — which of our scripts/features stops working
- **FIX** — the specific file or function to update

---

## Adding a new test

When you discover a new integration assumption (a new field we read, a new
CLI flag we pass, a new Pi API we use), add a test to the appropriate suite
in `scripts/aw-regression-test`:

```python
def test_my_new_assumption(self):
    """One sentence: what does this assumption protect?
    If Pi changes X, extension Y silently stops working."""
    # ... verify the assumption ...
    self.assertHas(
        something,
        "expected_value",
        breakage="scripts/my-script reads X from Y — if Y changes, script breaks",
        fix="Update scripts/my-script line N to use the new name",
    )
```

Use `self.assertHas(container, item, breakage=..., fix=...)` instead of
bare `assertIn` so the failure message is actionable.

---

## Skipped tests

Some tests skip when a precondition isn't met:

| Skip reason | What it means |
|---|---|
| `archon.db not found` | No Archon runs yet — run at least one workflow |
| `no rendered test YAML found` | Run `aw-run --dry-run X` first |
| `pnpm not in PATH` | `biome check` on extensions skipped |
| `aw-test-backend.sh not found` | Project-specific file; skip is expected on a fresh install |
| `~/.pi/agent/settings.json not found` | Pi not configured; model format test skipped |

Skips are not failures — they mean the test can't run in the current
environment, not that something is broken.
