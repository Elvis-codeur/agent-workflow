# Archon master-loop — design and operations guide

Drives the full coder ↔ tester ping-pong for one epic without a human in
the loop. The [Archon](https://github.com/coleam00/Archon) workflow engine
dispatches each AI role to a separate Pi session and arbitrates disagreements
automatically.

---

## Quick start

```bash
# Run all open epics in dependency order (recommended)
scripts/aw-run-all.sh

# Run one epic
scripts/aw-run BE-31

# Run with non-default models
scripts/aw-run \
  --coder  pi:github-copilot/claude-sonnet-4.6 \
  --tester pi:github-copilot/gpt-5.3-codex \
  --master pi:github-copilot/gpt-5.2 \
  BE-31

# Dry-run (render YAML, validate, then exit)
scripts/aw-run --dry-run BE-31

# See what a past run did
scripts/aw-inspect BE-31
scripts/aw-inspect BE-31 --events | less
pi --resume "$(scripts/aw-inspect BE-31 --session)"
```

---

## DAG — 16 nodes

```
read-epic
  └─► configure ────────────────────────────────────────────────────────────┐
        └─► implement ─(if skip_implement=false)──────────────────────────  │
              └─► write-tests ─(if skip_write_tests=false)─────────────── │ │
                    └─► run-tests ──(PASS)──► ci-check ──► promote-complete ──► commit ──► update-context ──► decide
                          │                    │
                          │                    └──(FAIL)──► fix-ci ──► rerun-ci ──► promote-complete
                          │
                          └──(FAIL)──► fix-blocked ──► rerun-tests
                                                           │
                                            (FAIL) ──► arbitrate ──► ask-human
```

| Node | Type | Role | What it does |
|---|---|---|---|
| `read-epic` | AI (master) | reads the epic JSON from `progress.*.yaml` |
| `configure` | bash | reads epic status + test-file presence; outputs JSON skip flags |
| `implement` | AI (coder, **skippable**) | implements, runs gates, marks `review` |
| `write-tests` | AI (tester, fresh ctx, **skippable**) | Mode A: writes test files |
| `run-tests` | bash | calls `scripts/aw-run-tests.sh` → `scripts/aw-test-<scope>.sh` |
| `fix-blocked` | AI (coder) | fixes failing tests, up to `--max-fix-attempts` attempts |
| `rerun-tests` | bash | same as run-tests, after fix-blocked |
| `arbitrate` | AI (master) | classifies disagreement into one of 8 buckets, emits verdict JSON |
| `ask-human` | AI (master) | prompts the user when arbitrate returns `unsure` |
| `ci-check` | bash | runs `scripts/aw-ci-preflight.sh`: lint, typecheck, lockfiles, migrations |
| `fix-ci` | AI (coder) | fixes CI-only failures (format drift, stale locks, missing migrations) |
| `rerun-ci` | bash | re-runs CI gates after fix-ci |
| `promote-complete` | bash | marks epic `status: complete` in `progress.<scope>.yaml` after tests+CI pass |
| `commit` | AI (master) | runs `/commit` skill — never pushes, never opens a PR |
| `update-context` | bash | regenerates `CODEBASE-SUMMARY.md`; appends epic log line |
| `decide` | bash | writes `CONVERGED`/`EXHAUSTED`/`ITERATE`/`FAILED` to `.archon/state/` |

`implement`, `write-tests`, `fix-blocked`, `arbitrate`, `fix-ci`, and `commit` all have
`idle_timeout: 120000` (2 minutes). If the model stops generating tokens for
2 minutes, Archon kills the node and `decide` writes `FAILED` so `aw-run` can
break the loop rather than hanging for hours.

---

## Default models

Chosen for throughput — `claude-sonnet-4.6` throttles heavily under sequential
session load on the GitHub Copilot tier.

| Role | Default | Rationale |
|---|---|---|
| coder | `pi:github-copilot/claude-sonnet-4.6` | Strong coding ability, 1M ctx |
| tester | `pi:github-copilot/gpt-5.3-codex` | Different model from coder = independent signal; code-optimised |
| master | `pi:github-copilot/gpt-5.2` | Strong reasoning; only runs on arbitration (rare) |
| max fix attempts | `3` | `--max-fix-attempts N` |
| max arbitration attempts | `3` | `--max-arbitration-attempts N` |
| autocommit | **on** | `--no-autocommit` |
| worktree cleanup | **on** | `--keep-worktree` |
| base branch | repo default (main) | `--from-branch BRANCH` |

**Pi model ref format**: `pi:<catalog-provider>/<model-id>`.  
Run `pi list-models` to see all available models.  
`aw-run` validates the format and exits 2 with a clear error if `/` is missing.

---


---

## Phase-skip flags — save tokens on repeat runs

The `configure` node auto-detects skippable phases. No flags needed in most
cases:

| Condition | Auto action |
|---|---|
| Epic `status == review` or `complete` | `implement` skipped |
| `skip_implement` + all test files exist in worktree | `write-tests` also skipped |

**Manual overrides:**

```bash
# Skip implement: write tests if missing, then run
scripts/aw-run --tests-only FE-52

# Skip implement AND write-tests: just run existing tests
scripts/aw-run --reuse-tests FE-02

# Granular
scripts/aw-run --skip-implement BE-35
scripts/aw-run --skip-write-tests BE-35

# All flags work with aw-run-all.sh too:
scripts/aw-run-all.sh -- --reuse-tests
```

**Example savings:**
- FE-02 was at `status: complete` — a new run would auto-detect and skip both
  `implement` (~90s, ~15k tokens) and `write-tests` (~50s, ~8k tokens),
  going straight to `run-tests` → `commit` → `decide: CONVERGED`.
- An epic at `review` with test files present → same skip path.
- An epic at `planned` with no test files → full run (`mode: full`).

The configure output is visible in the workflow log:
```
configure: mode=reuse-tests  skip_impl=True  skip_tests=True
           status='complete'  tests_exist=True
```

---

## Running all epics — `aw-run-all.sh`

Reads both `progress.*.yaml` files, builds a topological dependency graph,
and runs epics layer by layer:

```bash
scripts/aw-run-all.sh                        # all open epics
scripts/aw-run-all.sh --scope backend        # backend only
scripts/aw-run-all.sh --from BE-37           # resume after a stop
scripts/aw-run-all.sh --continue-on-error    # log failures, keep going
scripts/aw-run-all.sh --workers 2            # 2 epics in parallel per layer
scripts/aw-run-all.sh --dry-run              # print the 6-layer plan, exit
scripts/aw-run-all.sh -- --max-fix-attempts 5  # extra flags forwarded to aw-run
```

After each converged epic, `aw-run-all.sh` merges the worktree branch to
`main` and pushes before starting the next epic.

Logs are saved to `.archon/run-all-logs/<EPIC-ID>.log`.

---

## Context efficiency — CODEBASE-SUMMARY.md

Without this file, each coder/tester session burns ~5 000 tokens exploring
the codebase from scratch (running `ls`, `cat`, `grep` to discover which
packages exist, where tests live, what the gate commands are).

`CODEBASE-SUMMARY.md` pre-digests this into ~600 tokens. Every `implement`,
`write-tests`, and `fix-blocked` node prompt starts with:

```
Step 0 — read context first:
1. CODEBASE-SUMMARY.md           ← module layout, gate commands, test index
2. docs/gotchas/INDEX.md          ← known bugs; skip unless scope overlaps
3. progress.<scope>.yaml          ← confirm epic status + acceptance criteria
```

The `update-context` bash node regenerates the `<!-- AUTO-GENERATED -->` section
after every successful commit — zero AI tokens, pure Python parsing
`pyproject.toml` and `pnpm-workspace.yaml`. The `<!-- AGENT-MAINTAINED -->`
section (architectural patterns, recent epic changes) is appended automatically
by the workflow with one line per epic, also zero AI tokens.

To regenerate manually:
```bash
bash scripts/update-codebase-summary.sh
```

---

## Rate limit detection

GitHub Copilot throttles aggressively under sequential session load. Two
surfaces expose rate limit events:

**During a Pi session** (`rate-limit-notifier.ts` extension, auto-loaded):
- Catches HTTP 429 with `retry-after` headers → prints reset time in the TUI
- Catches model-reported quota messages (`"out of credits"`, `"rate limit"`, etc.)
- Catches Archon's forwarded `claude.rate_limit_event` JSON

**After a failed `scripts/aw-run`**:
```
============================================================
  ⛔  RATE LIMIT DETECTED IN THIS RUN
============================================================
  Limit type : 5-hour rolling window
  Reason     : out_of_credits
  Resets at  : 2026-05-23 15:10:00 (in 37 min)

  💡 Suggestions:
     Wait for the reset, then re-run: scripts/aw-run EPIC-ID
     Or switch model: --coder pi:github-copilot/gpt-5.3-codex
============================================================
```

The rate limit info is parsed from the Archon run log in
`.archon/run-all-logs/<EPIC-ID>.log` and from
`~/.archon/workspaces/.../logs/<run-id>.jsonl`.

---

## Observability

See `docs/observability.md` for the full guide. Quick reference:

```bash
archon serve                                   # web UI at localhost:3090
scripts/aw-inspect BE-31                       # cost + duration per node
scripts/aw-inspect BE-31 --events | less       # every tool call
scripts/aw-inspect BE-31 --session             # print resume command (auto-detects pi/claude/codex)
eval "$(scripts/aw-inspect BE-31 --session)"   # execute it directly
```

---

## Known gotchas and mitigations

| Gotcha | What breaks | Mitigation |
|---|---|---|
| **GOTCHA-001** — Pi bash tool reports `grep` exit 1 as failure | Agent retries harmless searches repeatedly | `bash-normalize-exit.ts` extension normalises exit 1→0 for grep/find/ls |
| **GOTCHA-002** — Double-quoting `$node.output` in bash: nodes | Archon's single-quoted JSON re-wrapped in `"..."` breaks bash when JSON contains `"` | Never use `"$node.output"` in bash: blocks |
| **GOTCHA-003** — Archon worktree venv has no packages installed | Python tests xfail silently (ModuleNotFoundError caught by pytest.xfail) | `aw-test-backend.sh` runs `uv sync --all-packages` before pytest |
| **GOTCHA-004** — Test runner exits 1 → `fix-blocked` skipped | Tests fail but coder never fixes them; workflow goes to arbitrate | Test runners always exit 0; failure via stdout content only |
| **GOTCHA-005** — `aw-decide.sh` marker written to worktree, not main repo | `state=UNKNOWN`; all convergences treated as failures; merges skipped | Use `--git-common-dir` not `--show-toplevel` to find repo root |
| **GOTCHA-006** — pnpm install stdout leaks "Scope:" before PASS | `run-tests.output` is multiline; `== 'PASS'` never matches | Use `&>/dev/null` on install commands, not just `2>/dev/null` |

Full write-ups: `docs/gotchas/GOTCHA-00{1,2,3,4,5,6}-*.md`.

---

## Speed troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Node hangs for 20+ min on a trivial command | GitHub Copilot throttled — model queued | Switch model; `idle_timeout: 120s` will kill it and `decide` writes FAILED |
| Each epic takes 30+ min (was 5 min manually) | 3–4 sequential Pi sessions per epic hit rate limit | Use gpt-5.3-codex (coder) + gpt-5.3-codex (tester) — both have higher throughput than claude-sonnet-4.6 under sequential load |
| `claude.rate_limit_event` in log with `overageDisabledReason: out_of_credits` | 5-hour or monthly token quota reached | Wait for reset (shown in `resetsAt`), or switch provider |

---

## File map

```
.archon/
└── workflows/
    ├── aw-master-loop.template.yaml.tmpl   ← rendered per-run by aw-run
    ├── .runs/                              ← ephemeral rendered YAMLs (gitignored)
    └── .../                               ← other Archon-managed files
.pi/
├── extensions/
│   ├── bash-normalize-exit.ts             ← normalises grep/find/ls exit codes
│   └── rate-limit-notifier.ts             ← surfaces API throttling in real-time
└── settings.json                          ← Pi skill path configuration
scripts/
├── aw-run                                 ← renders template + calls archon
├── aw-configure.py                        ← phase-skip decision logic (configure node)
├── aw-ci-preflight.sh                     ← fast CI gates run before commit
├── aw-run-all.sh                          ← topological orchestrator
├── aw-run-tests.sh                        ← project-agnostic test dispatcher
├── aw-decide.sh                           ← CONVERGED/EXHAUSTED/ITERATE/FAILED
├── aw-inspect                             ← observability CLI
├── aw-regression-test                     ← 45 integration regression tests
├── update-codebase-summary.sh             ← regenerates CODEBASE-SUMMARY.md AUTO section
└── gotchas-index.sh                       ← regenerates docs/gotchas/INDEX.md
CODEBASE-SUMMARY.md                        ← pre-digested codebase facts for agents
docs/
├── archon-master-loop.md                  ← this file
├── observability.md                       ← watching what agents did
├── regression-testing.md                  ← preventing upstream breakage
└── gotchas/
    ├── INDEX.md                           ← auto-generated; agents read at Step 0
    ├── GOTCHA-001-pi-bash-exit-1.md
    ├── GOTCHA-002-archon-double-quote-node-output.md
    ├── GOTCHA-003-archon-worktree-no-uv-sync.md
    ├── GOTCHA-004-test-runner-must-exit-zero.md
    ├── GOTCHA-005-aw-decide-worktree-marker-path.md
    └── GOTCHA-006-pnpm-stdout-leaks-into-pass-check.md
```
