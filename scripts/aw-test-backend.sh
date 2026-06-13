#!/usr/bin/env bash
# aw-test-backend.sh — backend test runner for the Archon aw-master-loop workflow.
#
# Called by scripts/aw-run-tests.sh when scope=backend.
# Receives the epic ID as $1.
#
# Contract (GOTCHA-004):
#   - ALWAYS exits 0. Failure is signalled by stdout content != "PASS".
#   - On success: prints bare "PASS" to stdout.
#   - On failure: prints the full pytest output to stdout.
#
# Package install (GOTCHA-003):
#   - Archon worktrees share .venv but packages may not be installed.
#   - `uv sync` resolves ALL extras including [docs] which pulls sphinx>=8
#     requiring Python>=3.10.  Projects with requires-python>=3.8 deadlock.
#   - Skip uv sync entirely — go straight to system python3 + PYTHONPATH.
#     The system interpreter already has pytest, yt-dlp, django, etc.

set -uo pipefail

EPIC="${1:-}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# ── Epic-scoped test paths ─────────────────────────────────────────────────────
# Add one line per epic when new backend epics are introduced.
# Each value is a space-separated list of pytest paths for that epic.
# When running without an epic (e.g. full-suite CI), all paths are run.
declare -A EPIC_TESTS=(
  # yt-auto-scraper epics
  [E-24]="tests/service/test_download_hardening_config.py tests/service/test_worker_download_timeout_passthrough.py tests/youtube_scraping/test_download_antibot_hardening.py"
  # Add new epics here as they are introduced.
)

if [[ -n "$EPIC" && -n "${EPIC_TESTS[$EPIC]+_}" ]]; then
  TEST_PATHS="${EPIC_TESTS[$EPIC]}"
else
  # No epic-specific paths: run the full backend suite
  TEST_PATHS="tests/"
fi

# ── Run pytest ────────────────────────────────────────────────────────────────
# Use system python3 directly — uv sync deadlocks on sphinx/docs extras.
TMPOUT="$(mktemp)"
RC=0

# shellcheck disable=SC2086   # word-splitting of TEST_PATHS is intentional
if PYTHONPATH=src python3 -m pytest $TEST_PATHS -q 2>&1 | tee "$TMPOUT"; then
  RC=0
else
  RC=1
fi

if [[ $RC -eq 0 ]]; then
  rm -f "$TMPOUT"
  echo "PASS"
else
  cat "$TMPOUT"
  rm -f "$TMPOUT"
  # Do NOT exit 1 — see GOTCHA-004: failure signalled by stdout content, not exit code
fi
