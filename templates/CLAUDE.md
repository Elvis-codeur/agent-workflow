# Claude Code — Project Notes

The canonical agent guidance is in [`AGENTS.md`](./AGENTS.md). Read it
first. This file holds only Claude-Code-specific addenda.

## Claude-Code-specific addenda

- **Skills.** `.claude/skills/` is a symlink to `docs/agent-rules/skills/`.
  Browse skills by name; each is a directory containing `SKILL.md`.
- **`/commit`.** Built-in Claude Code skill. The conventional-commits
  `commit-msg` hook enforces format, so `/commit` is safe to use as-is.
- **`/init`.** Do **not** re-run init in this repo — `CLAUDE.md` and
  `AGENTS.md` are already authored.
- **Hooks.** Pre-commit hooks are installed at `.git/hooks/`. If a hook
  blocks you, do not pass `--no-verify`. Fix the underlying issue.

For everything else: [`AGENTS.md`](./AGENTS.md).
