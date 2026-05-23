---
id: GOTCHA-001
discovered: 2026-05-23
discovered_by: human
scope:
  - "**/*"
severity: low
status: mitigated
reproducibility: always
tags: [pi, bash, exit-code, grep, find, ls, archon]
---

# GOTCHA-001 — Pi bash tool reports grep exit 1 (no matches) as a tool failure

## Symptom

When Pi's `bash` tool runs a `grep`, `find`, or `ls` command that produces
no results, the agent session log shows:

```
⚠️ Tool bash failed
```

The agent retries the same command multiple times and may stall for several
turns before working around it or giving up.

In Archon DAG runs the Archon log shows the same warning repeated:

```
WARN: dag.provider_warning_forwarded  nodeId: "implement"
  systemContent: "⚠️ Tool bash failed"
```

## Root cause

`grep` exits 1 when the search pattern matches nothing — that is the POSIX
contract for "no match found", distinct from an error (exit 2). Pi's bash
tool wrapper treats **any** non-zero exit code as a failure and surfaces it
as `⚠️ Tool bash failed`, even though exit 1 from grep is entirely normal.
The same applies to `ls` (target not found → exit 1) and occasionally `find`.

## Fix / workaround

| Option | Effort | Trade-off |
|---|---|---|
| **`bash-normalize-exit.ts` extension** (shipped by `install.sh`) | zero — auto-loaded | Wraps grep/find/ls commands in a subshell; maps exit 1 → 0, exit 2+ preserved. Standard output is unaffected so the agent still reads "no matches". |
| Agent-side guard: append `\|\| true` to each grep call | per-call | Requires discipline; easy to forget. Covered by the `‖ true` hint in the Archon workflow prompt. |

The extension is the primary mitigation. It lives at
`.pi/extensions/bash-normalize-exit.ts` (project-local, auto-discovered by Pi).

## Prevention

- The extension is installed automatically by `install.sh`. No extra steps.
- The `implement` and `fix-blocked` prompts in
  `.archon/workflows/aw-master-loop.template.yaml.tmpl` include a
  "Shell tip: append `|| true` to grep/find/ls existence checks" line as a
  belt-and-suspenders reminder for agents that run without the extension.
- If adding new workflow nodes that search files, include the same tip.

## References

- Pi extensions API: `.pi/extensions/bash-normalize-exit.ts` source
- POSIX grep exit codes: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/grep.html (§EXIT STATUS)
- Pi built-in tools: `read, bash, edit, write, grep, find, ls`

## History

- 2026-05-23: Observed during first live Archon run of BE-29 in general-simulator.
  5 × "Tool bash failed" in the `implement` node; all were grep no-match.
  (— human)
- 2026-05-23: `bash-normalize-exit.ts` extension added; Archon prompts
  updated with `|| true` hint. Status → mitigated.
