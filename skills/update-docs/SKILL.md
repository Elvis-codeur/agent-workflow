---
name: update-docs
description: >
  Keep the agent-workflow documentation in sync with code changes.
  Invoked after any feature, bug-fix, or workflow change to ensure README,
  design docs, the gotchas registry, the bug log, regression tests, and
  CODEBASE-SUMMARY all reflect the current state of the codebase.
  Also covers writing and running the regression test suite.
---

# `/update-docs` — Keep documentation in sync with code

## When to invoke

- After merging any PR that touches `scripts/`, `.archon/`, `.pi/extensions/`,
  `install.sh`, or any `docs/` file.
- After discovering and fixing a new bug (especially an integration bug
  involving Archon or Pi).
- After adding or changing a workflow flag, node, or feature.
- After upgrading Archon or Pi and verifying the regression tests still pass.
- On a regular maintenance cadence (e.g. end of each sprint).

---

## Step 0 — Inventory what changed

```bash
# What changed since the last doc-tagged commit?
git log --oneline $(git tag -l "docs-*" | sort -V | tail -1)..HEAD 2>/dev/null \
  || git log --oneline -20
```

Categorise changes as:

| Category | Examples | Docs to update |
|---|---|---|
| New workflow feature | configure node, skip flags | README, archon-master-loop.md |
| New script / flag | `aw-configure.py`, `--reuse-tests` | README, archon-master-loop.md, AGENTS.md |
| New integration bug found | Archon DB renamed, Pi event missing | docs/gotchas/, docs/bug-log.md |
| Regression test added | new Suite or test case | docs/regression-testing.md |
| Observability change | new aw-inspect flag | docs/observability.md |
| Install change | new file copied by install.sh | README (What gets installed tree) |

---

## Step 1 — README.md

Check and update the three sections that drift most:

### 1a. "What gets installed" file tree

Every file or symlink shipped by `install.sh` must appear in the tree.

```bash
# Find scripts shipped by install.sh
grep -E 'copy_file|make_symlink' install.sh | grep -v "^#" | \
  sed 's/.*"\$TEMPLATES\///; s/".*$//'
```

### 1b. "Running an epic end-to-end" code block

Verify the default models, flags, and description match `scripts/aw-run`.

```bash
grep -E "DEFAULT_CODER|DEFAULT_TESTER|DEFAULT_MASTER" scripts/aw-run
scripts/aw-run --help 2>&1 | head -35
```

### 1c. Skills table

Every `skills/*/SKILL.md` must have a row.

```bash
ls skills/
```

---

## Step 2 — docs/archon-master-loop.md

This is the primary design reference. Update when any of these change:

- **DAG node list** — add/remove/rename nodes; update the node table and diagram.
- **Default models** — check against `scripts/aw-run` `DEFAULT_*` variables.
- **New flags** — add to the Defaults table.
- **New gotchas / behaviours** — add a row to the "Known gotchas" table.
- **Speed / rate-limit info** — update the "Speed troubleshooting" table.

```bash
# Check for drift between doc and actual defaults
grep "DEFAULT_CODER\|DEFAULT_TESTER\|DEFAULT_MASTER" scripts/aw-run
grep "gpt-5.3-codex\|gemini-3-flash\|gpt-5.2" docs/archon-master-loop.md
```

---

## Step 3 — Gotchas registry

For every integration bug whose root cause is confirmed:

1. If it affects future agents working on ANY epic → write a `GOTCHA-NNN` file.
2. Promote bugs from `docs/bug-log.md` that have not yet been filed as gotchas.

```bash
# See which BUG-* entries are not yet in the gotchas index
python3 - <<'PY'
import re, pathlib
bugs   = re.findall(r'^## (BUG-\d+)', pathlib.Path('docs/bug-log.md').read_text(), re.M)
gotcha = pathlib.Path('docs/gotchas/INDEX.md').read_text()
for b in bugs:
    if b not in gotcha:
        print(f"  not yet a gotcha: {b}")
PY
```

### How to add a gotcha

```bash
# Find the next ID
ls docs/gotchas/GOTCHA-*.md | sort | tail -1

# Copy the template
cp docs/gotchas/_TEMPLATE.md docs/gotchas/GOTCHA-NNN-short-slug.md

# Fill in all front-matter fields, then regenerate the index
bash scripts/gotchas-index.sh
```

Front-matter that must be present:

```yaml
id: GOTCHA-NNN
discovered: YYYY-MM-DD
discovered_by: human | coder-agent | tester-agent | master-agent
scope:
  - "glob/pattern/**"       # which epics / paths this is relevant to
severity: low | medium | high | critical
status: open | mitigated | resolved | wont-fix
reproducibility: always | partial | unknown
tags: [archon, pi, bash, ...]
```

---

## Step 4 — docs/bug-log.md

Add a new `## BUG-NNN` entry for every confirmed integration bug fixed.

Structure:
```markdown
## BUG-NNN — <short title>

**Symptom:** what the developer/agent saw (exact error message preferred)

**Root cause:** the mechanism — why does this happen at the source level?

**Fix:** the minimal change that resolved it, with before/after code.

**Prevention:** which regression test covers this, or what guard was added.
```

Keep entries in discovery order. Do not re-sort.

---

## Step 5 — docs/regression-testing.md

Update when:

- A new test suite is added to `scripts/aw-regression-test`.
- An existing suite's scope expands (new tests added).
- A test is removed or made conditional.

For each changed suite, update:
- The test count in the suite header.
- The "What breaks" table column for new/changed tests.

```bash
# Count tests per suite in the current script
grep -c "def test_" scripts/aw-regression-test
```

---

## Step 6 — Run the regression tests

Always run before committing doc changes to catch any drift:

```bash
python3 scripts/aw-regression-test
```

Fix any failures before proceeding. A documentation-only commit that
breaks regression tests is a sign the docs were wrong before.

---

## Step 7 — CODEBASE-SUMMARY.md (in the target project)

If the installed workflow scripts changed, regenerate the project's
auto-generated section:

```bash
bash scripts/update-codebase-summary.sh
```

Verify the AGENT-MAINTAINED section (architectural patterns, recent epic
changes) is still accurate. Remove stale bullets. Add new patterns if
the most recent epics introduced reusable conventions.

---

## Step 8 — Commit

```bash
git add docs/ README.md CODEBASE-SUMMARY.md
git commit -m "docs: <what changed> — keep in sync with <feature/fix>"
```

Commit message format:
- `docs: update archon-master-loop.md for configure node + skip flags`
- `docs(gotchas): add GOTCHA-004 — <slug>`
- `docs(bug-log): add BUG-015 — <slug>`
- `docs: README + archon-master-loop.md after <feature>`

Do **not** bundle code changes and doc changes in the same commit unless
the code change is trivially small (e.g. a one-line fix where the whole
context is the doc update itself).

---

## Checklist

```
[ ] README.md — install tree, flags, skills table up to date
[ ] docs/archon-master-loop.md — DAG, models, flags, gotchas table
[ ] docs/bug-log.md — new BUG-* entry if a bug was fixed
[ ] docs/gotchas/ — new GOTCHA-* if the bug affects future agents
[ ] docs/gotchas/INDEX.md — regenerated (scripts/gotchas-index.sh)
[ ] docs/regression-testing.md — suite descriptions match current tests
[ ] docs/observability.md — if observability tools changed
[ ] CODEBASE-SUMMARY.md — auto section regenerated
[ ] python3 scripts/aw-regression-test — all pass
[ ] git status — no untracked doc files
```
