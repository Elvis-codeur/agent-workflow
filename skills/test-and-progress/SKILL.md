---
name: test-and-progress
description: Run epic tests, map outcomes back to progress.frontend.yaml or progress.backend.yaml, and update epic status plus review/blocked notes with concrete results.
---

# `/test-and-progress` — Run tests and update the progress file

Use this skill when you are acting as the tester-agent for an epic in
`progress.frontend.yaml` or `progress.backend.yaml`, or when the user asks to
rerun tests and update the progress file with current pass/fail reasons.

This skill defines:

- how tests should be written and interpreted
- how to run the right test scope for an epic
- how to update the matching `progress.*.yaml` entry
- what to write when tests pass, xfail, fail, or cannot run

## Two operating modes — read the task carefully

This skill has two distinct modes. Which one you are in is determined by the
exact phrasing of the task. Do not mix them.

### Mode A — write-tests

**Trigger phrases:** "write the tests", "add tests", "scaffold the tests",
"create test files", "implement the test suite".

**What to do:**
1. Write the test files at the `tests.paths` declared in the progress file.
2. Follow the "How tests should be written" rules below.
3. Stop. Do **not** run the tests.
4. Do **not** update the progress file status.

**Why:** The coder-agent may not have finished the implementation yet. Running
tests prematurely produces meaningless failures that pollute the progress file.
Write first; run separately when explicitly asked.

### Mode B — run-tests

**Trigger phrases:** "run the tests", "test", "check the tests", "retest",
"verify the tests", "update the progress file".

**What to do:**
1. Run the tests.
2. Record the outcome in the progress file (`review` or `blocked`).
3. Stop. Do **not** fix failing implementation code.

**Critical constraint:** When tests fail, your job ends at writing a precise
`blocked:` note. Do **not** edit implementation files to make tests pass. That
is the coder-agent's responsibility. A tester-agent that fixes code breaks the
two-agent separation and loses the independent signal the progress file
provides.

If you find yourself tempted to "just fix this one import" or "patch the
missing method", write the exact error in the `blocked:` note instead and stop.

## When to use this skill

- The task says "write the tests" for one or more epics (Mode A).
- The task says "run the tests" or "update the progress file" (Mode B).
- You are the tester-agent for a frontend or backend epic.
- You need to turn raw test output into `review` / `blocked` progress notes.

## When NOT to use this skill

- You are implementing code (that is the coder-agent's role).
- The task is only to explain the current progress plan without executing tests.

## Authority

Read in this order:

1. `AGENTS.md`
2. `docs/agent-rules/orientation.md`
3. The relevant progress file: `progress.frontend.yaml` or `progress.backend.yaml`
4. The matching spec section named by the epic's `area:` field

When the code, progress file, and spec disagree, the spec wins. Do not mark an
epic complete based on drifted behavior alone.

## Core rules

### 1. Test the epic's declared surface, not a random larger slice

Start from the epic's `tests.paths` entries. Those files are the minimum test
scope that matters for the progress update.

If broader downstream suites are required by the progress notes or by the spec,
run them too, but do not skip the epic's own test paths.

### 2. Distinguish four outcomes

Each epic ends in one of these practical states after a test run:

- `review`
  The epic's relevant tests are green, or green with intentional skips/xfails
  that match an accepted not-yet-implemented seam.
- `blocked`
  The tests fail, the environment cannot run them, a dependency is missing, or
  the implementation is missing and the epic is not actually done.
- `complete`
  Only use when the progress file explicitly says the tester-agent can mark it
  complete and all required implementation acceptance, tests acceptance, and CI
  gates are green.
- `planned` / `in_progress`
  Do not set these after a real test pass/fail run unless the user explicitly
  asks you to reset status.

There is no `tested` status in this repository. Use `review` or `blocked`.

### 3. `xfail` is not automatically success

Interpret `xfail` carefully:

- If the test intentionally xfails because the implementation module is not yet
  present, the epic is still `blocked`.
- If the xfail is a deliberate documented seam outside the epic's scope and the
  rest of the acceptance criteria are satisfied, the epic may still be `review`.

### 4. Environment failures are real blockers

If tests cannot run because of missing dependencies, missing plugins, missing
fixtures, invalid config, or import errors, record that as `blocked` with the
exact reason. Do not hide it behind a vague "tests unavailable" note.

## How tests should be written

When you are authoring tests before running them, use these rules:

### Match the progress file

For each epic:

1. Read `implementation.acceptance`
2. Read `tests.acceptance`
3. Ensure every bullet from `tests.acceptance` is covered directly
4. Add enough extra coverage to make the behavior robust, but do not drift away
   from the spec

### Write tests that fail for the right reason

- Prefer precise assertions over broad smoke checks.
- Assert the documented contract, not private implementation details.
- Use the smallest fixture that still proves the acceptance bullet.
- If the implementation is not present yet, an `xfail` with a concrete reason is
  acceptable for an initial test scaffold.

### Keep test structure close to the epic

- Put tests exactly at the `tests.paths` declared in the progress file.
- Name tests after acceptance bullets when possible.
- Use one helper only when it removes clear duplication.

### For async Python tests

- Use `pytest-asyncio` if the suite needs `@pytest.mark.asyncio` or async
  fixtures.
- If async support is missing in the environment, do not rewrite the tests to
  avoid the plugin just to force a run. Record the environment blocker.

## How to run tests

### Step 1 — locate the epic and its test paths

Read the epic entry in the relevant progress file and copy the `tests.paths`
exactly.

### Step 2 — run the smallest correct scope first

Examples:

```bash
uv run pytest apps/kernel-sidecar/tests/test_cli.py apps/kernel-sidecar/tests/test_settings.py
uv run pytest packages/simulator/tests/test_template_loader.py
pnpm vitest run tests/schemas/test_gsim_schema.ts
```

If the root test config does not auto-discover package-local tests, invoke the
paths explicitly.

### Step 3 — broaden only when needed

Broaden the run when:

- the epic notes require downstream suites
- a shared fixture changed
- the local test result is ambiguous
- you need to prove nothing else regressed in the touched area

### Step 4 — capture exact outcomes

For each epic, record:

- pass count if the suite is green
- fail count if the suite is red
- xfail count when relevant
- the first concrete blocking reason when the suite cannot run

## How to update the progress file

### Which file to update

- Frontend work: `progress.frontend.yaml`
- Backend work: `progress.backend.yaml`

Only update the epics you actually tested.

### Status mapping

Use these updates:

- Green relevant tests: set `status: review`
- Red tests or missing environment: set `status: blocked`
- Fully validated epic plus required gates green: set `status: complete`

### Notes format

If the epic is green, add:

```yaml
status: review
review: >
  Retested YYYY-MM-DD. All N tests in path/to/test_file.py pass.
```

If multiple files are involved:

```yaml
status: review
review: >
  Retested YYYY-MM-DD. BE-XX tests are green: 18/18 passed across
  apps/foo/test_a.py and apps/foo/test_b.py.
```

If blocked by a failure, add:

```yaml
status: blocked
blocked: >
  Retested YYYY-MM-DD. 1/6 tests fail in path/to/test_file.py:
  test_name fails because ...
```

If blocked by environment, add:

```yaml
status: blocked
blocked: >
  Retested YYYY-MM-DD. The suite could not start because `pytest_asyncio`
  is missing from the current uv environment.
```

### Writing good blocked notes

A blocked note should let a coder-agent act immediately without rerunning the
entire investigation. Include:

- exact test file or test name when known
- exact missing dependency or import error when known
- exact API mismatch when known
- counts when useful

Avoid vague notes like:

- "tests failing"
- "implementation incomplete"
- "CI red"

Prefer:

- "`find_solver()` got unexpected keyword argument `settings_path`"
- "13/13 namespace tests fail because `pandas` is missing from the uv env"
- "all 7 snapshot tests xfail because `kernel_sidecar.kernel.snapshot` is not implemented yet"

## Do not lose prior signal

When editing a progress entry:

- replace outdated `review:` or `blocked:` text with the latest test result
- keep the rest of the epic unchanged
- do not rewrite `summary`, `acceptance`, or `paths` unless the user asked for it

## Minimal tester-agent checklist

For each epic:

1. Read the epic in the progress file
2. Read the matching spec section
3. Run the epic's `tests.paths`
4. If blocked, capture the exact reason
5. Update the epic to `review` or `blocked`
6. Only mark `complete` if the progress file's completeness rules are truly met

## Useful repository-specific reminders

- Python workspace tests run via `uv run pytest ...`
- Frontend TS tests typically run via `pnpm vitest run ...`
- The repository root `pyproject.toml` may not auto-discover package-local test
  directories; explicit paths are often required
- Backend async suites currently rely on `pytest-asyncio`
- Shared fixture changes can affect both `progress.frontend.yaml` and
  `progress.backend.yaml`

## Related docs

- `docs/agent-rules/orientation.md`
- `progress.frontend.yaml`
- `progress.backend.yaml`
- `docs/specs/frontend-spec.md`
- `docs/specs/backend-spec.md`
