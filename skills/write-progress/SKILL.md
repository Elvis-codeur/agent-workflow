---
name: write-progress
description: Author or extend a progress.*.yaml epic plan — format, field semantics, two-agent-track convention, and rules for adding epics, phases, and status notes.
---

# `/write-progress` — Author or extend a progress file

Use this skill when you are:

- Starting a new epic plan for a project (new `progress.*.yaml` file).
- Adding one or more epics to an existing plan.
- Splitting a plan across phases.
- Revising the acceptance criteria of a `planned` epic before work begins.

## When NOT to use this skill

- You are updating `status`, `review:`, or `blocked:` after running tests —
  that is `/test-and-progress` (Mode B).
- You are updating `status` after implementing code — that is `/implement-epic`
  Step 6.
- You are fixing a blocked epic — that is `/fix-blocked`.

---

## What a progress file is for

A progress file is the **single source of truth for what needs to be built
and who is building it**. It is not a Gantt chart, a changelog, or a test
log. It answers three questions per epic:

1. What is the contract? (`implementation.acceptance` + `tests.acceptance`)
2. Which files does each track own? (`implementation.paths`, `tests.paths`)
3. What is the current state? (`status` + `review:` / `blocked:` notes)

The spec (`docs/specs/`) says *how* to build. The progress file says *what*
and *when*, and tracks *whether it's done*.

---

## File naming and location

```
progress.<scope>.yaml
```

Examples: `progress.frontend.yaml`, `progress.backend.yaml`,
`progress.api.yaml`, `progress.mobile.yaml`.

Keep at the repo root next to `AGENTS.md`. One file per major scope; don't
make a file per phase or per sprint.

---

## Top-level header

Every progress file starts with a comment block and a small set of
top-level keys:

```yaml
# progress.<scope>.yaml — <project name> <scope> v<N> epic plan
#
# Scope:  <one line: what packages/apps this file covers>
# Spec:   <path to the authoritative spec for this scope>
# Cutoff: <what v1 ships; link to the spec section>
#
# ── Conventions ─────────────────────────────────────────────────────────────
# Two agent tracks per epic:
#   - implementation.owner: coder-agent    — writes the code
#   - tests.owner:          tester-agent   — writes and runs the tests
# The two tracks may run in parallel once the epic's contract is fixed.
# An epic is COMPLETE only when:
#   - all implementation.acceptance items pass
#   - all tests.acceptance items pass
#   - the test suite at tests.paths is green
#   - CI gates relevant to this scope are green
#
# Status values: planned | in_progress | review | complete | blocked
# depends_on:   list of epic ids that must be status: complete before this starts
# ────────────────────────────────────────────────────────────────────────────

version: 1
target: <scope>-v1
spec: docs/specs/<scope>-spec.md
```

Optional extra top-level keys (add only what's meaningful):

```yaml
keyboard_map: docs/specs/keyboard-map.md   # frontend plans with chords
frontend_progress: progress.frontend.yaml  # backend plans that depend on FE epics
```

---

## Phases

Group related epics into named phases. Phases are informational — they do
not enforce ordering (use `depends_on` for that).

```yaml
phases:
  - id: P0
    name: Foundation
    epics: [PROJ-01, PROJ-02, PROJ-03]
  - id: P1
    name: Core feature
    epics: [PROJ-04, PROJ-05]
```

Rules:
- Every epic id must appear in exactly one phase.
- Phase ids use a prefix matching the file scope: `P0`/`P1` for frontend,
  `BP0`/`BP1` for backend, or invent a consistent prefix.
- Do not name a phase "Done" or "Backlog" — use `status` fields instead.

---

## Epic structure

Each epic is a YAML mapping under the `epics:` list. Full template:

```yaml
epics:

  - id: PROJ-01
    title: <Short noun phrase — what is being built>
    area: <slug — matches a section of the spec>
    status: planned
    depends_on: []
    summary: >
      One paragraph. Explain WHAT and WHY. Include the v1 scope boundary
      if relevant. Do not describe HOW — that belongs in the spec.
    implementation:
      owner: coder-agent
      paths:
        - path/to/file/to/create_or_modify.py
        - path/to/another/file.ts
      acceptance:
        - <Concrete, falsifiable statement about code behavior.>
        - <Each bullet is something the tester-agent can independently verify.>
        - <Prefer "function foo() returns X when Y" over "foo works correctly".>
    tests:
      owner: tester-agent
      paths:
        - tests/unit/test_proj01.py
        - tests/integration/test_proj01_integration.ts
      acceptance:
        - <Test scenario 1 — maps to one or more implementation.acceptance bullets.>
        - <Test scenario 2.>
        - <Edge case worth covering that is not in implementation.acceptance.>
```

### Required fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique within the file. Convention: `SCOPE-NN` (e.g. `FE-01`, `BE-14`). |
| `title` | string | Short noun phrase. Verb-less; describes the artifact, not the action. |
| `area` | string | Slug mapping to a spec section. See the spec's area→section table. |
| `status` | enum | One of: `planned`, `in_progress`, `review`, `complete`, `blocked`. New epics start `planned`. |
| `depends_on` | list | Epic ids (same or other file). Empty list if none. |
| `summary` | block scalar | One paragraph. WHAT + WHY. Not HOW. |
| `implementation.owner` | string | Always `coder-agent`. |
| `implementation.paths` | list | Files the coder-agent must create or modify. Be exhaustive. |
| `implementation.acceptance` | list | Concrete, falsifiable bullets. These are the coder's deliverables. |
| `tests.owner` | string | Always `tester-agent`. |
| `tests.paths` | list | Files the tester-agent must create. Usually one test file per epic. |
| `tests.acceptance` | list | Test scenarios. Must cover every `implementation.acceptance` bullet. |

### Optional fields (add when appropriate)

```yaml
    review: >
      Retested YYYY-MM-DD. All N tests in path/to/test_file.py pass.
      Gate: typecheck clean, linter clean.
```

```yaml
    blocked: >
      YYYY-MM-DD. Blocked on <exact reason>. <what would unblock it>.
```

`review:` and `blocked:` are written by agents after work, not by the
progress-file author. Leave them absent on new epics.

---

## Writing good acceptance criteria

### Implementation acceptance

Each bullet must be:

- **Concrete**: names a specific function, type, field, or observable behavior.
- **Falsifiable**: a passing or failing state exists; "works correctly" is not
  falsifiable.
- **Bounded**: one behavioral fact per bullet, not a paragraph.

Good:
```yaml
acceptance:
  - "parse_config() raises ConfigError with message 'missing key: timeout' when the timeout key is absent."
  - "Result.write() produces an HDF5 file with datasets /time, /voltage of equal length N."
  - "BlockRegistry.get(name) returns None (not raises) when name is unregistered."
```

Bad:
```yaml
acceptance:
  - "The parser works."
  - "Results are saved correctly."
  - "The registry is robust."
```

### Tests acceptance

- Mirror every `implementation.acceptance` bullet with at least one test scenario.
- Add edge cases not in implementation.acceptance (empty input, boundary values,
  error paths).
- Do not duplicate the implementation bullet verbatim — describe the *test
  scenario*, not the behavior.

Good:
```yaml
acceptance:
  - "test_parse_missing_timeout: call parse_config() with a dict lacking 'timeout'; assert ConfigError raised with correct message."
  - "test_result_write_shape: write a 100-point result; open with h5py; assert /time and /voltage both have shape (100,)."
```

---

## Status lifecycle

```
planned → in_progress → review → complete
                     ↘ blocked → in_progress (after fix)
```

| Status | Set by | Meaning |
|---|---|---|
| `planned` | progress-file author | Not started; preconditions not met or not yet assigned. |
| `in_progress` | coder-agent (on start) | Claimed and being implemented. |
| `review` | coder-agent (after commit) or tester-agent (after green run) | Implementation committed; awaiting tester-agent validation. |
| `complete` | tester-agent | All acceptance criteria met; test suite green; CI green. |
| `blocked` | coder-agent or tester-agent | Cannot proceed; reason in `blocked:` note. |

Rules:
- Only the tester-agent marks `complete`. The coder-agent marks `review`.
- Do not use `in_progress` for both tracks simultaneously on the same epic
  unless the plan explicitly notes parallel-track work.
- A `blocked` epic must always have a `blocked:` note. "blocked" without a
  note is forbidden.

---

## Ordering and `depends_on`

- `depends_on` lists epic ids that must reach `status: complete` before this
  epic can start.
- Cross-file dependencies are allowed: `depends_on: [FE-45, FE-46]` in
  `progress.backend.yaml` is valid.
- If an epic has no dependencies, use an explicit empty list: `depends_on: []`.
- Do not express dependencies through phase membership alone — phases are
  display groupings, not ordering constraints.

---

## Versioning and drift

The progress file is versioned with git like code. When the spec changes:

1. Update the progress file to match in the same PR.
2. If an acceptance bullet has already been verified, do not weaken it
   silently — annotate the revision in a `review:` note or a git commit message.
3. If an epic's `implementation.paths` change after work began, record the
   reason in `summary:` or a git commit message.

---

## What NOT to put in a progress file

- **HOW to implement** — that belongs in the spec.
- **Meeting notes or decisions** — commit messages and spec PRs are the record.
- **Vague status notes** — every `blocked:` or `review:` note must be
  actionable. "Tests failing" is not a note. "test_foo fails because
  `bar()` raises KeyError on empty dict" is a note.
- **Duplicate content from the spec** — a one-line `summary:` is enough; copy
  the contract from the spec, don't restate it.

---

## Cross-references

- `/implement-epic` — coder-agent workflow for a planned epic
- `/test-and-progress` — tester-agent workflow (write tests or run + update)
- `/fix-blocked` — coder-agent workflow for a blocked epic
- `docs/agent-rules/orientation.md` — where specs, progress files, and skills fit together
