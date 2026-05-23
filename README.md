# agent-workflow

Boilerplate for multi-agent software projects.

Provides:

- **AGENTS.md** — cross-tool agent guide (Claude Code, Codex, OpenCode, Pi, ChatGPT)
- **Pre-commit hooks** — conventional commits, file hygiene, gotchas-index regen, language linters
- **CI skeleton** — GitHub Actions jobs with pluggable language tracks
- **Architectural-invariant framework** — `check-invariants.sh` with a `check()` helper
- **Skills** — on-demand procedural workflows for agents:
  - `/write-progress` — author or extend a `progress.*.yaml` epic plan
  - `/implement-epic` — coder-agent: implement an epic, run gates, mark review
  - `/test-and-progress` — tester-agent: write tests (Mode A) or run + report (Mode B)
  - `/fix-blocked` — coder-agent: fix a blocked epic from tester feedback
  - `/aw-master-loop` — master-agent: arbitrate coder/tester ties, ask the human when unsure
  - `/record-gotcha` — capture off-epic bugs (toolchain, env, codegen) for future agents
  - `/commit` — gate-checked commit: lint → typecheck → test → stage → commit
- **Archon master loop** — `scripts/aw-run <EPIC-ID>` runs the full
  coder/tester ping-pong end-to-end via [Archon](https://github.com/coleam00/Archon),
  picking which model plays each role and arbitrating disagreements
  automatically. See `docs/archon-master-loop.md`.
- **Gotchas registry** — `docs/gotchas/` + auto-generated `INDEX.md` so
  the bug one agent discovers doesn't burn another agent's tokens.
- **Symlinks** — `.claude/skills/`, `.opencode/commands/`, and `.pi/skills/`
  all point to the skill tree.

---

## Install into a project

```bash
# Recommended — clone and run (always works, no CDN caching issues):
git clone --depth=1 https://github.com/Elvis-codeur/agent-workflow.git /tmp/aw
bash /tmp/aw/install.sh /path/to/myproject   # or . for current directory
rm -rf /tmp/aw

# Convenience one-liner (may serve a cached script for a few minutes after updates):
curl -fsSL https://raw.githubusercontent.com/Elvis-codeur/agent-workflow/main/install.sh | bash -s -- /path/to/myproject
```

The script is safe to re-run — it will not overwrite files you have already customised unless you pass `--force`.

---

## What gets installed

```
<your-project>/
├── AGENTS.md                          ← fill in your invariants + layout
├── CLAUDE.md                          ← thin Claude Code pointer (do not edit)
├── .pre-commit-config.yaml            ← uncomment the language tracks you use
├── .github/workflows/ci.yml           ← uncomment the CI jobs you need
├── scripts/
│   ├── check-invariants.sh            ← add your architectural checks here
│   ├── aw-run                         ← master-loop launcher (Archon)
│   ├── aw-run-tests.sh                ← project-agnostic test node
│   ├── aw-decide.sh                   ← loop-driver decision logic
│   └── gotchas-index.sh               ← regenerates docs/gotchas/INDEX.md
├── .archon/workflows/
│   └── aw-master-loop.template.yaml.tmpl   ← rendered per-run by aw-run
├── docs/
│   ├── gotchas/
│   │   ├── INDEX.md                   ← auto-generated; read at Step 0
│   │   └── _TEMPLATE.md
│   └── agent-rules/
│       ├── skills/
│       │   ├── write-progress/SKILL.md
│       │   ├── implement-epic/SKILL.md
│       │   ├── test-and-progress/SKILL.md
│       │   ├── fix-blocked/SKILL.md
│       │   ├── aw-master-loop/SKILL.md
│       │   ├── record-gotcha/SKILL.md
│       │   └── commit/SKILL.md
│       └── orientation.md                 ← fill in your project-specific nav
.claude/skills      -> docs/agent-rules/skills   (symlink)
.opencode/commands  -> docs/agent-rules/skills   (symlink)
.pi/skills          -> docs/agent-rules/skills   (symlink)
.pi/settings.json                                 ← makes pi load the same tree
```

---

## After install — three things to customise

1. **`AGENTS.md`** — add your project layout and architectural invariants.
2. **`scripts/check-invariants.sh`** — add `check` calls for your project rules.
3. **`.pre-commit-config.yaml` and `ci.yml`** — uncomment the language tracks you use.

Everything else works out of the box.

---

## The two-agent-track model

Every epic in a `progress.*.yaml` file has two independent tracks:

- **coder-agent** — implements `implementation.paths`, runs gates, marks `review`
- **tester-agent** — writes `tests.paths`, runs them, marks `complete` or `blocked`

The separation gives you an independent test signal: the tester never fixes code,
and the coder never writes the tests that verify their own work.

Skills encode the exact procedure for each role. Agents load a skill on demand
rather than relying on prose rules they may forget in long sessions.

---

## Running an epic end-to-end — the Archon master loop

`scripts/aw-run <EPIC-ID>` drives the full coder/tester ping-pong without a
human in the loop:

```bash
scripts/aw-run EPIC-AUTH-001
# defaults: master=pi:sonnet, coder=pi:sonnet,
#           tester=pi:sonnet, max-fix=3, max-arb=3,
#           autocommit ON, worktree cleanup ON.

scripts/aw-run --coder pi:kiro/minimax-m2-5 \
               --tester pi:sonnet \
               --master claude:opus \
               --max-fix-attempts 5 \
               --no-autocommit \
               EPIC-AUTH-001
```

Under the hood:

1. The wrapper renders `.archon/workflows/aw-master-loop.template.yaml.tmpl` with
   the chosen per-role provider/model triples.
2. [Archon](https://github.com/coleam00/Archon) creates an isolated git
   worktree and runs the DAG: `read-epic → implement (loop) → write-tests →
   run-tests → (on fail) fix-blocked (loop) → arbitrate → (unsure) ask-human
   → commit → decide`.
3. The `decide` node writes a one-word state (`CONVERGED` / `EXHAUSTED` /
   `ITERATE` / `FAILED`) that the wrapper reads to decide whether to recurse,
   clean up the worktree, or hard-fail with `BLOCKED-ARBITRATION-EXHAUSTED`.
4. Each AI node can be assigned to **pi**, **claude**, or **codex** — mix
   and match per role. Default for all three roles: `pi:sonnet`.

Requires `archon` v0.3.10+ in `PATH`. See `docs/archon-master-loop.md` for
the full design and `skills/aw-master-loop/SKILL.md` for the arbitration
procedure.

---

## Gotchas — institutional memory for off-epic bugs

Agents working on one epic frequently hit bugs that are NOT part of that
epic's acceptance criteria — a toolchain quirk, a cross-filesystem hazard,
a codegen oddity. Losing this knowledge is expensive: the next agent
rediscovers it from zero.

The `/record-gotcha` skill writes these findings to `docs/gotchas/` (with a
full reproduction recipe when needed) and adds a 5-line summary to the
epic's `gotchas:` list. `scripts/gotchas-index.sh` (run by the pre-commit
hook) keeps `docs/gotchas/INDEX.md` in sync. Every skill's Step 0 reads
the index before starting work.

---

## Adding project-specific skills

Add a directory under `docs/agent-rules/skills/<name>/SKILL.md`.
Register it in `AGENTS.md` skills table and in `docs/agent-rules/orientation.md`.
The symlinks pick it up automatically.

---

## License

MIT
