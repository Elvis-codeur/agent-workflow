#!/usr/bin/env bash
# aw-run-all.sh — run every open epic through the Archon master-loop in
# topological (dependency) order, merge each completed branch to main,
# then unlock the next layer.
#
# Usage:
#   scripts/aw-run-all.sh [options] [-- <aw-run-flags>...]
#
# Options:
#   --scope  backend|frontend|all   only run epics of this scope (default: all)
#   --from   EPIC-ID                skip epics that come before EPIC-ID in the
#                                   execution order (resume a partial run)
#   --workers N                     run up to N epics in parallel within a layer
#                                   (default: 1 = fully sequential)
#   --continue-on-error             log a failed epic and keep going instead of
#                                   stopping immediately (default: stop)
#   --no-push                       skip `git push origin main` after each merge
#   --dry-run                       print the execution plan and exit
#
# Everything after -- is forwarded verbatim to `scripts/aw-run`, e.g.:
#   scripts/aw-run-all.sh -- --max-fix-attempts 5 --no-autocommit
#
# Prerequisites:
#   • Working tree should be clean (stash WIP first to avoid merge conflicts)
#   • `archon` ≥ 0.3.10 in PATH
#   • Progress files: progress.backend.yaml and/or progress.frontend.yaml

set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ── Parse flags ───────────────────────────────────────────────────────────────
SCOPE="all"
FROM_EPIC=""
WORKERS=1
CONTINUE_ON_ERROR=0
PUSH=1
DRY=0
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)             SCOPE="$2"; shift 2 ;;
    --from)              FROM_EPIC="$2"; shift 2 ;;
    --workers)           WORKERS="$2"; shift 2 ;;
    --continue-on-error) CONTINUE_ON_ERROR=1; shift ;;
    --no-push)           PUSH=0; shift ;;
    --dry-run)           DRY=1; shift ;;
    --)                  shift; EXTRA=("$@"); break ;;
    -*)                  echo "unknown flag: $1" >&2; exit 2 ;;
    *)                   echo "unexpected arg: $1" >&2; exit 2 ;;
  esac
done

# ── Build execution plan (topological layers) ─────────────────────────────────
PLAN="$(python3 - "$SCOPE" "$FROM_EPIC" <<'PY'
import sys, yaml, json

scope_filter = sys.argv[1]   # "all" | "backend" | "frontend"
from_epic    = sys.argv[2]   # "" | "EPIC-ID"

def load_epics(fname, scope):
    try: data = yaml.safe_load(open(fname))
    except FileNotFoundError: return {}
    key = next((k for k in data if "epics" in k or k == "epics"), None)
    if not key: return {}
    return {ep["id"]: {**ep, "_scope": scope} for ep in data[key]}

epics = {}
epics.update(load_epics("progress.backend.yaml",  "backend"))
epics.update(load_epics("progress.frontend.yaml",  "frontend"))

# Epics already complete (treat merged-but-not-updated as complete too)
complete = {eid for eid, ep in epics.items() if ep.get("status") == "complete"}

OPEN = ("planned", "blocked", "in_progress", "review")
open_eps = {
    eid: ep for eid, ep in epics.items()
    if ep.get("status") in OPEN
    and (scope_filter == "all" or ep["_scope"] == scope_filter)
}

# Topological layers
layers, done = [], set(complete)
# Include complete epics from all scopes (needed for cross-scope deps)
all_complete = {eid for eid, ep in epics.items() if ep.get("status") == "complete"}
done = set(all_complete)

while True:
    layer = [
        eid for eid in open_eps
        if eid not in done
        and all(d in done for d in epics.get(eid, {}).get("depends_on", []))
    ]
    if not layer: break
    layer.sort()
    layers.append(layer)
    done |= set(layer)

# Flatten and apply --from filter
flat = [e for layer in layers for e in layer]
if from_epic:
    try: flat = flat[flat.index(from_epic):]
    except ValueError:
        print(f"ERROR: --from {from_epic} not found in plan", file=sys.stderr); sys.exit(1)

# Output: JSON list of {id, scope, layer} objects
plan = []
for i, layer in enumerate(layers):
    for eid in layer:
        if eid in flat:
            plan.append({"id": eid, "scope": epics[eid]["_scope"], "layer": i + 1})
print(json.dumps(plan))
PY
)"

if [[ $? -ne 0 ]]; then
  echo "error: failed to build execution plan" >&2
  exit 1
fi

TOTAL="$(echo "$PLAN" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"

# ── Print plan ────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  aw-run-all  │  scope=$SCOPE  workers=$WORKERS"
echo "═══════════════════════════════════════════════════════"
echo "$PLAN" | python3 -c "
import json, sys
plan = json.load(sys.stdin)
cur_layer = 0
for ep in plan:
    if ep['layer'] != cur_layer:
        cur_layer = ep['layer']
        print(f'  ── Layer {cur_layer} ' + '─' * 40)
    print(f'     {ep[\"id\"]:12s}  ({ep[\"scope\"]})')
print(f'  Total: {len(plan)} epics')
"
echo "═══════════════════════════════════════════════════════"

if [[ "$DRY" -eq 1 ]]; then
  echo "(dry-run — exiting)"
  exit 0
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

# Find the git worktree directory for a given epic ID.
# Archon normalises branch names to lower-case with dashes.
find_worktree() {
  local epic_id="$1"
  local safe
  safe="$(echo "$epic_id" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  # git worktree list --porcelain: first field is the path, second is HEAD sha,
  # third is branch ref.  Find the entry whose branch contains the epic slug.
  git worktree list --porcelain \
    | awk '/^worktree /{wt=$2} /^branch /{if($2 ~ SAFE){print wt}}' \
      SAFE="$safe"
}

# Merge a worktree branch to main, push, and clean up.
merge_and_cleanup() {
  local epic_id="$1"
  local branch="$2"    # full git branch name (e.g. archon/task-archon-epic-be-31)
  local wt_path="$3"   # absolute path to worktree

  echo "  → merging $branch to main"
  git checkout main
  git merge --no-ff "$branch" \
    -m "feat: $epic_id — Archon master-loop convergence

Automated merge by aw-run-all.sh." 2>&1 | tail -3

  if [[ "$PUSH" -eq 1 ]]; then
    echo "  → pushing main"
    git push origin main 2>&1 | tail -2
  fi

  echo "  → cleaning up worktree"
  git worktree remove --force "$wt_path" 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
}

# ── Run epics ─────────────────────────────────────────────────────────────────
LOG_DIR="$REPO_ROOT/.archon/run-all-logs"
mkdir -p "$LOG_DIR"

PASSED=0
FAILED=0
FAILED_EPICS=()

run_epic() {
  local epic_id="$1"
  local scope="$2"
  local log="$LOG_DIR/${epic_id}.log"

  echo ""
  echo "┌────────────────────────────────────────────────────"
  echo "│  Starting $epic_id  (scope: $scope)"
  echo "│  log: $log"
  echo "└────────────────────────────────────────────────────"

  set +e
  # --keep-worktree so we can merge the branch to main before cleanup
  scripts/aw-run --keep-worktree "${EXTRA[@]}" "$epic_id" 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ $rc -ne 0 ]]; then
    echo "  ✗ $epic_id FAILED (rc=$rc)"
    FAILED=$((FAILED + 1))
    FAILED_EPICS+=("$epic_id")
    if [[ "$CONTINUE_ON_ERROR" -eq 0 ]]; then
      echo "Stopping (use --continue-on-error to skip failures)" >&2
      exit "$rc"
    fi
    return
  fi

  # Locate the worktree that was just completed
  local wt_path branch
  wt_path="$(find_worktree "$epic_id")"
  if [[ -z "$wt_path" ]]; then
    echo "  ⚠ could not locate worktree for $epic_id — skipping merge"
  else
    branch="$(git -C "$wt_path" branch --show-current)"
    merge_and_cleanup "$epic_id" "$branch" "$wt_path"
  fi

  echo "  ✓ $epic_id DONE"
  PASSED=$((PASSED + 1))
}

# Sequential execution (WORKERS=1) or parallel within each layer
if [[ "$WORKERS" -le 1 ]]; then
  # Simple sequential: iterate through plan in layer order
  while IFS= read -r row; do
    epic_id="$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
    scope="$(echo "$row"   | python3 -c "import json,sys; print(json.load(sys.stdin)['scope'])")"
    run_epic "$epic_id" "$scope"
  done < <(echo "$PLAN" | python3 -c "import json,sys; [print(json.dumps(e)) for e in json.load(sys.stdin)]")
else
  # Parallel: group by layer, run up to WORKERS at a time within each layer
  echo "$PLAN" | python3 -c "
import json, sys
plan = json.load(sys.stdin)
layers = {}
for ep in plan:
    layers.setdefault(ep['layer'], []).append(ep)
for layer_num in sorted(layers):
    print('LAYER', layer_num)
    for ep in layers[layer_num]:
        print(json.dumps(ep))
    print('END_LAYER')
" | {
    layer_epics=()
    while IFS= read -r line; do
      if [[ "$line" == LAYER* ]]; then
        layer_epics=()
      elif [[ "$line" == END_LAYER ]]; then
        # Run layer_epics in parallel batches of WORKERS
        pids=()
        for row in "${layer_epics[@]}"; do
          epic_id="$(echo "$row" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
          scope="$(echo "$row"   | python3 -c "import json,sys; print(json.load(sys.stdin)['scope'])")"
          run_epic "$epic_id" "$scope" &
          pids+=($!)
          if [[ ${#pids[@]} -ge $WORKERS ]]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
          fi
        done
        # Wait remaining
        for pid in "${pids[@]}"; do wait "$pid"; done
        layer_epics=()
      else
        layer_epics+=("$line")
      fi
    done
  }
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  aw-run-all complete"
echo "  Passed: $PASSED / $TOTAL"
if [[ ${#FAILED_EPICS[@]} -gt 0 ]]; then
  echo "  Failed: $FAILED — ${FAILED_EPICS[*]}"
  echo "  Logs:   $LOG_DIR/"
  exit 1
else
  echo "  All epics converged ✓"
fi
echo "═══════════════════════════════════════════════════════"
