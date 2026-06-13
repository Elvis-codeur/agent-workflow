#!/usr/bin/env python3
"""
aw-read-epic.py — deterministic epic reader (no AI, no rate limits).

Replaces the AI-powered 'read-epic' DAG node. Reads the project's
progress.*.yaml files and emits the same JSON shape that the AI node
was expected to produce:

  { "epic_id": "...", "scope": "...",
    "implementation_paths": [...], "tests_paths": [...],
    "implementation_acceptance": "...", "tests_acceptance": "...",
    "spec_section": "..." }

Usage:
  python3 scripts/aw-read-epic.py EPIC_ID

Exit 0 on success (valid JSON on stdout). Exit 1 if the epic is not found
or if required YAML / JSON dependencies are missing.
"""

import json
import pathlib
import sys

PROGRESS_FILES = ["progress.yaml", "progress.backend.yaml", "progress.frontend.yaml"]


def _find_epic(root: pathlib.Path, epic_id: str) -> dict:
    """Return the epic dict from the first progress file that defines it, or {}."""
    try:
        import yaml  # type: ignore[import-untyped]
    except ImportError as exc:
        print(f"ERROR: PyYAML not installed — {exc}", file=sys.stderr)
        sys.exit(1)

    for fname in PROGRESS_FILES:
        path = root / fname
        if not path.exists():
            continue
        try:
            data = yaml.safe_load(path.read_text())
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        # Find the epics key (some repos use 'epics:', some use a scoped variant)
        key = next((k for k in data if "epics" in k or k == "epics"), None)
        if not key:
            continue
        for ep in data[key]:
            if isinstance(ep, dict) and ep.get("id") == epic_id:
                return ep

    # Not found — check which files were searched for a useful error
    searched = [f for f in PROGRESS_FILES if (root / f).exists()]
    if not searched:
        print(f"ERROR: no progress file found (searched {PROGRESS_FILES})", file=sys.stderr)
    else:
        print(
            f"ERROR: epic '{epic_id}' not found in {searched}",
            file=sys.stderr,
        )
    sys.exit(1)
    return {}  # unreachable — sys.exit above


def _resolve_scope(epic: dict) -> str:
    """Derive the scope string from the epic's 'area' or 'scope' field."""
    # Prefer explicit 'scope' field; fall back to 'area'
    scope = epic.get("scope") or epic.get("area", "")
    return scope.strip()


def _resolve_implementation_paths(epic: dict) -> list[str]:
    """Extract implementation file paths from the epic."""
    impl = epic.get("implementation", {})
    return impl.get("paths", []) if isinstance(impl, dict) else []


def _resolve_tests_paths(epic: dict) -> list[str]:
    """Extract test file paths from the epic."""
    tests = epic.get("tests", {})
    return tests.get("paths", []) if isinstance(tests, dict) else []


def _resolve_implementation_acceptance(epic: dict) -> str:
    """Extract implementation acceptance criteria as a plain string."""
    impl = epic.get("implementation", {})
    acceptance = impl.get("acceptance", []) if isinstance(impl, dict) else []
    if isinstance(acceptance, str):
        return acceptance
    if isinstance(acceptance, list):
        return "\n".join(f"- {item}" for item in acceptance)
    return ""


def _resolve_tests_acceptance(epic: dict) -> str:
    """Extract test acceptance criteria as a plain string."""
    tests = epic.get("tests", {})
    acceptance = tests.get("acceptance", []) if isinstance(tests, dict) else []
    if isinstance(acceptance, str):
        return acceptance
    if isinstance(acceptance, list):
        return "\n".join(f"- {item}" for item in acceptance)
    return ""


def _resolve_spec_section(epic: dict) -> str:
    """Derive the spec section reference from epic metadata."""
    # Some epics have an explicit spec_section field
    spec = epic.get("spec_section") or epic.get("spec", "")
    if spec:
        return spec.strip()

    # Fallback: build from the summary/description
    summary = epic.get("summary") or epic.get("description", "")
    # Clean up multi-line YAML strings
    if isinstance(summary, str):
        return summary.strip().replace("\n", " ")
    return ""


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: aw-read-epic.py EPIC_ID", file=sys.stderr)
        sys.exit(1)

    epic_id = sys.argv[1]

    # Resolve the main repo root (works from both a worktree and the main checkout)
    try:
        import subprocess

        git_common = subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip()
        root = pathlib.Path(git_common).parent.resolve()
    except Exception:
        root = pathlib.Path.cwd()

    epic = _find_epic(root, epic_id)

    result = {
        "epic_id": epic_id,
        "scope": _resolve_scope(epic),
        "implementation_paths": _resolve_implementation_paths(epic),
        "tests_paths": _resolve_tests_paths(epic),
        "implementation_acceptance": _resolve_implementation_acceptance(epic),
        "tests_acceptance": _resolve_tests_acceptance(epic),
        "spec_section": _resolve_spec_section(epic),
    }

    # Print JSON to stdout (consumed by Archon as $read-epic.output)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
