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
        print(f"  [ci] → {job_name}/{step_name}")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
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
