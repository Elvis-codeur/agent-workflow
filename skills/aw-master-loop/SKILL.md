---
name: aw-master-loop
description: Master-agent arbitration for the Archon aw-master-loop workflow — break ties when the coder-agent says `review` but the tester-agent says `blocked` after the fix-blocked loop has exhausted its retries. Read evidence, classify the failure into one of 8 buckets, emit a structured verdict, and escalate to the human only when truly unsure.
---

# `/aw-master-loop` — Master arbitration

Use this skill **only** when invoked by the `arbitrate` node of the Archon
`aw-master-loop` workflow. It runs after:

1. The coder-agent ran `/implement-epic` and marked the epic `review`.
2. The tester-agent ran `/test-and-progress` (Mode A then B) and marked it
   `blocked`.
3. The coder ran `/fix-blocked` up to `--max-fix-attempts` times.
4. The tests still failed.

Your job is to decide **who is right** — the coder, the tester, or neither —
without editing code or tests.

## When NOT to use this skill

- Tests are green. The workflow proceeds to `commit`. You should not have
  been invoked.
- The coder has not yet marked `review`, or the tester has not yet marked
  `blocked`. The workflow is in an earlier stage; defer.
- You were invoked manually outside the workflow. Stop and tell the user to
  run `scripts/aw-run` instead — manual arbitration short-circuits the
  retry counters and the gotchas registry.

---

## Role boundary

| You do | You do not do |
|---|---|
| Read the spec, the diff, the test output, the notes, the gotchas | Edit any source or test file |
| Emit a strict-JSON verdict | Mark the epic `complete` or `blocked` |
| Increment the arbitration counter (Step 5) | Re-run the test suite |
| Escalate to the human via `verdict: unsure` | Argue with the human's final decision |

The verdict routes the workflow:

- `coder_right` → tester rewrites the failing test, workflow loops back to `run-tests`.
- `tester_right` → coder runs `/fix-blocked` once more, workflow loops back to `implement`.
- `unsure` → `ask-human` node pauses for stdin; your `rationale` is the case file.

---

## Step 1 — Gather evidence (mechanical, no judgement yet)

Collect these **seven inputs** in this order. Do not skip. Do not reorder.

1. **Spec section** — the file/anchor named by the epic's `area:` field.
2. **Acceptance criteria** — `implementation.acceptance` *and* `tests.acceptance` from the progress file.
3. **Coder's latest `review:` note**.
4. **Tester's latest `blocked:` note**.
5. **The diff** — `git diff $BASE_BRANCH... -- <implementation.paths> <tests.paths>`.
6. **Raw test output** — the `$rerun-tests.output` string passed to you by the workflow.
7. **Gotchas registry** — run `cat docs/gotchas/INDEX.md` and read every entry whose `scope:` field overlaps any file in `implementation.paths`, `tests.paths`, or the failing test's path. Also read the current epic's inline `gotchas:` list. **If a gotcha plausibly explains the failure, jump to bucket 3 (env / toolchain).**

Quote one sentence from each of these inputs in your final `rationale`. The
human reading an `unsure` verdict must not have to re-derive your reasoning.

---

## Step 2 — Classify into exactly one bucket

| # | Pattern in evidence | Verdict | Side note |
|---|---|---|---|
| 1 | Failing test asserts behavior **not in `tests.acceptance` or spec** | `coder_right` | Tester must rewrite the test |
| 2 | Spec & `implementation.acceptance` require behavior X; diff does not deliver X | `tester_right` | Coder runs `/fix-blocked` |
| 3 | Test fails on **import / fixture / path / env / toolchain** error, not a real assertion | `unsure` | Often a gotcha — cite it |
| 4 | Spec acceptance is **ambiguous or self-contradictory** | `unsure` | Human must clarify the spec |
| 5 | Test asserts **partially in spec** (covers strict superset of acceptance) | `coder_right` *if* coder met acceptance, else `tester_right` | Cite the exact superset clause |
| 6 | Diff touches files **outside `implementation.paths`** | `tester_right` | Also flag `scope_violation: implementation` |
| 7 | Test file outside `tests.paths`, or test edits implementation | `coder_right` | Also flag `scope_violation: tests` |
| 8 | **Spec is outdated** — test encodes behavior that was correct when written but the project has since pivoted, or vice-versa | `unsure` | Flag `spec_outdated: true`; human must update the spec before either agent can be right |

If **two or more buckets** plausibly match the same evidence, the verdict is
forced to `unsure`. Do not pick a favorite.

---

## Step 3 — Confidence

Score `confidence ∈ [0, 1]` for your chosen bucket:

- `≥ 0.85` — single bucket, evidence unambiguous, no gotcha overlap, no ambiguous spec.
- `0.70 – 0.85` — single bucket, one minor caveat.
- `< 0.70` — **force `verdict: unsure`** regardless of which bucket "fit best". The
  arbitration cost of a wrong verdict (one more full coder + tester cycle) is
  much higher than the cost of asking the human.

---

## Step 4 — Emit the verdict

Output strictly the following JSON (matches the workflow's `output_format`):

```json
{
  "verdict": "coder_right | tester_right | unsure",
  "confidence": 0.0,
  "bucket": 1,
  "rationale": "≤ 6 sentences. Cite spec/acceptance/diff/test/gotcha by quoting one line from each input you used.",
  "flags": {
    "spec_outdated": false,
    "scope_violation": null,
    "gotcha_id": null
  }
}
```

`flags.gotcha_id` MUST be set whenever bucket 3 fired and a matching gotcha
exists in the registry. If none exists, set `gotcha_id: "PENDING"` and
include `"Open a /record-gotcha entry for this failure"` in `rationale` —
the workflow will route to `/record-gotcha` before retrying.

---

## Step 5 — Counter and hard-fail rule

The workflow ships a per-epic counter at:

```
.archon/state/arbitration-count-<epic-id>
```

Before emitting your verdict:

1. Read the counter (0 if missing).
2. Increment it.
3. Write it back.
4. If the new value **exceeds `$MAX_ARBITRATION_ATTEMPTS`** (env var injected
   by `scripts/aw-run`, default `3`), override your verdict to:

   ```json
   {
     "verdict": "unsure",
     "confidence": 0.0,
     "bucket": 0,
     "rationale": "BLOCKED-ARBITRATION-EXHAUSTED: $N attempts reached. Human must decide; counter is at .archon/state/arbitration-count-<epic-id>. Reset to 0 after intervention.",
     "flags": { "exhausted": true }
   }
   ```

5. The workflow's `ask-human` node will then surface this to the user and
   exit non-zero with code `BLOCKED-ARBITRATION-EXHAUSTED`. The worktree is
   preserved.

The counter is reset to 0 by the coder-agent on the first successful
`/implement-epic` of a fresh epic (Step 1, "Set status to in_progress"). It
is NEVER reset during arbitration — that is what makes the cap meaningful.

---

## Step 6 — Hand-off note for the human (only on `unsure`)

When `verdict: unsure`, the `ask-human` node will render a prompt for the
user. Your `rationale` is what they read. Use exactly this structure:

```
EPIC:    <epic-id>            scope: <frontend|backend|...>
SPEC:    "<one sentence quoted from the spec section>"
CODER:   "<one sentence quoted from the review: note>"
TESTER:  "<one sentence quoted from the blocked: note>"
DIFF:    <N files, M insertions, K deletions>     // from `git diff --stat`
GOTCHA:  <GOTCHA-NNN or "none">                   // if bucket 3
CONFLICT: <one sentence: what the two sides disagree about>
OPTIONS:
  a) coder_right  → tester rewrites <test_path>:<test_name>
  b) tester_right → coder runs /fix-blocked on <impl_path>
  c) spec_outdated → human edits docs/specs/<file> first
Recommended (if any): <a|b|c|none>
```

This is the only natural-language output the human reads. Make it scannable
in 30 seconds. Do not add prose around it.

---

## Hard limits

- **Never modify** the progress file. Status changes belong to the coder/tester skills.
- **Never run** the test suite. The bash node owns that.
- **Never re-read** the diff after writing the verdict — no second-guessing loops.
- **Never edit** files in `implementation.paths` or `tests.paths`.
- **Never reset** `.archon/state/arbitration-count-<epic-id>`.
- If you discover a gotcha during evidence gathering and no entry exists, set
  `flags.gotcha_id: "PENDING"` — do **not** invoke `/record-gotcha` yourself.
  The workflow has a dedicated node for that.
