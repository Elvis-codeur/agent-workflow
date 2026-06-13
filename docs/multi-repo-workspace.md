# Multi-repo workspaces

`agent-workflow` installs per-repo: each repo gets its own `progress.yaml`,
its own `scripts/aw-run*`, and runs its own isolated Archon master-loop. A
**workspace** adds one thin layer on top so you can drive the loop across many
repos from a single place, without coupling the repos to each other.

The workspace layer does **not** own epic state and does **not** reimplement the
loop. It reads a manifest, then for each repo `cd`s in and calls that repo's own
`scripts/aw-run-all.sh` (or `scripts/aw-run` for a single epic). All the proven
machinery — git worktrees, the 16-node DAG, merges, rate-limit detection — runs
unchanged inside each repo.

---

## Layout

```
<workspace-root>/            ← the dir whose children are the member repos
├── workspace.yaml           ← the manifest (you edit this)
├── scripts/aw-workspace     ← the orchestrator (installed here)
├── .aw-workspace/           ← aggregated logs + run-summary.md (generated)
├── repo-a/                  ← a member repo, agent-workflow installed inside
│   ├── progress.yaml
│   └── scripts/aw-run-all.sh
├── repo-b/
└── repo-c/
```

---

## Install

From the workspace root (the dir whose children are your repos):

```bash
git clone --depth=1 https://github.com/Elvis-codeur/agent-workflow.git /tmp/aw
bash /tmp/aw/install.sh --workspace .
rm -rf /tmp/aw
```

`--workspace` does three things, all idempotent (never clobbers a customised file):

1. copies `scripts/aw-workspace` to the root;
2. scaffolds `workspace.yaml` from the template if it does not exist;
3. runs the normal per-repo install into **every repo listed in the manifest**.

So on first run, edit `workspace.yaml` to list your repos, then re-run the
installer (or install into each repo individually with `install.sh <repo>`).

---

## Manifest — `workspace.yaml`

Full annotated template: `templates/workspace.example.yaml`.

```yaml
version: 1
workspace: general-scraper
defaults:                       # forwarded to each repo's aw-run as --coder/--tester/--master
  coder:  pi:github-copilot/claude-sonnet-4.6
  tester: pi:github-copilot/gpt-5.3-codex
  master: pi:github-copilot/gpt-5.2
repos:
  - name: repo-a
    path: repo-a                # relative to this file (absolute also allowed)
    progress: progress.yaml     # epic source for `status`
    base_branch: main           # passed to aw-run-all --base-branch
    order: 10                   # ascending; lower runs first
  - name: manager
    path: manager
    order: 99                   # runs last
    coder: claude:sonnet        # optional per-repo override of defaults
```

**Execution model (this version):** per-repo independent, sequential. Repos run
in ascending `order`. There is no cross-repo dependency graph — `order` is the
only sequencing lever. Put a repo that consumes the others (e.g. a manager)
at a high `order` so it runs last.

---

## Commands

Run from the workspace root (or pass `-w path/to/workspace.yaml`).

```bash
scripts/aw-workspace status      # epic-count table across all repos (read-only)
scripts/aw-workspace plan        # run order + the open epics each repo would run
scripts/aw-workspace run         # run the loop across every repo, sequentially
```

`status` and `plan` need no Archon — use them any time to see where things stand.

### `run` options

```bash
scripts/aw-workspace run --repo repo-a            # only this repo (repeatable)
scripts/aw-workspace run --repo repo-a --only BE-31   # a single epic in one repo
scripts/aw-workspace run --no-push                # forward --no-push to each repo
scripts/aw-workspace run --continue-on-error      # don't stop at the first failing repo
scripts/aw-workspace run --dry-run                # print per-repo commands, run nothing
scripts/aw-workspace run -- --max-fix-attempts 5  # everything after -- → each repo's aw-run
```

Model selection comes from the manifest (`defaults` + per-repo overrides) and is
forwarded automatically. Override per-invocation by appending flags after `--`.

### Logs

Each repo's run is tee'd to `<root>/.aw-workspace/logs/<repo>.log`, and a
`<root>/.aw-workspace/run-summary.md` table records pass/fail per repo.

---

## Progress-file compatibility

The per-repo loop accepts either layout:

| Layout | Status vocabulary |
|---|---|
| Single `progress.yaml` | `planned · in_progress · blocked · done · dropped` |
| Scoped `progress.backend.yaml` / `progress.frontend.yaml` | `planned · in_progress · review · complete · blocked` |

`done` is treated as `complete` and `dropped` is terminal, so both vocabularies
flow through `aw-run-all.sh` and the configure node (`aw-configure.py`)
identically. You do **not** need to convert a repo's single `progress.yaml` to
the scoped files.

---

## What this layer deliberately does *not* do

- No cross-repo dependency resolution (deferred; use `order`).
- No parallelism across repos (sequential keeps rate limits and debugging sane).
- No shared epic state — each repo remains the single source of truth for its
  own epics. The workspace only sequences runs and aggregates logs.
