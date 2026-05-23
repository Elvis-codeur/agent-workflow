# Agent Guidelines

You are working on **{{PROJECT_NAME}}**. Full architecture: `docs/specs/`.
This file lists what mechanical checks cannot enforce.

## Authority order

When guidance conflicts, follow this order:

1. **Mechanical gates** — pre-commit hooks, CI, type checkers, schema
   validators. If a gate fails, fix the cause; never bypass.
2. **Skills** at `docs/agent-rules/skills/<name>/SKILL.md`. Aliased into
   `.claude/skills/`, `.opencode/commands/`, and `.pi/skills/`. Invoke when
   starting a recurring workflow. Codex has no native skill loader — open
   the SKILL.md file directly and follow its body.
3. **This file** — invariants that cannot be mechanized.
4. **Architecture docs** — `docs/specs/` and `docs/agent-rules/`.

If you are fighting a gate, the gate is probably right.

## Project layout

```
# Fill in your project's directory tree here.
# Example:
apps/        deployables — frontend, backend, desktop
packages/    libraries — shared code, schemas, utilities
docs/        specs/ (architecture), agent-rules/ (this kind of rule)
scripts/     dev tooling
tests/       cross-package integration / validation
```

## Architectural invariants

Each is also enforced by `scripts/check-invariants.sh`, but the grep is a
floor. Read the rationale before circumventing.

<!-- Add your project's invariants here. Example format:

1. **No synchronous I/O on the main thread.** The UI must never block on
   disk or network operations.
   → `docs/agent-rules/architecture-invariants.md#no-sync-io`

2. **Single store, no local component state.** All application state lives
   in the global store; components are pure views.
   → `docs/agent-rules/architecture-invariants.md#single-store`
-->

## Commit conventions

Conventional Commits enforced by the `commit-msg` hook. Types: `feat`,
`fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`,
`revert`. Scope optional. `!` after type for breaking changes.

```
feat(canvas): add orthogonal wire router
fix(kernel): handle stdout chunks > 64KB
refactor!: rename public API fields
```

Use `/commit` to draft the message from the diff.

## Recurring workflows → use the skill

| Task | Skill | Path |
|---|---|---|
| Author or extend a progress file | `/write-progress` | `docs/agent-rules/skills/write-progress/` |
| Implement an epic (coder-agent) | `/implement-epic` | `docs/agent-rules/skills/implement-epic/` |
| Write or run tests + update progress | `/test-and-progress` | `docs/agent-rules/skills/test-and-progress/` |
| Fix a blocked epic (coder-agent) | `/fix-blocked` | `docs/agent-rules/skills/fix-blocked/` |
| Master arbitration (coder ↔ tester tie-break) | `/aw-master-loop` | `docs/agent-rules/skills/aw-master-loop/` |
| Record an off-epic bug for future agents | `/record-gotcha` | `docs/agent-rules/skills/record-gotcha/` |
| Lint + test + commit | `/commit` | `docs/agent-rules/skills/commit/` |

When invoking from Codex / ChatGPT (no skill mechanism): open the SKILL.md
file directly. Its body is the procedure.

## Run a full epic end-to-end (Archon master loop)

For any epic in a `progress.*.yaml` file, you can run the coder/tester loop
without babysitting it:

```bash
scripts/aw-run <EPIC-ID>
# zero flags = defaults: master=pi:github-copilot/claude-sonnet-4.6, coder=pi:github-copilot/claude-sonnet-4.6,
#              tester=pi:github-copilot/claude-sonnet-4.6, max-fix=3, max-arb=3, autocommit ON,
#              worktree cleanup ON.

scripts/aw-run --coder pi:kiro/minimax-m2-5 \
               --tester pi:github-copilot/claude-sonnet-4.6 \
               --master claude:opus \
               --max-fix-attempts 5 \
               --no-autocommit \
               EPIC-AUTH-001
```

The wrapper renders `.archon/workflows/aw-master-loop.template.yaml` with
the chosen per-role provider/model triples and invokes Archon in an
isolated git worktree. See `docs/archon-master-loop.md` for the full
design. Requires `archon` v0.3.10+ in `PATH`
(https://github.com/coleam00/Archon).

### Off-epic bugs (gotchas)

If an agent hits a bug NOT covered by `implementation.acceptance` while
working an epic (toolchain quirk, env-specific path, cross-filesystem
hazard), they must invoke `/record-gotcha` and append an entry to the
epic's `gotchas:` list before continuing. Short entries are inline (≤ 5
lines); anything bigger gets a long-form `docs/gotchas/GOTCHA-NNN-*.md`
with reproduction conditions, indexed automatically by
`scripts/gotchas-index.sh` (runs in the pre-commit hook).

## What NOT to do

- Don't bypass pre-commit hooks with `--no-verify`. Fix the issue.
- Don't introduce abstractions without an existing call site. Three similar
  lines beats a premature abstraction.
- Don't add backwards-compatibility shims for code that has never shipped.
- Don't comment WHAT code does. Name things clearly. Comment only the
  non-obvious WHY.
- Don't claim a task complete if CI is red.
- Don't duplicate content across `AGENTS.md`, `CLAUDE.md`, and skill files.
  Link to `docs/agent-rules/` instead. There is one source of truth per rule.
- **When asked to write tests**: write the test files, then stop. Do not run
  them. The coder-agent may not have finished the implementation.
- **When running tests as tester-agent**: record the result in the progress
  file and stop. Do not fix failing implementation code — that is the
  coder-agent's job. Use `/test-and-progress` for the full protocol.

## Tool-specific notes

- **Claude Code** reads this file plus `CLAUDE.md` (a thin pointer here).
  Skills live at `.claude/skills/` (symlink → `docs/agent-rules/skills`).
- **OpenCode** reads this file plus `.opencode/commands/` (symlink → same
  target). Note: OpenCode expects `<name>.md` flat files while skills here
  use `<name>/SKILL.md` directories. A flattener script may be needed when
  OpenCode becomes a primary tool.
- **Codex** reads this file. No skill mechanism — open the SKILL.md path
  from the table above directly.
- **Cursor / Aider / others**: read this file. Add a tool-specific shim if
  needed; do not duplicate rules.
