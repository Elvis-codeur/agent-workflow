# Observability — watching what the agents did

Every workflow run leaves a complete audit trail: structured events in
Archon's database, a full Pi conversation JSONL that can be replayed, and
a live dashboard in the web UI. This document maps each observation need to
the right tool.

---

## The three surfaces

| Need | Tool | Where |
|---|---|---|
| Live progress while a run is happening | Archon web UI | `http://localhost:3090` |
| Post-mortem cost + duration per node | `scripts/aw-inspect EPIC-ID` | terminal |
| Full tool-call log (what the agent read/ran) | `scripts/aw-inspect EPIC-ID --events` | terminal |
| Resume the exact session and ask follow-up questions | `pi --resume $(scripts/aw-inspect EPIC-ID --session)` | Pi TUI |
| Programmatic / scripted access | SQLite `~/.archon/archon.db` | any SQL client |

---

## Surface 1 — Archon web UI

```bash
archon serve          # default port 3090
archon serve --port 4000
```

Open `http://localhost:3090`.

**What you see:**

- **Sidebar** — every workflow run from every platform (CLI, web, Slack,
  Telegram). Runs triggered by `scripts/aw-run` appear here automatically.
- **Conversation view** — click any run to see the full message stream with
  tool calls expandable inline (inputs + outputs + duration).
- **Node list** — each DAG node (read-epic, implement, write-tests, …)
  appears as a row with status icon, duration, and error detail.
- **Workflow Builder** (`/workflows/builder`) — visual DAG canvas for
  reading or editing the workflow YAML. This is a static editor; it does
  **not** animate live execution status.

> **Note (v0.3.10):** The visual DAG graph (boxes + arrows) is only in the
> builder, not in the monitoring view. The monitoring view shows a linear
> node list. A live execution graph may be added in a future Archon release.
> Upgrade with `archon version` / `archon serve` (auto-downloads latest UI).

You can run `archon serve` in a separate terminal **while** `aw-run-all.sh`
is running and watch nodes complete in real time.

---

## Surface 2 — `scripts/aw-inspect`

A small Python CLI that reads `~/.archon/archon.db` and
`~/.pi/agent/sessions/` and surfaces the data in a readable format.

### Default — cost + duration table

```
$ scripts/aw-inspect BE-19

  Epic:    BE-19
  Run:     aw-master-loop-20260523T110936Z-BE_19
  Status:  completed
  Started: 2026-05-23 11:09:39
  Ended:   2026-05-23 11:34:05

  Node             Status       Duration   Cost USD  Output preview
  ---------------- ---------- ---------- ----------  ------------------------------
  read-epic        completed         10s          -  {"epic_id":"BE-19","scope":"b…
  implement        completed       14.6m          -  Now let me read the spec…
  write-tests      completed        109s          -  I'll start by reading…
  run-tests        completed          4s          -  PASS
  fix-blocked      skip(when)         0s          -
  commit           completed        7.8m          -  I've read the /commit skill…
  decide           completed          0s          -  CONVERGED
  ----------------           ---------- ----------
  TOTAL                              (GitHub Copilot — $0)

  Tool calls: bash×101, read×27, edit×5, write×1
```

The `Cost USD` column is `$0` when the provider is GitHub Copilot (included
in the Copilot subscription). It shows real costs for pay-per-token providers
(OpenAI, Anthropic direct).

### `--events` — full tool-call log

Every file the agent read, every bash command it ran, in chronological order:

```
$ scripts/aw-inspect BE-19 --events | less

  2026-05-23 11:09:52  [implement   ]  read      docs/agent-rules/skills/implement-epic/SKILL.md
  2026-05-23 11:09:52  [implement   ]  read      progress.backend.yaml
  2026-05-23 11:09:56  [implement   ]  read      AGENTS.md
  2026-05-23 11:10:00  [implement   ]  bash      grep -n "kernel_status|kernel_restart" docs/…
  2026-05-23 11:10:03  [implement   ]  read      apps/kernel-sidecar/src/…/kernel.py
  …
```

This tells you exactly how the agent approached the problem: which files it
explored first, which commands it ran to understand the codebase, where it
spent time.

### `--session` — path to the Pi JSONL for replay

```bash
$ scripts/aw-inspect BE-19 --session
/home/elvis/.pi/agent/sessions/--home-elvis-.archon-…-epic-be-19--/2026-05-23T11-26-…jsonl
```

Use the path directly with Pi to resume the conversation:

```bash
pi --resume "$(scripts/aw-inspect BE-19 --session)"
```

Once inside Pi you can:
- Read the full reasoning chain with `/tree`
- Ask "why did you choose this implementation?"
- Ask "what would have been a different approach?"
- Ask the agent to explain a specific commit it made
- Fork from any point with `/fork` to explore alternatives

---

## Surface 3 — Pi session files directly

Every Pi session started by Archon is saved to:

```
~/.pi/agent/sessions/
  --home-elvis-.archon-workspaces-<repo>-worktrees-archon-task-archon-epic-<id>--/
    <timestamp>_<uuid>.jsonl
```

The JSONL contains the full conversation: system prompt, every user message
(injected by Archon), every assistant message, every tool call input + output.

**Read it directly:**

```bash
# List all sessions for an epic
ls ~/.pi/agent/sessions/ | grep "be-31"

# Page through the raw JSONL
cat ~/.pi/agent/sessions/.../2026-…jsonl | python3 -m json.tool | less

# Count messages and tool calls
python3 -c "
import json, pathlib
lines = pathlib.Path('~/.pi/agent/sessions/.../file.jsonl').expanduser().read_text().splitlines()
entries = [json.loads(l) for l in lines if l.strip()]
roles = [e.get('role','?') for e in entries if 'role' in e]
print('messages:', len(roles), '| breakdown:', {r: roles.count(r) for r in set(roles)})
"
```

---

## Surface 4 — Archon DB (SQLite)

`~/.archon/archon.db` stores everything Archon knows. Key tables:

| Table | Contents |
|---|---|
| `remote_agent_workflow_runs` | One row per `aw-run` call — name, status, started_at, working_path |
| `remote_agent_workflow_events` | Every event in every run: node_started, tool_called, tool_completed, node_completed with `cost_usd` and `node_output` |
| `remote_agent_conversations` | Conversation ID linking runs to messages |
| `remote_agent_sessions` | Pi session metadata |
| `remote_agent_isolation_environments` | Worktree path, branch name, status |

**Useful queries:**

```sql
-- All completed runs, newest first
SELECT workflow_name, status, started_at,
       json_extract(metadata, '$.node_counts.completed') AS nodes_done
FROM remote_agent_workflow_runs
ORDER BY started_at DESC;

-- Total tool calls per epic
SELECT r.workflow_name,
       SUM(CASE WHEN e.event_type='tool_called' THEN 1 ELSE 0 END) as tool_calls
FROM remote_agent_workflow_runs r
JOIN remote_agent_workflow_events e ON e.workflow_run_id = r.id
GROUP BY r.id
ORDER BY r.started_at DESC;

-- What did the implement node read for BE-31?
SELECT json_extract(e.data, '$.tool_input.path') as path,
       json_extract(e.data, '$.tool_name') as tool
FROM remote_agent_workflow_events e
JOIN remote_agent_workflow_runs r ON r.id = e.workflow_run_id
WHERE r.user_message = 'BE-31'
  AND e.step_name = 'implement'
  AND e.event_type = 'tool_called'
  AND json_extract(e.data, '$.tool_name') = 'read';
```

```bash
sqlite3 ~/.archon/archon.db "SELECT workflow_name, status FROM remote_agent_workflow_runs ORDER BY started_at DESC LIMIT 10;"
```

---

## Per-run log files

`aw-run-all.sh` captures stdout+stderr of each `aw-run` call to:

```
.archon/run-all-logs/
  BE-19.log
  BE-31.log
  FE-02.log
  …
```

These are plain text and contain the full Archon INFO/WARN/ERROR log stream.
Useful for debugging infrastructure failures (worktree creation, validation
errors) that happen before any Pi session starts.

```bash
# See what went wrong with a failed epic
cat .archon/run-all-logs/BE-35.log | grep -E "ERROR|WARN|Failed"

# Count tool-bash-failed warnings per epic
grep -c "Tool bash failed" .archon/run-all-logs/*.log
```

---

## What the observability does NOT cover

| Gap | Status |
|---|---|
| Per-token cost breakdown (input vs output) | Not exposed by Archon v0.3.10; tracked only as `cost_usd` total per node |
| Live DAG graph (nodes + arrows animated) | Not in Archon v0.3.10 monitoring view (only in builder) |
| Cross-epic comparison dashboard | Not built; use SQL queries on `archon.db` |
| Reasoning chain / "why did you do X" | Only via `pi --resume` with the session file — you have to ask the agent directly |

---

## Quick-reference card

```bash
# Is it running?
archon workflow status

# Watch live
archon serve                                        # then open localhost:3090

# Inspect a completed epic
scripts/aw-inspect BE-31                            # cost + duration table
scripts/aw-inspect BE-31 --events | less            # every tool call
scripts/aw-inspect BE-31 --session                  # path to session JSONL

# Resume the agent session and ask follow-up questions
pi --resume "$(scripts/aw-inspect BE-31 --session)"

# Query the DB directly
sqlite3 ~/.archon/archon.db "SELECT workflow_name, status, started_at FROM remote_agent_workflow_runs ORDER BY started_at DESC LIMIT 20;"

# Read the run log
less .archon/run-all-logs/BE-31.log
```
