---
name: session-handoff
description: >
  Maintain a running session log and a concise handoff document so that
  any agent (or human) can resume work in a future session with zero
  re-investigation. Call this skill after every important milestone —
  bug fix, epic completion, infra change, blocker discovery, or session
  end. Append-only; never delete previous entries.
---

# `/session-handoff` — Keep session log & handoff up to date

Use this skill **every time** you reach a meaningful milestone during a
coding session. Do NOT wait until the end — the user may forget, the session
may crash. Append as you go.

## When to invoke (triggers)

Call this skill after **any** of:

- A bug is diagnosed and fixed (or a workaround applied)
- An epic is written, implemented, or marked `done`/`complete`
- An infrastructure change (Docker network, env vars, container creation)
- A new download target or campaign is configured
- A blocker is discovered (even if not yet resolved)
- A new gotcha is recorded
- A session is ending (final summary)
- A session is starting (quick "resumed from…" entry)

**Rule**: if you think "I wish the next agent knew this," invoke the skill.

## When NOT to invoke

- Trivial one-liner fixes with no diagnostic value (typo, formatting)
- Every single commit — batch related commits into one milestone entry
- Routine progress checks ("job still running, 5% done") — only log
  significant progress milestones (first success, 50%, completion)

---

## Files maintained

| File | Location | Purpose |
|---|---|---|
| Session log | `<project>/test_*_experiments/SESSION_YYYY-MM-DD.md` | Full chronology, every milestone, exact commands |
| Handoff | `<project>/test_*_experiments/ops/HANDOFF.md` | Quick-start: current state, resume commands, gotchas |

If `test_*_experiments/` doesn't exist, ask the user where to store session
logs. Do not create files in random locations.

---

## Step 1 — Determine file paths

```bash
# Find the experiments directory
EXP_DIR=$(find . -maxdepth 2 -type d -name "test_*_experiments" | head -1)
SESSION_FILE="$EXP_DIR/SESSION_$(date +%Y-%m-%d).md"
HANDOFF_FILE="$EXP_DIR/ops/HANDOFF.md"
```

If today's SESSION file doesn't exist, create it with a header:

```markdown
# Session YYYY-MM-DD — <project> <one-line summary>

## Quick Resume
... (filled at session end)
```

If it exists, append to it.

---

## Step 2 — Write the milestone entry

Append a timestamped entry to the SESSION file. Format:

```markdown
### HH:MM — <Milestone title>

**What happened**: <2-3 sentences. What was the symptom, what did you do.>

**Resolution**: <How it was fixed, or current state if ongoing.>

**Commands / artifacts** (if applicable):
```bash
# exact commands run, file paths changed, container names
```

**Gotchas / notes**: <Anything surprising. Cross-reference GOTCHA-NNN if applicable.>
```

Keep each entry **scannable in 15 seconds**. The next agent should be able to
grep for a keyword and find the relevant timestamp.

### Examples

```markdown
### 14:35 — yt-dlp bot detection blocking 95% of downloads

**What happened**: Job 185 on @ChristisLord failed 37/39 videos with
"Sign in to confirm you're not a bot." PoT provider was running but
yt-dlp wasn't using it correctly.

**Resolution**: Installed deno v2.3.0 (yt-dlp 2026.06.09 min supported),
deployed fresh browser-exported cookies, fixed PoT provider base_url
from 127.0.0.1 to bgutil-provider:4416. Success rate went from 5% to 100%.

**Commands**:
docker exec yt-scraper-service yt-dlp --cookies /app/cookies.txt \
  --extractor-args "youtubepot-bgutilhttp:base_url=http://bgutil-provider:4416" \
  --remote-components ejs:github --no-download "https://youtube.com/watch?v=..."

**Gotchas**: yt-dlp 2026.06.09 requires deno >= 2.3.0 (not 1.x).
Cookies must be browser-exported (not yt-dlp-exported) and mounted read-only.
```

---

## Step 3 — Update HANDOFF.md

After every milestone that changes the **resume procedure**, update HANDOFF.md:

- Container names, networks, ports
- New docker run command (if changed)
- Database URL changes
- New download targets
- New critical gotchas

HANDOFF.md should always answer: *"I have 5 minutes. What do I type to get
downloads flowing again?"*

Keep it under ~100 lines. Full chronology lives in the SESSION file.

### HANDOFF.md template sections

```markdown
# <Project> Handoff

*Updated: YYYY-MM-DD HH:MM UTC — <last milestone>*

## Quick Resume
... (copy-pasteable bash commands, in order)

## Infrastructure
| Component | Container | Network | Port | Status |
| ... |

## Download Targets
| ID | Channel | Folder | Last Job | State |
| ... |

## Critical Gotchas (most recent first)
1. ...
2. ...
```

---

## Step 4 — Update the epic `progress_notes` (if applicable)

If the milestone relates to an epic, also append a note to the epic's
`progress_notes` field in `progress.yaml`. This is the permanent record;
the session log is the narrative.

```yaml
progress_notes: "2026-07-04: Fixed bot detection. Installed deno v2.3.0.\n\
  Deployed cookies, configured PoT provider. Job 190 succeeded.\n"
```

---

## Step 5 — Session start (first invocation)

If this is the first call in a session, prepend a header:

```markdown
## Session start: YYYY-MM-DD HH:MM UTC
**Agent**: <coder-agent|tester-agent|master-agent>
**Resumed from**: <previous SESSION file or "fresh start">
```

Then proceed with Step 2 normally.

---

## Step 6 — Session end (final invocation)

When the user says the session is ending:

1. Write a **Final state** section at the bottom of the SESSION file:

```markdown
## Final state — HH:MM UTC

**Containers running**: <list>
**Active jobs**: <job IDs, targets, progress>
**Blockers for next session**: <what's needed to resume>
**Next steps**: <bulleted list>
```

2. Make sure HANDOFF.md is fully up to date (Quick Resume section especially).

3. If the user is in a git repo, suggest committing:
```bash
git add SESSION_*.md ops/HANDOFF.md progress.yaml
git commit -m "docs(session): handoff YYYY-MM-DD — <one-line summary>"
```

---

## Anti-patterns

| Don't | Do |
|---|---|
| Write prose essays | Write scannable bullet-point entries |
| Wait until session end | Append after every milestone |
| Put commands in prose | Put commands in ```bash blocks for copy-paste |
| Assume the next agent is you | Write for someone with zero context |
| Omit the exact error message | Quote it verbatim — it's the grep key |
| Skip updating HANDOFF.md | It's the 5-minute resume document |

---

## Checklist (before returning to previous skill)

- [ ] SESSION file has timestamped entry for this milestone
- [ ] HANDOFF.md updated if resume procedure changed
- [ ] Epic `progress_notes` updated if epic-related
- [ ] Commands are in copy-pasteable ```bash blocks
- [ ] Gotchas cross-referenced with GOTCHA-NNN ids
