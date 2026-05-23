---
id: GOTCHA-002
discovered: 2026-05-23
discovered_by: human
scope:
  - ".archon/workflows/*.yaml.tmpl"
  - "scripts/aw-decide.sh"
severity: medium
status: mitigated
reproducibility: always
tags: [archon, bash, shell-quoting, json, double-quote]
---

# GOTCHA-002 — Wrapping Archon `$node.output` in double-quotes breaks bash when the value contains `"`

## Symptom

The `decide` DAG node fails with exit code 2:

```
bash: -c: line N: syntax error near unexpected token `('
bash: -c: line N: `                           "'{"verdict":"coder_right",...
```

Appears whenever an upstream node with `output_format` (e.g. `arbitrate`)
produces a JSON blob that is substituted into the `decide` bash script.

## Root cause

Archon's bash-node variable substitution (`escapedForBash = true`) wraps each
substituted value in **single quotes** (`shellQuote`). So `$arbitrate.output`
becomes `'{"verdict":"coder_right","rationale":"..."}'`.

When the workflow template wraps this substitution in **double quotes** too —
`"$arbitrate.output"` — the shell sees `"'{"verdict"..."}'`. The first `"`
character **inside** the JSON prematurely closes the outer double-quoted string,
leaving the rest of the JSON as unquoted bare-words. Bash then hits `(` in
`pytest.xfail('...')` and throws a syntax error.

## Fix

In any `bash:` node: **do not double-quote Archon node-output
substitutions**. Let Archon's single-quoting stand on its own:

```yaml
# WRONG — "..." wraps Archon's '...' producing "'{...'"
bash scripts/aw-run-tests.sh "$read-epic.output.scope"
bash scripts/aw-decide.sh "$arbitrate.output"

# CORRECT — Archon's single-quoting is sufficient
bash scripts/aw-run-tests.sh $read-epic.output.scope
bash scripts/aw-decide.sh $arbitrate.output
```

Only literal strings that you write yourself need quoting. Any
`$nodeId.output` or `$nodeId.output.field` placeholder must be left
**bare** (no surrounding `"..."`) in the template.

## Prevention

- Add this note as a comment to every bash node in
  `aw-master-loop.template.yaml.tmpl` that substitutes node outputs.
- The `decide` node now includes an inline comment explaining the rule.

## References

- Archon `substituteNodeOutputRefs` + `shellQuote` in
  `packages/workflows/src/dag-executor.ts`

## History

- 2026-05-23: Hit during first clean BE-30 run after fixing
  `scripts/aw-test-backend.sh`. (— human)
- 2026-05-23: Template `decide` node fixed; status → mitigated.
