---
name: implement-and-test
description: Implement an epic AND write its tests in a single agent session, without a separate tester agent. Use when independent tester review is not required. The progress file is explicitly marked [SINGLE-AGENT].
---

# `/implement-and-test` — Single-agent implement + test

Use this skill when you are the **sole agent** for an epic that has
`agent_mode: single` in its progress YAML, or when `scripts/aw-run
--single-agent` was passed explicitly.

---

## When to use — and when NOT to

**Appropriate for:**
- Small, self-contained epics where acceptance criteria are unambiguous and
  mechanically verifiable.
- Time-sensitive or token-budget-constrained runs where a second session is
  not justified.

**Do NOT use when:**
- The epic is high-risk (auth, data migrations, external APIs).
- The tester catching a spec misunderstanding would be valuable.
- The epic is already `status: review` — use `/test-and-progress` instead.

---

## Role boundary

| You do | You do not do |
|---|---|
| Implement `implementation.paths` | Start a new session for tests |
| Run gates (lint, typecheck, suite) | Mark `complete` (workflow does that after `run-tests`) |
| Write test files at `tests.paths` | Run the tests (`run-tests` bash node does that) |
| Mark `status: review` with `[SINGLE-AGENT]` note | Bypass the `run-tests` → `ci-check` → `promote-complete` chain |

---

## Step 0 — Read context first

1. `CODEBASE-SUMMARY.md` — module layout, gate commands, test index
2. `docs/gotchas/INDEX.md` — known bugs; skip entries whose scope doesn't overlap
3. Progress file — confirm status, `implementation.acceptance`, `tests.acceptance`, `agent_mode`

If `agent_mode` is not `single`, stop and tell the caller to use
`/implement-epic` plus `/test-and-progress` instead.

---

## Part 1 — Implement

Follow `/implement-epic` through Step 5:

1. Confirm `depends_on` epics are `complete`.
2. Set `status: in_progress`.
3. Implement `implementation.paths` to satisfy `implementation.acceptance`.
4. Run gates: lint → typecheck → existing test suite (zero new failures).
5. **Do NOT write test files yet. Do NOT commit yet.**

---

## Part 2 — Write tests (same session, no context reset)

After gates are green, write test files at `tests.paths`:

- Write tests that verify each `tests.acceptance` bullet independently.
- Prefer precise assertions over broad smoke checks.
- Do NOT run the tests.
- Do NOT modify any `implementation.paths` file.

---

## Part 3 — Commit

Stage and commit everything together:

```bash
git add -A
git commit -m "feat(<scope>): <EPIC-ID> implement + tests [single-agent]

Co-Authored-By: <model> <noreply@provider>"
```

---

## Part 4 — Update the progress file

Update the epic entry with **exactly** this format:

```yaml
status: review
review: >
  [SINGLE-AGENT] Implemented and tested in one session by the same agent
  without independent tester review. YYYY-MM-DD.
  Implementation: all acceptance bullets satisfied; gates green.
  Tests: written at <tests.paths> (not run by this agent).
```

The `[SINGLE-AGENT]` prefix is **mandatory** — it is the permanent audit trail
that future agents and humans read to understand the lack of session separation.

```bash
git add progress.*.yaml
git commit -m "chore(progress): mark <EPIC-ID> review [single-agent]"
```

---

## What the workflow does next

```
implement-and-test → run-tests → (FAIL) → fix-blocked → rerun-tests → arbitrate
                               → (PASS) → ci-check → promote-complete → commit
```

The rest of the DAG is identical to split mode. The `[SINGLE-AGENT]` note in
the progress file gives the `arbitrate` master agent context if tests fail.

---

## Checklist

- [ ] `agent_mode: single` confirmed (or `--single-agent` flag used)
- [ ] All `depends_on` epics are `complete`
- [ ] Status set to `in_progress`
- [ ] Implementation gates green (lint, typecheck, existing tests)
- [ ] Test files written at `tests.paths`
- [ ] No `implementation.paths` touched after Part 2 started
- [ ] Committed with `[single-agent]` in message
- [ ] Progress YAML updated to `status: review` with `[SINGLE-AGENT]` note

---

## Related docs

- `docs/agent-rules/skills/implement-epic/SKILL.md` — split-mode coder role
- `docs/agent-rules/skills/test-and-progress/SKILL.md` — split-mode tester role
- `docs/archon-master-loop.md` — full DAG including single-agent path
