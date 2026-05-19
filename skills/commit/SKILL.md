---
name: commit
description: Gate-checked commit workflow — runs lint and full test suite before staging any files, then creates a conventional-commit message from the diff.
---

# `/commit` — Lint, test, then commit

Use this skill whenever you are about to commit changes — whether you are the
coder-agent, tester-agent, or any other agent role. No agent may attempt a
`git commit` without completing every step below first.

> **Non-negotiable.** This gate applies to every agent, every task, every
> branch. "It's a small change" is not an exception. If a step fails, fix
> the root cause before proceeding. Never use `--no-verify` or skip steps.

---

## Step 1 — Lint

Run the linter(s) for the languages you changed. All must exit 0.

```bash
# Python (ruff)
uv run ruff check --fix .
uv run ruff format .

# TypeScript / JavaScript (biome)
pnpm exec biome check --write .

# Rust
cargo fmt --manifest-path <path/to/Cargo.toml>

# Go
gofmt -w .

# Other: run whatever linter your project uses
```

If the linter reports unfixable errors, fix them manually before continuing.

---

## Step 2 — Type-check

```bash
# Python
uv run mypy .

# TypeScript
pnpm tsc --noEmit
# or via a workspace filter:
# pnpm --filter @yourscope/app typecheck

# Rust (clippy)
cargo clippy -- -D warnings
```

All type errors must be resolved before continuing.

---

## Step 3 — Full test suite

Run every test that covers the changed code. When in doubt, run all of them.

```bash
# Python
uv run pytest

# TypeScript / JavaScript
pnpm test
# or: pnpm vitest run

# Rust
cargo test
```

All tests must be green (or legitimately `xfail`) before continuing. If a
test was passing before your change and is now failing, fix it — do not
mark it xfail.

**Tester-agent scaffold carve-out:** When you are the tester-agent committing
new test files (Mode A of `/test-and-progress`), the implementation may not
exist yet. Tests in `tests.paths` may be `xfail` with a concrete reason
(`@pytest.mark.xfail(reason="<epic-id> not yet implemented")`). That is
acceptable — xfail scaffold tests may be committed. What is not acceptable:
tests that *error* (import errors, missing fixtures) or that pass by
coincidence against stub code. Fix errors before committing; let intentional
xfails through.

---

## Step 4 — Review the diff

```bash
git diff --staged   # if already staged
git diff            # unstaged changes
git status
```

Check for:
- accidentally included files (`.env`, large binaries, generated artifacts
  that should be gitignored)
- debug prints, `console.log`, `TODO` comments introduced by you
- leftover merge-conflict markers

---

## Step 5 — Stage selectively

Add specific files. Never use `git add -A` or `git add .` without first
reviewing `git status` output.

```bash
git add path/to/file1 path/to/file2 ...
```

---

## Step 6 — Write the commit message

Follow Conventional Commits (enforced by the `commit-msg` hook):

```
<type>(<scope>): <short imperative summary>

<body — optional, explains WHY not WHAT>
<footer — breaking changes, closes #issue>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. Append `!` after the type for breaking changes.

Derive the message from the actual diff, not from memory of what you
intended to do.

---

## Step 7 — Commit

```bash
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<body if needed>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

If the pre-commit hook modifies files (whitespace, end-of-file fixes), it
will exit non-zero. Re-stage the modified files and create a **new** commit —
never `--amend` after a hook failure.

---

## What to do when a gate fails

| Gate | Failure action |
|---|---|
| Lint | Fix the reported lines; do not suppress rules without approval |
| Type-check | Fix the type error; inline suppression requires a comment explaining why |
| Tests | Fix the failing test or the code; do not mark passing tests as xfail |
| Pre-commit hook | Re-stage hook-modified files; create a new commit |
| `commit-msg` hook | Rewrite the message to conform; do not bypass |
