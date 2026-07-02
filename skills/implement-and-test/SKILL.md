---
name: implement-and-test
description: Single-agent TDD workflow — write failing tests first, implement until they pass, then mark the epic complete. Use when one agent handles the full epic without a separate tester session.
---

# `/implement-and-test` — Single-agent TDD

Use this skill when you are the **sole agent** for an epic that has
`agent_mode: single` in its progress YAML.

The order is always: **red → green → commit → complete**.
Tests come first. Implementation follows. Never the other way around.

---

## When to use — and when NOT to

**Use when:**
- The epic has `agent_mode: single`.
- You are the only agent in this session (no separate tester session).

**Do NOT use when:**
- The epic is `agent_mode: split` (default) — use `/implement-epic` + `/test-and-progress` instead.
- The epic is already `status: review` from a split-mode run — use `/test-and-progress` Mode B.
- The epic is `status: blocked` — use `/fix-blocked` instead.

---

## Why TDD here

In split mode, the tester catches spec misunderstandings the coder missed.
In single-agent mode, that safety net is gone. Writing tests first forces you
to read the acceptance criteria as a *verifier*, not as an *implementer*.
A test written before the code encodes what the spec says; a test written after
the code risks encoding what the code does. The order is not optional.

---

## Step 0 — Read before writing anything

In this order. Do not skip.

1. `docs/gotchas/INDEX.md` — every off-epic bug prior agents recorded.
   If any row's `scope` overlaps your `implementation.paths` or `tests.paths`,
   open the full `GOTCHA-NNN-*.md` before proceeding.
2. `AGENTS.md` — invariants, commit conventions, hook rules.
3. `docs/agent-rules/skills/commit/SKILL.md` — the gate you must clear before marking `complete`.
4. The progress file — your epic by ID. Note `agent_mode`, `depends_on`, both acceptance lists.

**The gotcha rule (active throughout every step):**
If you hit a bug NOT covered by `implementation.acceptance` or `tests.acceptance`,
stop. Ask: would fixing this satisfy any acceptance bullet?
- Yes → it's the epic. Keep going.
- No → invoke `/record-gotcha`, then resume.

---

## Step 1 — Confirm preconditions

1. Every epic in `depends_on` must be `status: complete`. If any is not, write:
   ```yaml
   status: blocked
   blocked: >
     YYYY-MM-DD. Blocked: <epic-id> is not complete. Cannot start until it is.
   ```
   Then stop.

2. Set status immediately:
   ```yaml
   status: in_progress
   ```
   Commit this change before touching any files:
   ```bash
   git add progress.*.yaml
   git commit -m "chore(progress): mark <EPIC-ID> in_progress [single-agent-tdd]"
   ```

---

## Step 2 — Understand the contract

Read `tests.acceptance` line by line. For each bullet:
- What exact behavior must the test assert?
- What input triggers it? What is the expected output or side effect?
- Which function, endpoint, or class does it exercise?

Read `implementation.acceptance` line by line:
- Map each bullet to the file(s) in `implementation.paths` that will satisfy it.

Do not open any `implementation.paths` file yet. You should be able to
describe, in one sentence per acceptance bullet, what the test will assert and
what the code will do — before writing either.

---

## Step 3 — Write the tests (red phase)

Write all test files at `tests.paths`. Rules:

- Cover every `tests.acceptance` bullet with at least one test.
- Add edge cases the acceptance lists imply but do not name explicitly.
- Assert the documented contract, not private implementation details.
- Use the smallest fixture that still proves the acceptance bullet.
- Do **not** import from `implementation.paths` files that don't exist yet;
  use `xfail` with `strict=True` so the test *fails* rather than *errors*:
  ```python
  @pytest.mark.xfail(reason="BE-01 not yet implemented", strict=True)
  def test_something():
      ...
  ```
  `strict=True` means an unexpected pass is also a failure — it prevents
  tests from silently passing against stub code.

After writing, run the tests to confirm they fail for the **right reason**:
```bash
# Python
python -m pytest backend/tests/test_your_epic.py -v

# TypeScript
npx jest path/to/test_your_epic.test.ts --verbose
```

**Expected outcomes at this stage:**
- Tests fail because the implementation does not exist yet → correct, proceed.
- Tests error on import or missing fixture → NOT correct. Fix the test scaffolding
  before proceeding. A test that errors is not red, it is broken.

Do not proceed to Step 4 until tests fail for behavioral reasons only.

---

## Step 4 — Implement (green phase)

Now open `implementation.paths` and write the code.

Rules:
- Implement exactly what `implementation.acceptance` specifies. Nothing more.
- Do not add abstractions, refactors, or features not required by acceptance bullets.
- Do not edit `tests.paths` files to make tests pass. If a test seems wrong,
  re-read the acceptance bullet it maps to. If the spec is ambiguous, record
  the ambiguity in a `blocked:` note rather than guessing.
- After each significant change, run the failing test(s):
  ```bash
  python -m pytest backend/tests/test_your_epic.py::test_name -v
  ```
  Iterate until all epic tests pass.

Remove `xfail` markers as the corresponding implementation is completed and
the tests turn green. `strict=True` xfails that start passing will fail the
suite until you remove the marker — that is intentional.

---

## Step 5 — Run the full gate sequence

Once all epic tests are green, run the full gate sequence:

```bash
# Python backend
ruff check --fix backend/
ruff format backend/
mypy backend/ --ignore-missing-imports
python -m pytest backend/ -v

# TypeScript frontend (if touched)
cd frontend && npx eslint --fix src/ && npx tsc --noEmit && npx jest
```

All gates must be green: zero lint errors, zero type errors, zero test
failures outside pre-existing `xfail`. Fix any gate failures before
continuing. Never use `--no-verify`.

If a gate failure is caused by something outside the epic's scope
(a pre-existing broken test, a toolchain bug), invoke `/record-gotcha`
before proceeding.

---

## Step 6 — Commit

Stage and commit implementation and test files together in one commit:

```bash
git add <implementation.paths files> <tests.paths files>
git commit -m "feat(<area>): <EPIC-ID> <short imperative description> [single-agent-tdd]

<optional body: one or two sentences on WHY, not WHAT>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

The `[single-agent-tdd]` tag is the permanent audit trail that this epic
had no independent tester session.

---

## Step 7 — Mark complete and update CODEBASE-SUMMARY

Update the progress file:

```yaml
status: complete
review: >
  [SINGLE-AGENT-TDD] YYYY-MM-DD. Tests written first (red confirmed),
  then implemented (green). All N tests pass at tests.paths.
  Gates: ruff clean, mypy clean, full suite green.
  <note any non-obvious decision required by an acceptance bullet>
```

Commit:
```bash
git add progress.*.yaml
git commit -m "chore(progress): mark <EPIC-ID> complete [single-agent-tdd]"
```

Then update `CODEBASE-SUMMARY.md`:
- Append one line to "Recent epic changes": `- <EPIC-ID> (YYYY-MM-DD): <one sentence>`
- If the epic introduced a reusable pattern, add a bullet to "Architectural patterns".

```bash
git add CODEBASE-SUMMARY.md
git commit -m "docs(summary): update codebase summary after <EPIC-ID>"
```

---

## If blocked at any step

Write a precise blocked note and stop:

```yaml
status: blocked
blocked: >
  YYYY-MM-DD. Blocked at Step <N>. <exact reason — test name, error message,
  missing dependency, ambiguous spec>. <what would unblock it>.
```

Commit the note:
```bash
git add progress.*.yaml
git commit -m "chore(progress): mark <EPIC-ID> blocked — <short reason>"
```

---

## Checklist

- [ ] Read `docs/gotchas/INDEX.md` — checked for overlapping scope
- [ ] Read `AGENTS.md`, commit skill, progress file
- [ ] All `depends_on` epics are `status: complete`
- [ ] Status set to `in_progress`, committed
- [ ] Both acceptance lists understood line by line
- [ ] Tests written at `tests.paths`
- [ ] Tests confirmed **red** (fail for behavioral reason, not import error)
- [ ] Implementation written at `implementation.paths`
- [ ] All epic tests **green**; `xfail` markers removed where implemented
- [ ] Lint gate green
- [ ] Type-check gate green
- [ ] Full test suite green (zero new failures)
- [ ] Committed with `[single-agent-tdd]` tag
- [ ] Progress updated to `status: complete` with `[SINGLE-AGENT-TDD]` note
- [ ] `CODEBASE-SUMMARY.md` updated

---

## Related docs

- `docs/agent-rules/skills/implement-epic/SKILL.md` — split-mode coder role
- `docs/agent-rules/skills/test-and-progress/SKILL.md` — split-mode tester role
- `docs/agent-rules/skills/fix-blocked/SKILL.md` — recovering from a blocked epic
- `docs/agent-rules/skills/commit/SKILL.md` — full gate procedure
- `docs/agent-rules/skills/write-progress/SKILL.md` — authoring the epic plan
