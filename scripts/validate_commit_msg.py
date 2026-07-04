#!/usr/bin/env python3
"""Validate repository commit-message subjects (Conventional Commits + house rules).

Invoked by .githooks/commit-msg. Also runnable directly:

  validate_commit_msg.py --file <commit-msg-file>
  validate_commit_msg.py --message "<commit-subject>"

Rules enforced on the subject line:
  - must be `type(scope): summary` or `type: summary`
  - type ∈ ALLOWED_TYPES; optional `!` before the colon marks a breaking change
  - summary must not be a vague placeholder (FORBIDDEN_SUMMARIES)
  - `Merge ...` and `Revert ...` subjects are exempt
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Full Conventional Commits type set (kept broad on purpose — the house style
# uses perf/style/build/ci/revert in addition to the core types).
ALLOWED_TYPES = {
    "feat", "fix", "docs", "style", "refactor",
    "perf", "test", "build", "ci", "chore", "revert",
}

SPECIAL_PREFIXES = ("Merge ", "Revert ")

# Vague, purpose-free summaries that hide what actually changed.
FORBIDDEN_SUMMARIES = {
    "update", "updates", "misc", "misc changes", "changes",
    "fix stuff", "wip", "work in progress", "temp", "tmp",
    "stuff", "minor changes", "various fixes",
}

# `!` (breaking-change marker) allowed after type or after (scope).
PATTERN = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[a-z0-9_-]+)\))?(?P<bang>!)?: (?P<summary>.+)$")


def validate_subject(subject: str) -> list[str]:
    subject = subject.rstrip("\n")
    errors: list[str] = []

    if not subject.strip():
        return ["Commit message subject must not be empty."]

    if subject.startswith(SPECIAL_PREFIXES):
        return []

    match = PATTERN.match(subject)
    if not match:
        return [
            "Commit subject must match 'type(scope): summary' or 'type: summary' "
            "(optionally 'type!: summary' for breaking changes).",
        ]

    commit_type = match.group("type")
    summary = match.group("summary")

    if commit_type not in ALLOWED_TYPES:
        errors.append("Commit type must be one of: " + ", ".join(sorted(ALLOWED_TYPES)) + ".")

    if summary.lower().strip() in FORBIDDEN_SUMMARIES:
        errors.append("Commit summary is too vague. Describe the purpose of the change, not a generic action.")

    if summary != summary.lstrip():
        errors.append("Commit summary must not start with extra whitespace.")

    return errors


def _usage() -> str:
    return (
        "Usage:\n"
        "  validate_commit_msg.py --file <commit-msg-file>\n"
        "  validate_commit_msg.py --message <commit-subject>\n"
    )


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in {"--file", "--message"}:
        sys.stderr.write(_usage())
        return 2

    if argv[1] == "--file":
        text = Path(argv[2]).read_text(encoding="utf-8")
        lines = text.splitlines()
        subject = lines[0] if lines else ""
    else:
        subject = argv[2]

    errors = validate_subject(subject)
    if not errors:
        return 0

    sys.stderr.write("Invalid commit message subject:\n")
    sys.stderr.write(f"  {subject or '<empty>'}\n\n")
    for error in errors:
        sys.stderr.write(f"- {error}\n")
    sys.stderr.write(
        "\nExamples:\n"
        "- feat(scheduler): add cron-based download windows\n"
        "- fix(api): handle stdout chunks larger than 64KB\n"
        "- refactor!: rename public DownloadJob fields\n"
        "- docs: document the schedule CRUD workflow\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
