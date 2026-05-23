#!/usr/bin/env python3
"""
aw-configure.py — decide which workflow phases to execute for one epic.

Usage (called from the 'configure' DAG bash node):
  python3 scripts/aw-configure.py EPIC_ID SCOPE TESTS_PATHS_JSON [FLAGS...]

Flags (forwarded from aw-run):
  --skip-implement      force-skip the implement node
  --skip-write-tests    force-skip the write-tests node

Outputs one JSON line consumed by downstream 'when:' conditions:
  {"skip_implement":"false","skip_write_tests":"false",
   "mode":"full","reason":"...","epic_status":"planned","tests_exist":"false"}

Auto-detection logic (no flags needed):
  status == review or complete  → skip_implement = true
  skip_implement AND all test files exist in CWD → skip_write_tests = true

Modes:
  full            implement + write-tests + run-tests
  tests-only      skip implement; write tests if missing, then run
  implement-only  skip write-tests; implement then run existing tests
  reuse-tests     skip implement + skip write-tests; just run existing tests
"""

import argparse
import json
import os
import pathlib
import sys


def get_epic_status(root: pathlib.Path, epic_id: str) -> str:
    """Read the current status of an epic from progress.*.yaml files."""
    try:
        import yaml  # type: ignore[import-untyped]
    except ImportError:
        return ""
    for fname in ["progress.backend.yaml", "progress.frontend.yaml"]:
        try:
            data = yaml.safe_load((root / fname).read_text())
            key = next((k for k in data if "epics" in k or k == "epics"), None)
            if not key:
                continue
            for ep in data[key]:
                if ep["id"] == epic_id:
                    return ep.get("status", "")
        except Exception:
            pass
    return ""


def all_tests_exist(root: pathlib.Path, tests_paths_json: str) -> bool:
    """Return True when every test file in tests_paths already exists."""
    try:
        paths = json.loads(tests_paths_json)
        return bool(paths) and all((root / p).exists() for p in paths)
    except Exception:
        return False


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("epic_id")
    p.add_argument("scope")
    p.add_argument("tests_paths_json")
    p.add_argument("--skip-implement",   action="store_true", default=False)
    p.add_argument("--skip-write-tests", action="store_true", default=False)
    args = p.parse_args()

    # Resolve the main repo root (works from both a worktree and the main checkout)
    try:
        import subprocess

        git_common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
        root = pathlib.Path(git_common).parent.resolve()
    except Exception:
        root = pathlib.Path.cwd()

    status  = get_epic_status(root, args.epic_id)
    t_exist = all_tests_exist(root, args.tests_paths_json)

    # --- compute skip flags ---
    # Auto-detect: implementation is complete if status is review or complete
    skip_impl  = args.skip_implement or status in ("review", "complete")
    # Auto-detect: if we're skipping implement AND tests already exist, skip write-tests
    skip_tests = args.skip_write_tests or (skip_impl and t_exist)

    # --- compute human-readable mode and reason ---
    if   skip_impl  and skip_tests:      mode = "reuse-tests"
    elif skip_impl  and not skip_tests:  mode = "tests-only"
    elif not skip_impl and skip_tests:   mode = "implement-only"
    else:                                mode = "full"

    reasons: list[str] = []
    if args.skip_implement:
        reasons.append("--skip-implement flag")
    if args.skip_write_tests:
        reasons.append("--skip-write-tests flag")
    if status in ("review", "complete") and not args.skip_implement:
        reasons.append(f"auto: status={status}")
    if t_exist and skip_impl and not args.skip_write_tests:
        reasons.append("auto: all test files present")
    reason = "; ".join(reasons) if reasons else "no overrides (full run)"

    result = {
        "skip_implement":   str(skip_impl).lower(),    # "true" or "false"
        "skip_write_tests": str(skip_tests).lower(),
        "mode":             mode,
        "reason":           reason,
        "epic_status":      status,
        "tests_exist":      str(t_exist).lower(),
    }

    # Emit to stderr for human visibility, then print JSON to stdout
    # (stdout is captured as $configure.output by Archon)
    print(
        f"  configure: mode={mode}  skip_impl={skip_impl}  skip_tests={skip_tests}"
        f"  status={status!r}  tests_exist={t_exist}",
        file=sys.stderr,
    )
    print(json.dumps(result))


if __name__ == "__main__":
    main()
