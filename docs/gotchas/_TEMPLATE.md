---
id: GOTCHA-NNN
discovered: YYYY-MM-DD
discovered_by: coder-agent          # coder-agent | tester-agent | master-agent | human
scope:                               # globs of paths this gotcha is relevant to
  - path/to/component/**
severity: medium                     # low | medium | high | critical
status: open                         # open | mitigated | resolved | wont-fix
reproducibility: full                # full | partial | unknown
tags: []
---

# GOTCHA-NNN — <short imperative title>

## Symptom

What the agent sees. Quote the exact error message, stack frame, log line,
or observed misbehavior. If the failure is silent (wrong output, no error),
say "silent" and describe the divergence.

## Reproduction

Minimum recipe to trigger the bug, including:

- **Environment**: OS, kernel, filesystem, container, GPU/CPU vendor, locale,
  any non-default mount option.
- **Versions**: language runtime, package manager, every relevant dependency.
- **Setup**: file layout, env vars, config flags.
- **Trigger**: the exact command to run.
- **Expected vs. actual**: what the docs/spec promise vs. what happens.

If the bug only reproduces on a specific host class (e.g., NTFS-mounted
working tree, WSL2, ARM64), state it as a **precondition** at the top of
this section so future agents can skip the gotcha when their environment
differs.

## Root cause

The mechanism. "Why does this happen at the kernel/library/parser level?",
not "what happens to the user". If unknown, write `unknown` and list the
strongest leads you have so the next agent doesn't start from zero.

## Fix / workaround

The smallest change that makes the bug go away. If multiple options exist,
list them with trade-offs:

| Option | Effort | Trade-off |
|---|---|---|
| Move data dir to ext4 | low | requires a host-level convention |
| Patch TDLib to drop `O_DIRECT` | high | maintain a fork |

## Prevention

What would have caught this earlier? A pre-flight check, a lint rule, a CI
matrix entry, a doc line under "Prerequisites", a comment in the config
file. Be concrete enough that a future agent can implement the prevention.

## References

- Upstream issue: <url> (accessed YYYY-MM-DD)
- Related commit: `<sha>` in `<repo>`
- Mailing list thread / datasheet page / RFC: …

## History

- YYYY-MM-DD: Discovered while working on EPIC-XXX. (— discovered_by)
- YYYY-MM-DD: Workaround landed in commit `<sha>`.
- YYYY-MM-DD: Status changed to `mitigated`.
