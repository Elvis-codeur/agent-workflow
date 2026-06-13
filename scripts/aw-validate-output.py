#!/usr/bin/env python3
"""
aw-validate-output.py — guardrail: detect rate-limit / corrupted AI output
before downstream DAG nodes consume it.

Every AI node with output_format can return non-JSON garbage when the provider
hits a rate limit, credit exhaustion, or auth error.  When that happens the
Archon engine (v0.4.1) marks the node *completed* with the raw error text,
and downstream $nodeId.output.field references silently collapse to empty
strings — turning a provider error into a cryptic bash failure 5 nodes later.

This script catches the corruption **at the boundary** so the bash node that
calls it exits non-zero, the DAG stops, and the operator sees a clear message
instead of hunting through log files.

Usage:
  python3 scripts/aw-validate-output.py [--schema EPIC|CONFIGURE] <RAW_OUTPUT>

Exit 0 → output is valid JSON matching the expected shape.
Exit 1 → output is corrupted (rate limit / credit / auth / malformed JSON).

The --schema flag is optional.  Without it only the basic liveness checks
run (rate-limit text, credit exhaustion, JSON parse).  With --schema the
script also verifies required fields for a known workflow node.
"""

import json
import re
import sys

# ── Patterns that indicate a provider rejection (not real AI output) ──────────

RATE_LIMIT_PATTERNS = [
    r"You('ve| have) hit your (session|rate) limit",
    r"rate limit",
    r"too many requests",
    r"exceeded your (current )?quota",
    r"try again in",
    r"resets?\s+\d",
    r"429",
    r"503",
]

CREDIT_EXHAUSTION_PATTERNS = [
    r"credit balance",
    r"out of credits",
    r"insufficient.*credit",
    r"billing.*limit",
    r"usage limit",
]

AUTH_FAILURE_PATTERNS = [
    r"unauthorized",
    r"authentication failed",
    r"invalid.*(api.?key|token)",
    r"401",
    r"403",
    r"not authenticated",
]


def _matches_any(text: str, patterns: list[str]) -> bool:
    lowered = text.lower()
    return any(re.search(p, lowered) for p in patterns)


def _check_liveness(raw: str) -> str | None:
    """Return an error string if the output looks like a provider rejection."""
    if _matches_any(raw, RATE_LIMIT_PATTERNS):
        return "rate limit message detected"
    if _matches_any(raw, CREDIT_EXHAUSTION_PATTERNS):
        return "credit exhaustion message detected"
    if _matches_any(raw, AUTH_FAILURE_PATTERNS):
        return "auth failure message detected"
    return None


def _parse_json(raw: str) -> tuple[dict | None, str | None]:
    """Try to parse raw text as JSON. Returns (parsed, error)."""
    stripped = raw.strip()
    if not stripped:
        return None, "empty output"
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError as e:
        return None, f"invalid JSON: {e}"
    if not isinstance(parsed, dict):
        return None, f"expected JSON object, got {type(parsed).__name__}"
    return parsed, None


# ── Schema validators (one per upstream node that feeds into configure) ───────

READ_EPIC_REQUIRED = [
    "epic_id",
    "scope",
    "implementation_paths",
    "tests_paths",
    "implementation_acceptance",
    "tests_acceptance",
    "spec_section",
]


def _validate_read_epic(parsed: dict) -> str | None:
    """Validate the read-epic output schema."""
    missing = [k for k in READ_EPIC_REQUIRED if k not in parsed]
    if missing:
        return f"missing required fields: {missing}"
    if not isinstance(parsed.get("implementation_paths"), list):
        return "implementation_paths must be a list"
    if not isinstance(parsed.get("tests_paths"), list):
        return "tests_paths must be a list"
    return None


SCHEMA_VALIDATORS = {
    "EPIC": _validate_read_epic,
}


def main() -> None:
    import argparse

    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("raw_output", help="Raw node output text to validate")
    p.add_argument(
        "--schema",
        choices=list(SCHEMA_VALIDATORS),
        default=None,
        help="Also validate against a known node schema",
    )
    args = p.parse_args()
    raw = args.raw_output

    # 1. Liveness check (rate limit / credit / auth)
    liveness_err = _check_liveness(raw)
    if liveness_err:
        print(f"VALIDATE FAILED (liveness): {liveness_err}", file=sys.stderr)
        sys.exit(1)

    # 2. JSON parse check
    parsed, json_err = _parse_json(raw)
    if json_err:
        # Before failing on JSON parse, double-check: some rate limit messages
        # start as valid JSON (e.g. {"error": "rate limit exceeded"}) but we
        # want to catch those via liveness first. If liveness passed but JSON
        # still fails, the output is genuinely malformed.
        print(f"VALIDATE FAILED (JSON): {json_err}", file=sys.stderr)
        sys.exit(1)

    # 3. Schema check (only when --schema is specified)
    if args.schema:
        validator = SCHEMA_VALIDATORS[args.schema]
        schema_err = validator(parsed)
        if schema_err:
            print(f"VALIDATE FAILED (schema={args.schema}): {schema_err}", file=sys.stderr)
            sys.exit(1)

    # All checks passed
    print("VALIDATE OK", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
