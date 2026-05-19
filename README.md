# agent-workflow

Boilerplate for multi-agent software projects.

Provides:

- **AGENTS.md** — cross-tool agent guide (Claude Code, Codex, OpenCode, ChatGPT)
- **Pre-commit hooks** — conventional commits, file hygiene, language linters
- **CI skeleton** — GitHub Actions jobs with pluggable language tracks
- **Architectural-invariant framework** — `check-invariants.sh` with a `check()` helper
- **Skills** — on-demand procedural workflows for agents:
  - `/write-progress` — author or extend a `progress.*.yaml` epic plan
  - `/implement-epic` — coder-agent: implement an epic, run gates, mark review
  - `/test-and-progress` — tester-agent: write tests (Mode A) or run + report (Mode B)
  - `/fix-blocked` — coder-agent: fix a blocked epic from tester feedback
  - `/commit` — gate-checked commit: lint → typecheck → test → stage → commit
- **Symlinks** — `.claude/skills/` and `.opencode/commands/` both point to the skill tree

---

## Install into a project

```bash
# Into the current directory:
curl -fsSL https://raw.githubusercontent.com/Elvis-codeur/agent-workflow/main/install.sh | bash

# Into a specific directory:
curl -fsSL https://raw.githubusercontent.com/Elvis-codeur/agent-workflow/main/install.sh | bash -s -- /path/to/myproject

# Or clone and run locally:
git clone https://github.com/Elvis-codeur/agent-workflow.git
./agent-workflow/install.sh /path/to/myproject
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
│   └── check-invariants.sh            ← add your architectural checks here
└── docs/agent-rules/
    ├── skills/
    │   ├── write-progress/SKILL.md
    │   ├── implement-epic/SKILL.md
    │   ├── test-and-progress/SKILL.md
    │   ├── fix-blocked/SKILL.md
    │   └── commit/SKILL.md
    └── orientation.md                 ← fill in your project-specific nav
.claude/skills -> docs/agent-rules/skills   (symlink)
.opencode/commands -> docs/agent-rules/skills (symlink)
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

## Adding project-specific skills

Add a directory under `docs/agent-rules/skills/<name>/SKILL.md`.
Register it in `AGENTS.md` skills table and in `docs/agent-rules/orientation.md`.
The symlinks pick it up automatically.

---

## License

MIT
