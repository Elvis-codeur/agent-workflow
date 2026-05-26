# agent-workflow

Boilerplate for multi-agent software projects — installs the infrastructure
to run a fully automated coder ↔ tester loop via
[Archon](https://github.com/coleam00/Archon), with observability, rate-limit
detection, context efficiency, and regression tests to survive upstream upgrades.

---

## Install into a project

```bash
# Clone and run (recommended — avoids CDN caching):
git clone --depth=1 https://github.com/Elvis-codeur/agent-workflow.git /tmp/aw
bash /tmp/aw/install.sh /path/to/myproject
rm -rf /tmp/aw

# One-liner:
curl -fsSL https://raw.githubusercontent.com/Elvis-codeur/agent-workflow/main/install.sh \
  | bash -s -- /path/to/myproject
```

Safe to re-run — never overwrites files you have already customised.

---

## What gets installed

```
<project>/
├── AGENTS.md                           ← fill in your invariants + layout
├── CODEBASE-SUMMARY.md                 ← pre-digested facts for agents (~600 tokens)
├── CLAUDE.md                           ← thin Claude Code pointer (do not edit)
├── .pre-commit-config.yaml             ← uncomment the language tracks you use
├── .github/workflows/ci.yml            ← uncomment the CI jobs you need
├── scripts/
│   ├── check-invariants.sh             ← add your architectural checks here
│   ├── aw-run                          ← master-loop launcher (Archon)
│   ├── aw-configure.py                 ← phase-skip decision logic (configure node)
│   ├── aw-ci-preflight.sh              ← fast CI gates run before commit
│   ├── aw-run-all.sh                   ← topological orchestrator (all epics)
│   ├── aw-run-tests.sh                 ← project-agnostic test dispatcher
│   ├── aw-decide.sh                    ← loop decision: CONVERGED/ITERATE/FAILED
│   ├── aw-inspect                      ← observability CLI
│   ├── aw-regression-test              ← 45 integration regression tests
│   ├── update-codebase-summary.sh      ← regenerates CODEBASE-SUMMARY.md
│   └── gotchas-index.sh                ← regenerates docs/gotchas/INDEX.md
├── .archon/workflows/
│   └── aw-master-loop.template.yaml.tmpl   ← 16-node DAG, rendered per-run
├── .pi/
│   ├── extensions/
│   │   ├── bash-normalize-exit.ts      ← fixes grep exit 1 false alarms
│   │   └── rate-limit-notifier.ts      ← surfaces API throttling in real-time
│   └── settings.json                   ← Pi skill path configuration
├── docs/
│   ├── archon-master-loop.md           ← DAG design + operations guide
│   ├── observability.md                ← watching what agents did
│   ├── regression-testing.md           ← preventing upstream breakage
│   └── gotchas/
│       ├── INDEX.md                    ← auto-generated; agents read at Step 0
│       └── _TEMPLATE.md
└── docs/agent-rules/
    └── skills/
        ├── write-progress/SKILL.md
        ├── implement-epic/SKILL.md
        ├── test-and-progress/SKILL.md
        ├── fix-blocked/SKILL.md
        ├── aw-master-loop/SKILL.md
        ├── record-gotcha/SKILL.md
        ├── commit/SKILL.md
        └── update-docs/SKILL.md
.claude/skills      → docs/agent-rules/skills  (symlink)
.opencode/commands  → docs/agent-rules/skills  (symlink)
.pi/skills          → docs/agent-rules/skills  (symlink)
```

---

## After install — four things to customise

1. **`AGENTS.md`** — add your project layout and architectural invariants.
2. **`scripts/check-invariants.sh`** — add `check` calls for your project rules.
3. **`.pre-commit-config.yaml` and `ci.yml`** — uncomment the language tracks you use.
4. **`scripts/aw-test-<scope>.sh`** — add project-specific test runners
   (e.g. `aw-test-backend.sh`, `aw-test-frontend.sh`) so the workflow runs
   the right tests for each epic scope.

---

## Running an epic end-to-end

```bash
# One epic
scripts/aw-run BE-31

# All open epics in dependency order
scripts/aw-run-all.sh

# Dry-run: see the 6-layer plan without running anything
scripts/aw-run-all.sh --dry-run

# Resume after a stop
scripts/aw-run-all.sh --from BE-37

# Override models per-run — Pi, Claude Code, or Codex

# Pi (default — GitHub Copilot tier)
scripts/aw-run \
  --coder  pi:github-copilot/claude-sonnet-4.6 \
  --tester pi:github-copilot/gpt-5.3-codex \
  BE-31

# Claude Code CLI  (requires: curl -fsSL https://claude.ai/install.sh | bash)
scripts/aw-run \
  --coder  claude:sonnet \
  --tester claude:sonnet \
  --master claude:opus \
  BE-31

# OpenAI Codex CLI  (requires: npm install -g @openai/codex)
scripts/aw-run \
  --coder  codex:gpt-5.3-codex \
  --tester codex:gpt-5.3-codex \
  BE-31

# Mix providers freely per role
scripts/aw-run \
  --coder  claude:sonnet \
  --tester codex:gpt-5.3-codex \
  --master pi:github-copilot/gpt-5.2 \
  BE-31
```

**Defaults** (Pi provider, chosen for throughput):
- coder: `pi:github-copilot/claude-sonnet-4.6` — strong coding ability, 1M context
- tester: `pi:github-copilot/gpt-5.3-codex` — different model from coder = independent signal; code-optimised
- master: `pi:github-copilot/gpt-5.2` — strong reasoning, used only for arbitration

**All three providers are fully supported:**

| Provider | Format | Prerequisite |
|---|---|---|
| `pi` | `pi:<catalog-provider>/<model-id>` | Pi coding agent (default) |
| `claude` | `claude:<alias-or-full-id>` | `curl -fsSL https://claude.ai/install.sh \| bash` |
| `codex` | `codex:<model-id>` | `npm install -g @openai/codex` |

**Phase-skip flags** (save tokens on repeat runs):
```bash
scripts/aw-run --tests-only FE-52    # skip implement; write + run tests
scripts/aw-run --reuse-tests FE-02   # skip implement + write-tests; just run
```
Auto-detected: if an epic is already `review`/`complete`, `implement` is skipped
without any flag. See `docs/archon-master-loop.md` for full details.

Requires `archon` ≥ v0.3.10 in PATH.
Full design: `docs/archon-master-loop.md`.

---

## What happens inside one epic run

```
read-epic → configure → implement → write-tests → run-tests ──(PASS)──► ci-check ──► promote-complete → commit → update-context → decide
                                                    │                        │
                                                    │                        └──(FAIL)──► fix-ci → rerun-ci ──► promote-complete
                                                    │
                                                    └──(FAIL)──► fix-blocked → rerun-tests
                                                                                    │
                                                                       (still FAIL) └──► arbitrate → ask-human
```

1. **read-epic** — parses the epic JSON from `progress.*.yaml`
2. **configure** — bash node reads epic status + checks test-file presence; emits JSON skip flags
   (`skip_implement`, `skip_write_tests`, `mode`). No AI tokens.
3. **implement** — coder runs gate commands, marks `review`; reads `CODEBASE-SUMMARY.md` at Step 0 to skip ~5 000 tokens of codebase exploration. *Skipped automatically* when epic is `review`/`complete`.
4. **write-tests** — tester writes test files independently (fresh context). *Skipped automatically* if all test files already exist.
5. **run-tests** — project-specific bash runner (`scripts/aw-test-<scope>.sh`)
6. **fix-blocked** — coder fixes failures, up to `--max-fix-attempts` rounds
7. **rerun-tests** — reruns tests after fix-blocked
8. **arbitrate** — master classifies the coder/tester disagreement into one of 8 buckets, emits `coder_right` / `tester_right` / `unsure`
9. **ask-human** — only fires on `unsure`; the one point where the workflow blocks on input
10. **ci-check** — runs fast CI gates (`aw-ci-preflight.sh`): lint, typecheck, lockfile integrity, migrations
11. **fix-ci** — coder fixes CI-only issues (format drift, stale locks, missing migrations); does not touch tests
12. **rerun-ci** — reruns CI gates after fix-ci
13. **promote-complete** — when tests + CI pass, updates `progress.<scope>.yaml` to `status: complete`
14. **commit** — runs `/commit` skill; never pushes, never opens a PR
15. **update-context** — regenerates `CODEBASE-SUMMARY.md` (zero AI tokens); appends one-line epic log entry
16. **decide** — writes `CONVERGED`/`EXHAUSTED`/`ITERATE`/`FAILED`; `aw-run` reads this and either cleans up or loops

All six AI nodes (`implement`, `write-tests`, `fix-blocked`, `arbitrate`, `fix-ci`, `commit`) have `idle_timeout: 120s` — a throttled model that stops responding is killed within 2 minutes.

---

## Observability

```bash
archon serve                                          # web UI at localhost:3090
scripts/aw-inspect BE-31                              # cost + duration per node
scripts/aw-inspect BE-31 --events | less              # every file read, every bash command
scripts/aw-inspect BE-31 --session                    # print resume command for detected provider
eval "$(scripts/aw-inspect BE-31 --session)"          # resume directly (pi / claude / codex)
```

Full guide: `docs/observability.md`.

---

## Rate limit detection

When GitHub Copilot (or any provider) throttles a session, you now see:

```
============================================================
  ⛔  RATE LIMIT DETECTED IN THIS RUN
============================================================
  Limit type : 5-hour rolling window
  Reason     : out_of_credits
  Resets at  : 2026-05-23 15:10:00 (in 37 min)

  💡 Switch model: scripts/aw-run --coder pi:github-copilot/claude-sonnet-4.6 EPIC
============================================================
```

This is printed by `scripts/aw-run` after any failed run. The
`rate-limit-notifier.ts` Pi extension also shows it in real-time in the TUI
during a session.

---

## Gotchas registry — institutional memory

When an agent hits a bug that isn't part of the epic's acceptance criteria
(toolchain quirk, env hazard, codegen oddity), the `/record-gotcha` skill
writes it to `docs/gotchas/`. `scripts/gotchas-index.sh` keeps `INDEX.md`
in sync. Every agent reads the index at Step 0 so the bug isn't rediscovered.

Three gotchas are pre-loaded from building this workflow:

| ID | What it prevents |
|---|---|
| GOTCHA-001 | Pi `bash` tool reporting `grep` exit 1 as a tool failure |
| GOTCHA-002 | Double-quoting `$node.output` in Archon bash: nodes breaking bash |
| GOTCHA-003 | Archon worktree venv having no packages → 63 xfail instead of running |
| GOTCHA-004 | Test runner exits 1 → `fix-blocked` skipped; tests never fixed |
| GOTCHA-005 | `aw-decide.sh` writes marker to worktree → `state=UNKNOWN`, merges skipped |
| GOTCHA-006 | pnpm install stdout before PASS → `== 'PASS'` never matches |

---

## Regression tests — surviving Archon and Pi upgrades

```bash
# Before upgrading Archon or Pi, run this first:
python3 scripts/aw-regression-test

# Filter by area:
python3 scripts/aw-regression-test archon    # DB schema + CLI flags + YAML
python3 scripts/aw-regression-test pi        # tools + extensions + model format
python3 scripts/aw-regression-test scripts   # our own scripts
```

45 tests across 5 suites. Each failure names the affected script and gives
a concrete fix. Full guide: `docs/regression-testing.md`.

---

## Skills

On-demand procedural workflows — agents load them by reading `SKILL.md`
rather than relying on prose rules they may forget in long sessions.

| Skill | Trigger | What it does |
|---|---|---|
| `/write-progress` | "plan epic X" | Authors or extends a `progress.*.yaml` |
| `/implement-epic` | (called by `implement` node) | Implements an epic end-to-end; marks `review` |
| `/test-and-progress` | (called by `write-tests` node) | Mode A: writes tests; Mode B: runs + reports |
| `/fix-blocked` | (called by `fix-blocked` node) | Fixes failing tests, stays in scope |
| `/aw-master-loop` | (called by `arbitrate` node) | Classifies coder/tester disagreement |
| `/record-gotcha` | "record this bug" | Writes to `docs/gotchas/` + epic's `gotchas:` list |
| `/commit` | (called by `commit` node) | lint → typecheck → test → stage → conventional commit |
| `/update-docs` | "update docs" | keep README, design docs, gotchas, and regression tests in sync |

---

## Cross-tool skill coverage

| Tool | Auto-loads skills? | How |
|---|---|---|
| Claude Code | ✅ | `.claude/skills/` symlink |
| Pi | ✅ | `.pi/skills/` symlink + `.pi/settings.json` |
| OpenCode | ⚠️ read-on-demand | `.opencode/commands/` symlink; agent reads via AGENTS.md pointer |
| Codex | ⚠️ read-on-demand | No skill mechanism; agent reads via AGENTS.md pointer |

---

## License

MIT
