---
name: implement-epic
description: Implement the code for one epic from a progress.*.yaml file, following its acceptance criteria, then mark it review-ready. Counterpart to /test-and-progress.
---

# `/implement-epic` — Implement an epic

Use this skill when you are acting as the **coder-agent** for an epic in
a `progress.*.yaml` file.

This skill defines:

- how to read an epic's contract before writing a single line
- what to implement and what to leave for the tester-agent
- how to run the gates that gate a `review` status
- how to update the progress file when done or blocked

## Role boundary — read this first

This skill owns the **implementation** side only.

| You do | You do not do |
|---|---|
| Implement the files in `implementation.paths` | Write the test files at `tests.paths` |
| Run lint, typecheck, and the existing suite | Write new tests from scratch |
| Mark status `in_progress` then `review` | Mark status `complete` |
| Write a `review:` note with concrete evidence | Run tester-agent steps |

The tester-agent (skill `/test-and-progress`) independently validates the
tests and marks the epic `complete`. Do not collapse the two roles into one
pass.

**Exception:** if the epic's `implementation.paths` include a test file (rare —
only when the epic's entire deliverable is a test, such as an e2e smoke suite),
write that file. Document it explicitly in your `review:` note.

---

## Step 0 — Read before writing

Read these documents in order. Do not skip.

1. **`docs/gotchas/INDEX.md`** — every gotcha discovered by prior agents. If
   any row's `scope` overlaps your `implementation.paths` or the failing
   test's path, open the linked `GOTCHA-NNN-*.md` and read it before
   writing code. Skipping this step is a token-waste violation.
2. `AGENTS.md` — invariants, commit conventions, hook rules
3. `docs/agent-rules/skills/commit/SKILL.md` — the gate you must pass before
   marking `review`
4. The relevant progress file — find your epic by ID. Pay attention to the
   epic's `gotchas:` list — those are pre-existing land mines for this work.
5. The spec section named by the epic's `area:` field

When the spec and the progress file disagree, **the spec wins**. Raise the
conflict in your `review:` note but implement to the spec.

---

## Step 0a — The gotcha rule (applies through every step below)

If at any point you hit a bug that is NOT covered by
`implementation.acceptance`, stop. Apply the gotcha-vs-epic test
(`/record-gotcha`): would fixing this bug satisfy any acceptance line?

- **Yes** → it's the epic, keep going.
- **No**  → invoke `/record-gotcha` before you fix anything else. Silently
  fixing an off-epic bug creates tech debt the next agent pays for. After
  recording, resume from the step you paused.

---

## Step 1 — Confirm preconditions

Before touching any file:

1. **Check `depends_on`.** Every epic listed there must be `status: complete`.
   If any is `planned`, `in_progress`, `review`, or `blocked`, stop and record
   a `blocked:` note explaining which dependency is not ready.

2. **Check cross-file dependencies.** Some epics depend on epics in other
   progress files. Read any such notes and honour them.

3. **Verify the implementation paths are free.** For each path in
   `implementation.paths`, confirm it either doesn't exist yet or can be
   safely modified without colliding with another in-progress epic.

4. **Set status to `in_progress`** in the progress file immediately. This
   signals to other agents that this epic is claimed.

---

## Step 2 — Understand the contract

Read `implementation.acceptance` line by line. For each bullet:

- Identify the files it touches.
- Identify the exact interface it specifies (function names, types, field
  names, error messages). These are not suggestions — they are what the
  tester-agent will verify.
- Note which bullets have cross-language or cross-service contracts.

Do not start implementing until you can describe, in one sentence per bullet,
what concrete code change each bullet requires.

---

## Step 3 — Implement

### General rules

- Implement exactly what the acceptance bullets specify. Do not add features,
  refactor surrounding code, or introduce abstractions not required by the epic.
- Prefer editing existing files to creating new ones when the path list says
  to modify an existing file.
- Default to writing no comments. Only add one when a hidden invariant or
  subtle workaround would surprise a future reader.
- Do not add error handling for scenarios that cannot happen. Trust internal
  guarantees. Validate only at system boundaries.
- Never bypass pre-commit hooks (`--no-verify`). Fix the root cause.
- After the implementation compiles and the existing test suite is green (or
  legitimately `xfail`), stop. Do not write new test files — those belong in
  `tests.paths` and are the tester-agent's work.
- If the tester-agent pre-scaffolded `tests.paths` as `xfail`, those tests
  may still be `xfail` after your implementation — that is expected. Do not
  remove `xfail` markers; the tester-agent does that when they re-run via
  `/test-and-progress` Mode B.

### Language-specific reminders

Add your project's specific gate commands here. Examples:

```bash
# Python — run after each significant change
uv run ruff check --fix . && uv run ruff format .
uv run mypy .
uv run pytest path/to/affected_test.py

# TypeScript — run after each significant change
pnpm exec biome check --write src/
pnpm tsc --noEmit
pnpm test

# Rust
cargo fmt
cargo clippy -- -D warnings
cargo test
```

---

## Step 4 — Run the commit gates

Follow the `/commit` skill exactly. All gates must be green before you commit.

Run the full gate sequence for every language you touched:
1. Lint + auto-fix
2. Type-check
3. Full test suite (zero new failures; intentional `xfail` is acceptable)

If any gate fails:
- Fix the root cause in the implementation files.
- Re-run the full gate sequence from the beginning.
- Do not commit with a failing gate.

---

## Step 5 — Commit

Use the `/commit` skill procedure. Message format:

```
feat(<scope>): <EPIC-ID> <short imperative description>

<optional body: one or two sentences on WHY, not WHAT>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Scope should match the epic's `area:` field.

---

## Step 6 — Update the progress file

After a successful commit, update the epic entry:

```yaml
status: review
review: >
  Implemented YYYY-MM-DD. All implementation.acceptance bullets satisfied.
  Gate: <linter> clean, <type-checker> clean, N/N tests pass.
  <note any acceptance bullet that required a non-obvious decision>
```

If blocked at any step:

```yaml
status: blocked
blocked: >
  YYYY-MM-DD. Blocked on <exact reason>. <what would unblock it>.
```

Good `blocked:` notes give the next agent enough to act without
re-investigating. Include exact error messages, missing identifiers, or
unmet dependency names.

---

## Step 7 — Commit the progress file update

```bash
git add progress.*.yaml
git commit -m "chore(progress): mark <EPIC-ID> review"
```

The tester-agent will then pick up the epic, write and run the tests, and
either mark it `complete` or return it to `blocked`.

---

## Avoiding common mistakes

| Mistake | Correct approach |
|---|---|
| Writing tests from `tests.paths` | Stop at implementation; leave tests.paths to the tester-agent |
| Marking `complete` | Only the tester-agent marks `complete`; you mark `review` |
| Bypassing `--no-verify` | Fix the hook failure in the code |
| Adding a feature not in `implementation.acceptance` | Remove it; scope creep obscures test signal |
| Implementing across multiple epics in one commit | One commit per epic maximum |
| Editing `tests.paths` files to make tests pass | That is the tester-agent's domain |

---

## Checklist (read before starting)

- [ ] Read AGENTS.md, commit skill, progress file, and spec
- [ ] All `depends_on` epics are `status: complete`
- [ ] Status set to `in_progress`
- [ ] `implementation.acceptance` bullets understood line by line
- [ ] All `implementation.paths` files created or modified
- [ ] No `tests.paths` files touched
- [ ] Lint gate green
- [ ] Type-check gate green
- [ ] Existing test suite green (zero new failures)
- [ ] Committed with conventional commit message
- [ ] Progress file updated to `status: review` with concrete evidence

---

## Related docs

- `docs/agent-rules/skills/commit/SKILL.md` — gate procedure
- `docs/agent-rules/skills/test-and-progress/SKILL.md` — tester counterpart
- `docs/agent-rules/skills/fix-blocked/SKILL.md` — resolving blocked epics
- `docs/agent-rules/skills/write-progress/SKILL.md` — authoring the epic plan
