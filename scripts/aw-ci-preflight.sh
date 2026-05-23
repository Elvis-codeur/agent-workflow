#!/usr/bin/env bash
# aw-ci-preflight.sh — run the project's "fast" CI gates locally before committing.
#
# Reads .github/workflows/ci.yml, extracts every job step that can run without
# external services (no apt-get, no Docker, no Playwright install), and runs them.
# Also auto-detects Django migrations and lockfile integrity checks.
#
# Outputs bare "PASS" to stdout on success; full failure output to stdout on failure.
# ALWAYS exits 0 — failure signalled by stdout content (same contract as aw-test-*.sh).
#
# Project-specific override: add scripts/aw-ci-custom.sh; it will be sourced at the
# end and can override any SKIP_* flag or append to FAILURES[].
#
# Usage (called from the 'ci-check' DAG node):
#   bash scripts/aw-ci-preflight.sh [EPIC_ID] [SCOPE]
set -uo pipefail
EPIC="${1:-}"
SCOPE="${2:-all}"
ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
cd "$ROOT"

TMPOUT="$(mktemp)"
FAILURES=()

# ── Branch-scoped file list ───────────────────────────────────────────────────
# Lint/format/typecheck steps are narrowed to files changed by THIS branch
# vs origin/main, so pre-existing rot on main doesn't block our autonomous
# loop. The full CI job on GitHub still runs against everything; this is a
# pre-flight gate, not a full CI replacement.
BASE_REF="${AW_CI_BASE_REF:-origin/main}"
if ! git rev-parse --verify "$BASE_REF" &>/dev/null; then
  BASE_REF="$(git merge-base HEAD origin/HEAD 2>/dev/null || echo HEAD~1)"
fi
# Files changed in this branch (added/modified, no deletions)
CHANGED_FILES="$(git diff --name-only --diff-filter=AM "$BASE_REF"...HEAD 2>/dev/null \
  | grep -v -E '^(\.archon|\.git|node_modules|\.venv)/' || true)"
export CHANGED_FILES BASE_REF

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "  [ci] $*" >&2; }
fail() { FAILURES+=("$1"); log "FAILED: $1"; }

run_step() {
  local label="$1"; local cmd="$2"
  log "running: $label"
  if eval "$cmd" >> "$TMPOUT" 2>&1; then
    log "  ✓ $label"
  else
    fail "$label"
    log "  ✗ $label"
  fi
}

# Steps to skip (require infra / too slow for preflight)
should_skip() {
  local step="$1"
  echo "$step" | grep -qiE \
    'apt-get|brew install|yum install|apk add|chocolatey|winget|
     playwright.*install.*--with-deps|--with-deps|
     docker|docker-compose|podman|
     sudo |systemctl|service |
     vite build|next build|webpack.*build|npm run build|pnpm.*build|
     playwright test|cypress|selenium|puppeteer|
     e2e|integration.*test|uv run pytest.*tests/(integration|e2e|smoke)'
}

# ── 1. Auto-parse .github/workflows/ci.yml ────────────────────────────────────
CI_YAML="$ROOT/.github/workflows/ci.yml"

if [[ -f "$CI_YAML" ]]; then
  log "parsing $CI_YAML"
  python3 - "$CI_YAML" >> "$TMPOUT" 2>&1 <<'PYEOF'
import yaml, sys, os, subprocess, pathlib

ci = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())
jobs = ci.get("jobs", {})

# Jobs to skip entirely (infra-heavy or covered elsewhere)
SKIP_JOBS = {"e2e", "deploy", "release", "publish", "docker", "staging"}

for job_name, job in jobs.items():
    if job_name.lower() in SKIP_JOBS:
        print(f"  [ci] skipping job '{job_name}' (infra/deploy)")
        continue

    steps = job.get("steps", [])
    for step in steps:
        cmd = step.get("run", "")
        if not cmd:
            continue
        # Skip infra steps
        skip_patterns = [
            "apt-get", "brew install", "yum ", "apk add", "chocolatey", "winget",
            "playwright install", "--with-deps", "docker", "sudo apt",
            "vite build", "next build", "npm run build", "pnpm run build",
            "e2e", "playwright test",
        ]
        if any(p in cmd.lower() for p in skip_patterns):
            print(f"  [ci] skipping step in '{job_name}': {cmd[:60].replace(chr(10),' ')}…")
            continue

        step_name = step.get("name", cmd[:50].replace("\n", " "))

        # ── Scope whole-repo lint/format/typecheck to branch-changed files ──
        # so pre-existing rot on main doesn't block this epic.
        changed = os.environ.get("CHANGED_FILES", "").strip().split("\n")
        changed = [f for f in changed if f]
        py_files  = [f for f in changed if f.endswith(".py")]
        ts_files  = [f for f in changed
                     if f.endswith((".ts", ".tsx", ".js", ".jsx", ".json"))]
        scoped_map = [
            ("uv run ruff format .",      "uv run ruff format",      py_files),
            ("uv run ruff format --check .", "uv run ruff format --check", py_files),
            ("uv run ruff check .",       "uv run ruff check",       py_files),
            ("uv run mypy",               "uv run mypy",             py_files),
            ("pnpm exec biome check .",   "pnpm exec biome check",   ts_files),
            ("pnpm biome check .",        "pnpm biome check",        ts_files),
        ]
        # Test runners we skip entirely when no in-scope files changed.
        # (Vitest/jest scoping to changed files is fragile across project layouts.)
        skip_if_no_files = [
            ("pnpm test",                  ts_files),
            ("pnpm run test",              ts_files),
            ("pnpm exec vitest",           ts_files),
            ("pnpm vitest",                ts_files),
            ("pnpm --filter",              ts_files),  # pnpm --filter <pkg> test/typecheck/build
            ("pnpm -F",                    ts_files),  # short form
            ("npm test",                   ts_files),
            ("npm run test",               ts_files),
            ("pnpm exec playwright",       ts_files),
        ]
        skipped_no_changes = False
        for needle, files in skip_if_no_files:
            if needle in cmd and not files:
                print(f"  [ci] ↳ {job_name}/{step_name}: no frontend files in scope, skipping")
                skipped_no_changes = True
                break
        if skipped_no_changes:
            continue
        for needle, replacement, files in scoped_map:
            if needle in cmd:
                if not files:
                    print(f"  [ci] ↳ {job_name}/{step_name}: no changed files in scope, skipping")
                    skipped_no_changes = True
                    break
                quoted = " ".join(f"'{f}'" for f in files)
                cmd = cmd.replace(needle, f"{replacement} {quoted}")
                print(f"  [ci] ↳ scoped to {len(files)} changed file(s)")
                break
        if skipped_no_changes:
            continue

        print(f"  [ci] → {job_name}/{step_name}")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        # pytest exit 5 = no tests collected; treat as warning, not failure
        if result.returncode == 5 and "pytest" in cmd:
            print(f"  [ci] ↳ pytest collected no tests; treating as pass")
            continue
        if result.returncode != 0:
            print(f"FAILED_STEP: {job_name}/{step_name}")
            sys.exit(1)

sys.exit(0)
PYEOF
  YAML_RC=$?
  [[ $YAML_RC -ne 0 ]] && fail "ci.yml-steps"
else
  log "no .github/workflows/ci.yml found — running auto-detection only"
fi

# ── 2. Django migrations check (auto-detect in any project) ───────────────────
MANAGE_PY="$(find "$ROOT" -name "manage.py" \
  -not -path "*/node_modules/*" -not -path "*/.venv/*" \
  -not -path "*/.git/*" 2>/dev/null | head -1)"

if [[ -n "$MANAGE_PY" ]]; then
  log "Django detected: $MANAGE_PY"
  MANAGE_DIR="$(dirname "$MANAGE_PY")"
  if command -v uv &>/dev/null; then
    PYTHON_CMD="uv run python"
  else
    PYTHON_CMD="python3"
  fi
  # Check for missing migrations
  if ! $PYTHON_CMD "$MANAGE_PY" makemigrations --check --dry-run \
       >> "$TMPOUT" 2>&1; then
    fail "django-migrations-stale"
    echo "  FIX: cd $MANAGE_DIR && python manage.py makemigrations" >> "$TMPOUT"
  else
    log "  ✓ Django migrations up to date"
  fi
fi

# ── 3. Python lockfile integrity ───────────────────────────────────────────────
if [[ -f "$ROOT/uv.lock" ]] && command -v uv &>/dev/null; then
  if ! uv lock --check >> "$TMPOUT" 2>&1; then
    fail "uv-lock-stale"
    echo "  FIX: uv lock" >> "$TMPOUT"
  else
    log "  ✓ uv.lock is up to date"
  fi
fi

# ── 4. Node lockfile integrity ─────────────────────────────────────────────────
if [[ -f "$ROOT/pnpm-lock.yaml" ]] && command -v pnpm &>/dev/null; then
  if ! pnpm install --frozen-lockfile &>/dev/null 2>&1; then
    fail "pnpm-lock-stale"
    echo "  FIX: pnpm install" >> "$TMPOUT"
  else
    log "  ✓ pnpm-lock.yaml is up to date"
  fi
fi

# ── 5. Project-specific override hook ─────────────────────────────────────────
if [[ -x "$ROOT/scripts/aw-ci-custom.sh" ]]; then
  log "running project override: scripts/aw-ci-custom.sh"
  if ! bash "$ROOT/scripts/aw-ci-custom.sh" "$EPIC" "$SCOPE" \
       >> "$TMPOUT" 2>&1; then
    fail "aw-ci-custom"
  fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
if [[ ${#FAILURES[@]} -eq 0 ]]; then
  cat "$TMPOUT" >&2   # progress to stderr (visible in Archon UI)
  rm -f "$TMPOUT"
  echo "PASS"
else
  echo "CI_PREFLIGHT_FAILED: ${FAILURES[*]}"
  echo ""
  cat "$TMPOUT"
  rm -f "$TMPOUT"
  echo ""
  echo "=== Failures: ${FAILURES[*]} ==="
  echo "The fix-ci agent will address these. Common commands:"
  echo "  django migrations : python manage.py makemigrations"
  echo "  uv lock           : uv lock"
  echo "  pnpm lock         : pnpm install"
  echo "  ruff format       : uv run ruff format ."
  echo "  biome format      : pnpm exec biome check --write ."
  echo "  cargo fmt         : cargo fmt"
  echo "  schema codegen    : pnpm -F @gensim/schemas codegen"
fi
