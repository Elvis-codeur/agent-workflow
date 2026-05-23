---
name: record-gotcha
description: Capture institutional memory for an off-epic bug — a problem the agent hit that is NOT covered by the current epic's acceptance criteria but will cost tokens to rediscover. Decides inline-only vs. long-form, writes the long-form document with reproduction conditions, appends the entry to the epic's `gotchas:` list, and triggers the index regenerator.
---

# `/record-gotcha` — Record an off-epic bug for future agents

Use this skill the moment you realize the bug you are chasing is **not in
`implementation.acceptance` or `tests.acceptance`** of your current epic.

Examples of real gotchas (from prior projects):

- TDLib segfaults when its sqlite db sits on an NTFS mount under WSL because
  it opens with `O_DIRECT` which NTFS-3g rejects silently.
- A Verilog → C++ transpiler emits an unused-variable warning that promotes
  to an error under `-Werror` only when the source file has a BOM.
- `pnpm 9` ignores `node-linker=hoisted` in a workspace package's `.npmrc`;
  the directive must live at the workspace root.

Each cost an agent hours of token burn the first time. Recording it costs 30
seconds and saves the next agent the same hours.

## When NOT to use this skill

- The bug is in `implementation.acceptance` — that is the epic, fix it.
- The bug is a one-line typo in your own diff — fix it and move on.
- You can't reproduce the bug and can't describe a repro path — record it
  inline-only (Path A below), do not invoke long-form authoring.

---

## The gotcha-vs-epic-bug test

> Would fixing this bug satisfy **any** line of `implementation.acceptance`?
>
> - **Yes** → it is the epic. Don't record a gotcha. Fix it under
>   `/implement-epic` or `/fix-blocked`.
> - **No**  → it is a gotcha. Record it here.

Apply the test before doing anything else. If you're unsure, re-read the
acceptance bullets one by one.

---

## Two paths

### Path A — inline-only (fits in ≤ 5 lines)

Use when the gotcha can be fully described — symptom, cause, fix — in five
lines of prose, AND no reproduction recipe is needed because the cause is
self-evident from the description.

1. Pick an id of the form `GOTCHA-inline-YYYY-MM-DD[-slug]`.
2. Append to the current epic's `gotchas:` list in the progress file:

   ```yaml
   gotchas:
     - id: GOTCHA-inline-2026-05-23-pnpm-npmrc-scope
       summary: |
         pnpm 9 silently ignores `node-linker=hoisted` inside a workspace
         package's .npmrc. The directive must live at the workspace root
         .npmrc only. Symptom: phantom-deps install lint failures despite
         the local override. Fix: move the line up; delete the nested file.
   ```

3. Run `scripts/gotchas-index.sh` to refresh `docs/gotchas/INDEX.md`.
4. **Return to your previous skill.** This skill never owns the fix.

If your summary spills past 5 lines, **stop and switch to Path B** — that's
the rule, not a guideline.

### Path B — long-form document (default for anything non-trivial)

Use whenever:

- The summary does not fit in 5 lines, OR
- Reproduction requires specific environment / toolchain / data conditions, OR
- The root cause involves multiple components and would mislead the next
  reader if compressed, OR
- The workaround has trade-offs that another agent will need to weigh.

#### B.1 — Allocate the next id

```bash
ls docs/gotchas/ | grep -oE 'GOTCHA-[0-9]+' | sort -V | tail -1
```

Increment by 1. Pad to three digits: `GOTCHA-001`, `GOTCHA-002`, …

#### B.2 — Create the document

Copy `docs/gotchas/_TEMPLATE.md` to
`docs/gotchas/GOTCHA-NNN-<short-slug>.md` and fill **every** section:

- **Front-matter** (`id`, `discovered`, `discovered_by`, `scope`, `severity`, `status`) — used by `scripts/gotchas-index.sh`.
- **Symptom** — what the agent sees (error message, stack trace, hang, segfault, silent corruption).
- **Reproduction** — minimal recipe: env, file layout, command, expected vs. actual output. If repro requires a specific host (NTFS, WSL, GPU vendor, glibc version), say so explicitly. **If you cannot write a repro, write what is known and mark `reproducibility: partial`.**
- **Root cause** — the actual mechanism. "Why does this happen", not "what happens". If unknown, write `unknown` and list the leads.
- **Fix / workaround** — what to do. If there are multiple, list them with trade-offs.
- **Prevention** — what to check next time before falling into the trap (a lint rule, a CI check, a doc line, a smell).
- **References** — upstream bug reports, commits, mailing-list threads, datasheet pages. URLs and accession dates.

Keep the document under ~300 lines. If it exceeds that, you are probably
documenting a *project*, not a gotcha — split it.

#### B.3 — Append the epic reference

Add to the current epic's `gotchas:` list:

```yaml
gotchas:
  - id: GOTCHA-007
    summary: |
      TDLib segfaults when its sqlite db dir is on NTFS under WSL: it opens
      with O_DIRECT which NTFS-3g rejects silently. Move td_db/ to an ext4
      path; do NOT symlink (TDLib resolves the symlink target before the
      O_DIRECT open). See docs/gotchas/GOTCHA-007-tdlib-ntfs-segfault.md.
```

The summary in the progress file is still capped at 5 lines. Its job is to
help the next agent **decide whether to open the long-form doc**; the
long-form doc carries the full payload.

#### B.4 — Refresh the index

```bash
scripts/gotchas-index.sh
```

This regenerates `docs/gotchas/INDEX.md` from the front-matter of every
`GOTCHA-*.md`. Commit the index alongside your new doc.

#### B.5 — Return to your previous skill

`/record-gotcha` never owns the fix. After recording, resume `/implement-epic`,
`/fix-blocked`, or `/test-and-progress` from wherever you paused.

---

## Front-matter contract (Path B)

The index script depends on this. Do not omit fields; use `unknown` or
`n/a` if you must.

```yaml
---
id: GOTCHA-007
discovered: 2026-05-23
discovered_by: tester-agent      # coder-agent | tester-agent | master-agent | human
scope:                            # globs the gotcha is relevant to
  - apps/telegram-bot/**
  - packages/td-bindings/**
severity: high                    # low | medium | high | critical
status: open                      # open | mitigated | resolved | wont-fix
reproducibility: full             # full | partial | unknown
tags: [tdlib, wsl, ntfs, sqlite, segfault]
---
```

---

## Hard limits

- **One gotcha = one document.** Don't bundle unrelated findings.
- **One gotcha = one owning epic.** The epic that discovered it. If a later
  epic *hits* the same gotcha, it cites the id in its `review:` or
  `blocked:` note — it does NOT add a duplicate entry.
- **Never silently fix-and-move-on.** If you spotted a gotcha and didn't
  record it, you have created tech debt that the next agent will pay for.
  This rule is enforced in `/implement-epic`, `/fix-blocked`, and
  `/test-and-progress`.
- **Never edit** another epic's existing gotcha entries. Open a new one and
  link to the old one via `references:` if there's an update.
