#!/usr/bin/env bash
# update-codebase-summary.sh — regenerate the AUTO-GENERATED section of
# CODEBASE-SUMMARY.md from project metadata.
#
# What is auto-generated (deterministic, zero AI tokens):
#   - Python + TypeScript workspace package list
#   - Source file counts per package
#   - Test file index (grouped by package)
#   - Gate commands (lint / typecheck / test per scope)
#   - Compiler module map (if packages/simulator exists)
#   - Recent epics log (appended by the workflow after each commit)
#
# What stays human/agent-maintained (between AGENT-START / AGENT-END):
#   - Architectural patterns
#   - Cross-cutting design decisions
#
# Usage:
#   bash scripts/update-codebase-summary.sh          # regenerate in-place
#   bash scripts/update-codebase-summary.sh --check  # exit 1 if outdated
#
# Called automatically by the Archon workflow (update-context node) after
# each successful commit.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
OUT="$ROOT/CODEBASE-SUMMARY.md"
CHECK="${1:-}"

# ── Generate the AUTO section ─────────────────────────────────────────────────
NEW_AUTO="$(python3 - "$ROOT" <<'PY'
import sys, pathlib, re, json, subprocess
from datetime import date

root = pathlib.Path(sys.argv[1])

lines = []
def h(t): lines.append(f"### {t}")
def li(t): lines.append(f"- {t}")
def blank(): lines.append("")

# ── Python packages ──────────────────────────────────────────────────────────
pyproj_root = root / "pyproject.toml"
py_packages = []
if pyproj_root.exists():
    txt = pyproj_root.read_text()
    m = re.search(r'\[tool\.uv\.workspace\].*?members\s*=\s*\[([^\]]+)\]', txt, re.DOTALL)
    if m:
        py_packages = re.findall(r'"([^"]+)"', m.group(1))

# ── TypeScript packages ───────────────────────────────────────────────────────
ts_packages = []
pnpm_ws = root / "pnpm-workspace.yaml"
if pnpm_ws.exists():
    import yaml
    ws = yaml.safe_load(pnpm_ws.read_text())
    ts_packages = ws.get("packages", [])

# ── Count source files per package ───────────────────────────────────────────
def count_src(pkg_path: pathlib.Path, exts):
    if not pkg_path.exists():
        return 0
    return sum(1 for f in pkg_path.rglob("*")
               if f.suffix in exts
               and "test" not in f.stem.lower()
               and ".test." not in f.name
               and ".spec." not in f.name
               and "node_modules" not in f.parts
               and ".venv" not in f.parts
               and "__pycache__" not in f.parts
               and "generated" not in f.parts
               and "dist" not in f.parts)

# ── Gate commands ─────────────────────────────────────────────────────────────
backend_gates = []
frontend_gates = []

# Python: ruff + mypy from first simulator-like package
for pkg in py_packages:
    pp = root / pkg / "pyproject.toml"
    if pp.exists() and "simulator" in pkg:
        backend_gates.append("uv run ruff check packages/simulator/src/")
        backend_gates.append("uv run mypy packages/simulator/src/")
        backend_gates.append("bash scripts/aw-test-backend.sh")
        break
if not backend_gates and py_packages:
    backend_gates = ["uv run ruff check .", "uv run pytest -q"]

# TS: from frontend package.json
for pkg in ts_packages:
    pj = root / pkg / "package.json"
    if pj.exists() and "frontend" in pkg:
        scripts = json.loads(pj.read_text()).get("scripts", {})
        if "typecheck" in scripts:
            frontend_gates.append(f"pnpm --filter {pathlib.Path(pkg).name} typecheck")
        frontend_gates.append("bash scripts/aw-test-frontend.sh")
        break

# ── Compiler module map ───────────────────────────────────────────────────────
compiler_dir = root / "packages/simulator/src/simulator/compiler"
compiler_modules = []
if compiler_dir.exists():
    compiler_modules = sorted(
        p.stem for p in compiler_dir.iterdir()
        if p.suffix == ".py" and p.stem != "__init__"
        and "__pycache__" not in str(p)
    )

# ── Test file index ────────────────────────────────────────────────────────────
from collections import defaultdict
test_groups: dict = defaultdict(list)
for pat in ("test_*.py", "*.test.ts", "*.test.tsx", "*.spec.ts"):
    for f in root.rglob(pat):
        parts = f.relative_to(root).parts
        # Only look inside apps/, packages/, tests/ — skip worktrees, vendor, OSS dirs
        if not parts or parts[0] not in ("apps", "packages", "tests"):
            continue
        # group by first two path components
        group = "/".join(parts[:2])
        test_groups[group].append("/".join(parts[2:]))

# ── Build output ──────────────────────────────────────────────────────────────
lines.append(f"*Last updated: {date.today()}*")
blank()

h("Workspace packages")
if py_packages:
    lines.append("")
    lines.append("**Python (uv workspace):**")
    for pkg in py_packages:
        n = count_src(root / pkg, {".py"})
        li(f"`{pkg}/` — {n} source files")
if ts_packages:
    blank()
    lines.append("**TypeScript (pnpm workspace):**")
    for pkg in ts_packages:
        n = count_src(root / pkg, {".ts", ".tsx"})
        li(f"`{pkg}/` — {n} source files")

blank()
h("Gate commands per scope")
if backend_gates:
    lines.append("")
    lines.append("**backend:**")
    for g in backend_gates:
        li(f"`{g}`")
if frontend_gates:
    blank()
    lines.append("**frontend:**")
    for g in frontend_gates:
        li(f"`{g}`")

if compiler_modules:
    blank()
    h("packages/simulator/src/simulator/compiler — modules")
    for m in compiler_modules:
        li(f"`{m}.py`")

blank()
h("Test file index")
for group in sorted(test_groups):
    files = sorted(test_groups[group])
    lines.append("")
    lines.append(f"**{group}/** ({len(files)} test files)")
    for f in files[:8]:
        li(f"`{f}`")
    if len(files) > 8:
        li(f"… +{len(files) - 8} more")

print("\n".join(lines))
PY
)"

# ── Splice into CODEBASE-SUMMARY.md ──────────────────────────────────────────
MARKER_START="<!-- AUTO-GENERATED:START -->"
MARKER_END="<!-- AUTO-GENERATED:END -->"

if [[ ! -f "$OUT" ]]; then
  echo "CODEBASE-SUMMARY.md not found at $OUT" >&2
  exit 1
fi

python3 - "$OUT" "$MARKER_START" "$MARKER_END" "$NEW_AUTO" <<'PY'
import sys, pathlib
out, start, end, new_content = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
txt = pathlib.Path(out).read_text()
# Replace between markers (inclusive of marker lines)
pattern = f"{start}\n.*?{end}"
import re
replacement = f"{start}\n{new_content}\n{end}"
new_txt, n = re.subn(pattern, replacement, txt, count=1, flags=re.DOTALL)
if n == 0:
    print(f"WARNING: markers not found in {out}", file=sys.stderr)
    sys.exit(1)
pathlib.Path(out).write_text(new_txt)
print(f"updated {out}")
PY

if [[ "$CHECK" == "--check" ]]; then
  if git diff --quiet "$OUT"; then
    echo "CODEBASE-SUMMARY.md is up to date"
    exit 0
  else
    echo "CODEBASE-SUMMARY.md is stale — run scripts/update-codebase-summary.sh" >&2
    exit 1
  fi
fi
