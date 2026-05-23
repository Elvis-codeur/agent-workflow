# Archon master-loop workflow (design)

> Branch: `feat/archon-master-loop`
> Status: scaffold — not yet wired end-to-end.

## Goal

Automate the coder ↔ tester ping-pong that today requires a human in the
loop. The user picks one epic from a `progress.*.yaml` file and chooses which
model plays which role; the [Archon](https://github.com/coleam00/Archon)
workflow engine drives every CLI call non-interactively until the epic is
`complete` or the master agent escalates.

## Roles and existing skills

The existing skills already encode the contract for each role. The Archon
workflow just orchestrates them — it does NOT duplicate their logic.

| Archon node | Role | Skill it runs |
|---|---|---|
| `read-epic` | master | reads the epic, no edits |
| `implement` (loop) | coder | `/implement-epic`, then `/fix-blocked` on retry |
| `write-tests` | tester | `/test-and-progress` Mode A |
| `run-tests` | n/a (bash) | invokes the project test command |
| `arbitrate` | master | breaks coder/tester ties, may ask user |
| `commit` | master | `/commit` |

## Where it runs

The workflow file lives in `.archon/workflows/` and is executed by the
**Archon CLI** (`~/.local/bin/archon`, v0.3.10+). Archon dispatches each
AI-node to one of the registered providers — `pi`, `claude`, or `codex` —
according to the per-node `provider:` and `model:` fields.

You can trigger a run from:

- **Terminal** — `scripts/aw-run …` (renders the template, calls `archon workflow run`)
- **A pi / Claude Code / Codex session** — say "use archon to run aw-master-loop …";
  the host agent shells out to the `archon` CLI.
- **Archon Web UI** — `archon serve`, then start the workflow from the dashboard.
- **Slack / Telegram / GitHub** — if you wire the corresponding Archon adapter.

The workflow itself always runs in an **isolated git worktree** (Archon's
`--branch` flag), so multiple epics can run in parallel without stepping
on each other.

## Per-call model assignment

Archon validates `model:` strings at YAML load time, so they cannot be
substituted with `$ARGUMENTS` at runtime. We work around this with a small
wrapper:

```
scripts/aw-run \
    --coder claude:sonnet \
    --tester codex:gpt-5-codex \
    --master pi:kiro/minimax-m2-5 \
    --max-fix-attempts 3 \
    EPIC-AUTH-001
```

`aw-run` renders `.archon/workflows/aw-master-loop.template.yaml` with the
chosen `provider`/`model`/`modelReasoningEffort` triples into
`.archon/workflows/.runs/aw-run-<ts>.yaml`, then executes:

```
archon workflow run aw-master-loop-<ts> "<EPIC-ID>" \
    --branch archon/epic-<EPIC-ID>
```

You can also reuse a single coder/tester pair for an entire implementation
loop by omitting `--master` (it then defaults to whichever model is set as
`defaultAssistant` in `~/.archon/config.yaml`).

## Arbitration policy (master agent)

The master node only runs when the coder has marked an epic `review` but the
tester has marked it `blocked` after `--max-fix-attempts` retries — i.e., the
two sub-agents disagree on whether the implementation is correct.

The master is given:

1. The epic spec (`implementation.acceptance` + `tests.acceptance`)
2. The latest `review:` note from the coder
3. The latest `blocked:` note from the tester
4. The diff and the test output

It produces structured JSON (`output_format`) with one of three verdicts:

- `coder_right` → tester rewrites the test, loop back to `run-tests`
- `tester_right` → coder runs `/fix-blocked` again, loop back to `implement`
- `unsure` → an `interactive: true` node prompts the human (you) for the call

The `unsure` branch is the only point at which the workflow blocks on input.

## File map

```
.archon/
└── workflows/
    └── aw-master-loop.template.yaml      # rendered by scripts/aw-run
scripts/
└── aw-run                                # bash wrapper, renders + invokes
skills/
└── aw-master-loop/SKILL.md               # master-agent procedure (arbitration rules)
docs/
└── archon-master-loop.md                 # this file
```

## Defaults (locked)

| Role | Default | Override flag |
|---|---|---|
| master | `claude:sonnet` (Sonnet 4.6) | `--master PROVIDER:MODEL` |
| coder | `codex:gpt-5-codex` | `--coder PROVIDER:MODEL` |
| tester | `claude:sonnet` (Sonnet 4.6) | `--tester PROVIDER:MODEL` |
| max fix attempts before arbitration | `3` | `--max-fix-attempts N` |
| autocommit on green | **on** | `--no-autocommit` |
| worktree cleanup on success | **on** | `--keep-worktree` |

The autocommit node never pushes and never opens a PR — it only runs the
`/commit` skill (lint → typecheck → test → stage → conventional commit).
When `--no-autocommit` is passed, `scripts/aw-run` strips the commit node
from the rendered workflow between the `>>> AUTOCOMMIT` / `<<< AUTOCOMMIT`
markers in the template.

Worktree cleanup runs `archon complete <branch>` only when the workflow exits
zero; on failure the worktree is preserved so you can inspect it.
