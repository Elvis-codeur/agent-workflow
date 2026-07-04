---
name: fix-blocked
description: Resolve a blocked epic — read the blocked note, fix the implementation narrowly (split mode) or fix code and/or tests (single-agent mode), re-run gates, and mark complete or return to review.
---

# `/fix-blocked` — Resolve a blocked epic

Use this skill when an epic has `status: blocked` in a progress file
and you need to unblock it.

**The procedure differs by `agent_mode`. Read that field first.**

---

## Single-agent mode (`agent_mode: single`)

You wrote both the tests and the implementation. Being blocked means one of:
1. **Code bug** — your implementation doesn't satisfy what the tests assert.
2. **Test bug** — your tests assert something the spec does not require, or
   use an assumption that is no longer correct.
3. **Environment / dependency** — toolchain, missing package, env var.

You may fix both code **and** tests — with one constraint:
**tests must express the spec, not the implementation.**

Before touching any file, open the spec section for the epic's `area:` and
the original `tests.acceptance` bullets. If the test is asserting something
that contradicts the spec or goes beyond it, fix the test. If the test
correctly states the spec and the code is wrong, fix the code. Document which
it was in the review note.

After fixing, re-run gates and mark `complete` (not `review`):
```yaml
status: complete
review: >
  [SINGLE-AGENT-TDD] Fixed YYYY-MM-DD. <what was wrong: code bug / test bug / env>.
  <what was changed and why it aligns with the spec>.
  All N tests green. Gates clean.
```

---

## Split mode (`agent_mode: split`, default)

This skill is the **coder-agent's response to tester-agent feedback**. It is
narrower than `/implement-epic` — you are not building from scratch, you are
fixing a specific reported failure.

### When NOT to use this skill (split mode)

- The epic is `planned` or `in_progress` and never been attempted — use `/implement-epic`.
- The `blocked:` note says a *dependency* is missing — resolve the dependency first.
- The tester-agent has not written a `blocked:` note yet — wait for them.

### Role boundary (split mode)

| You do | You do not do |
|---|---|
| Fix implementation files in `implementation.paths` | Edit test files in `tests.paths` |
| Fix only what the `blocked:` note describes | Refactor or improve surrounding code |
| Re-run gates | Rewrite tests to pass against broken code |
| Update epic to `review` | Mark the epic `complete` |

**If a test appears wrong** (asserting behavior the spec does not require),
do NOT edit the test. Record the discrepancy in the `blocked:` note and flag
it. The tester-agent is responsible for correcting wrong tests in split mode.

---

## Role boundary

| You do | You do not do |
|---|---|
| Fix implementation files in `implementation.paths` | Edit test files in `tests.paths` |
| Fix only what the `blocked:` note describes | Refactor, rename, or improve surrounding code |
| Re-run the gates | Rewrite the tests to pass against broken code |
| Update the epic to `review` | Mark the epic `complete` |

**Critical:** If a test appears to be wrong (asserting a behavior the spec
does not require, testing an undocumented side effect, etc.), do **not** edit
the test to make it pass your implementation. Instead, record the discrepancy
in the `blocked:` note and flag it explicitly. The tester-agent is responsible
for correcting wrong tests; you are responsible for correcting wrong code.

---

## Step 0 — Read the gotchas index, then the blocked note

Before anything else, `cat docs/gotchas/INDEX.md` and read every row whose
`scope` overlaps the failing test's path or your `implementation.paths`.
Many "blocked" reports are gotchas in disguise — env, toolchain, filesystem,
codegen quirks. Catching one here saves a full fix-test-arbitrate cycle.

The `blocked:` field written by the tester-agent is your second input.
Read it before opening any implementation file.

A well-written `blocked:` note tells you:

- **Which test failed** — exact test name and file.
- **Why it failed** — the assertion that was violated, the exception raised,
  or the missing symbol.
- **What the test expects** — the concrete behavior the test asserts.

If the note is vague ("tests are failing"), do not guess. Use
`/test-and-progress` (Mode B) to rerun the tests and produce a precise note
before attempting a fix.

**The gotcha rule.** If, during your fix, you find that the failure is
caused by something outside `implementation.acceptance` (a toolchain quirk,
an env-specific path, a cross-filesystem hazard), stop and invoke
`/record-gotcha` before continuing. Then resume the fix or, if the gotcha
IS the cause and there is no code change needed in `implementation.paths`,
leave a `blocked:` note citing the gotcha id and exit — the master will
route correctly.

Example of a note you can act on:

```yaml
blocked: >
  Retested 2026-05-19. 1/6 tests fail in packages/simulator/tests/test_template_loader.py:
  test_loader_raises_on_missing_key — TemplateLoader.load() returns None instead of
  raising TemplateNotFoundError when the key is absent. Spec: backend-spec.md §6.2.
```

---

## Step 1 — Confirm it is a code bug, not a dependency or test bug

Before editing any file, answer:

1. **Is the `blocked:` note describing a code defect in `implementation.paths`?**
   If yes, proceed.

2. **Is the `blocked:` note describing a missing dependency** (a package not
   installed, an environment variable not set, a file that should have been
   generated by another epic)?
   If yes, stop. Record the dependency in a `blocked:` update and wait for
   the dependency to be resolved.

3. **Does the test's assertion contradict the spec?**
   Open the spec section named by the epic's `area:` field. Read the relevant
   section. If the test asserts behavior the spec does not require, do not
   edit implementation to match the test — flag it. Example update:

   ```yaml
   blocked: >
     2026-05-19. test_loader_raises_on_missing_key asserts TemplateNotFoundError
     but backend-spec.md §6.2 does not specify the exception type — only that an
     error is raised. Test may be over-specified. Tester-agent should confirm
     before this epic can be unblocked.
   ```

4. **Do all `depends_on` epics have `status: complete`?**
   If any are `planned`, `in_progress`, or `blocked`, this epic cannot
   proceed. Update `blocked:` to name the unmet dependency.

---

## Step 2 — Reproduce the failure

Run the exact test(s) named in the `blocked:` note before changing anything:

```bash
# Python
uv run pytest path/to/test_file.py::test_name -v

# TypeScript
pnpm vitest run path/to/test_file.ts -t "test name"
```

Confirm the failure matches the note. If the test now passes (someone else
fixed it), update the progress file to `review` without making any code
changes.

---

## Step 3 — Fix narrowly

Fix only what the `blocked:` note describes. Do not:

- Refactor code outside the reported failure path.
- Add features not in `implementation.acceptance`.
- Rename identifiers (unless the name mismatch is the reported bug).
- Touch `tests.paths` files.
- Add extra error handling for scenarios outside the reported failure.

A narrow fix has a small diff. If your fix requires changing ten files,
pause and re-read Step 1 — you may be solving the wrong problem.

---

## Step 4 — Run the gates

Follow `/commit` exactly. All gates must be green before committing.

### Backend gate sequence

```bash
uv run ruff check --fix .
uv run ruff format .
uv run mypy packages/ apps/
uv run pytest path/to/test_file.py   # the failing test first
uv run pytest                         # full suite — confirm no regressions
```

### Frontend gate sequence

```bash
pnpm --filter @gensim/frontend exec biome check --write src/
pnpm --filter @gensim/frontend typecheck
pnpm --filter @gensim/frontend test
```

If the originally failing test now passes but a different test breaks,
you have introduced a regression. Fix the regression before committing.
Do not mark the epic `review` until the full suite is green (or
legitimately xfail).

**Xfail carve-out:** Tests that were intentionally `xfail` before your fix
may flip to passing after it (expected). That is fine. Do not re-mark them
xfail. If an xfail test starts failing unexpectedly, treat it as a
regression and fix it.

---

## Step 5 — Commit

Use the `/commit` skill procedure. Message format:

```
fix(<scope>): <EPIC-ID> resolve <short description of what was wrong>

<optional body: one sentence on why this was wrong and what the fix does>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Example:

```
fix(simulator): BE-10 TemplateLoader.load() now raises TemplateNotFoundError

Was returning None on missing key; spec §6.2 requires an exception.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

---

## Step 6 — Update the progress file

**Split mode** — replace the `blocked:` note with a `review:` note:

```yaml
status: review
review: >
  Fixed YYYY-MM-DD. <EPIC-ID>: <short description of the fix>.
  Gate: <linter> clean, <type-checker> clean, N/N tests pass in
  path/to/test_file.py. Previously blocked: <one line from the old note>.
```

Remove the old `blocked:` field entirely. The tester-agent will re-run
the suite and confirm `complete` or return to `blocked`.

**Single mode** — replace the `blocked:` note with `complete`:

```yaml
status: complete
review: >
  [SINGLE-AGENT-TDD] Fixed YYYY-MM-DD. <what was wrong: code bug / test bug / env>.
  <what was changed and why it aligns with the spec>.
  All N tests green. Gates clean. Previously blocked: <one line from old note>.
```

Remove the old `blocked:` field entirely. Leave all other fields unchanged.

---

## Step 7 — Commit the progress file update

```bash
git add progress.frontend.yaml   # or progress.backend.yaml
# Split mode:
git commit -m "chore(progress): mark <EPIC-ID> review after fix"
# Single mode:
git commit -m "chore(progress): mark <EPIC-ID> complete after fix [single-agent-tdd]"
```

---

## Avoiding common mistakes

| Mistake | Mode | Correct approach |
|---|---|---|
| Editing tests to make broken code pass | Split | Fix the code; flag spec ambiguity instead |
| Editing tests without checking the spec | Single | Always check spec before changing a test |
| Fixing beyond the `blocked:` note's scope | Both | Narrow the diff; scope creep hides regressions |
| Marking `complete` directly | Split | Only the tester-agent marks complete in split mode |
| Marking `review` | Single | Single-agent skips review; go directly to `complete` |
| Committing with a failing test | Both | Fix the regression before committing |
| Using `--no-verify` | Both | Fix the hook failure in the code |

---

## Checklist

**Split mode:**
- [ ] Read the `blocked:` note completely
- [ ] Confirmed it is a code bug (not dependency or test-spec mismatch)
- [ ] Reproduced failure before changing anything
- [ ] Fixed only what the note describes; no `tests.paths` files touched
- [ ] Full suite green; lint and type-check green
- [ ] Committed with `fix(<scope>): <EPIC-ID> ...` message
- [ ] Progress updated to `status: review`

**Single mode:**
- [ ] Read the `blocked:` note; determined whether code bug or test bug
- [ ] Checked spec to validate the fix direction
- [ ] Reproduced failure before changing anything
- [ ] Fixed code and/or tests; all changes align with spec
- [ ] Full suite green; lint and type-check green
- [ ] Committed with `fix(<scope>): <EPIC-ID> ... [single-agent-tdd]` message
- [ ] Progress updated to `status: complete` with `[SINGLE-AGENT-TDD]` note

---

## Related docs

- `/implement-epic` — building an epic from scratch
- `/test-and-progress` — tester-agent workflow (run tests + update progress)
- `/write-progress` — authoring epic plans
- `/commit` — gate procedure
- `docs/agent-rules/orientation.md` — where everything fits
