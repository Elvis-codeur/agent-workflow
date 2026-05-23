#!/usr/bin/env bash
# install.sh — inject the agent-workflow boilerplate into a target project.
#
# Usage:
#   ./install.sh                    # installs into the current directory
#   ./install.sh /path/to/project   # installs into the specified directory
#   ./install.sh --force .          # overwrites files that already exist
#
# Safe to re-run: existing files are not overwritten unless --force is passed.

set -eo pipefail

REPO_URL="https://github.com/Elvis-codeur/agent-workflow.git"
CLONED_DIR=""

# ── Locate the boilerplate source ─────────────────────────────────────────────
# When run via `curl | bash`, BASH_SOURCE[0] is empty or "/dev/stdin" — there
# are no local files to copy from. Clone the repo to a temp dir instead.
_src="${BASH_SOURCE[0]:-}"
if [[ -z "$_src" || "$_src" == "/dev/stdin" || "$_src" == "bash" ]]; then
    echo "Detected curl-pipe mode — cloning agent-workflow..."
    CLONED_DIR="$(mktemp -d)"
    git clone --depth=1 "$REPO_URL" "$CLONED_DIR" >/dev/null 2>&1
    SCRIPT_DIR="$CLONED_DIR"
else
    SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
fi

TEMPLATES="$SCRIPT_DIR/templates"
SKILLS_SRC="$SCRIPT_DIR/skills"
WORKFLOWS_SRC="$SCRIPT_DIR/.archon/workflows"
GOTCHAS_SRC="$SCRIPT_DIR/docs/gotchas"
SCRIPTS_SRC="$SCRIPT_DIR/scripts"

# ── Parse arguments ───────────────────────────────────────────────────────────
FORCE=false
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *) TARGET="$arg" ;;
    esac
done

TARGET="${TARGET:-.}"
TARGET="$(cd "$TARGET" && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
skip() { printf "  ${YELLOW}~${NC} %s (already exists — skipped)\n" "$1"; }
info() { printf "  %s\n" "$1"; }

copy_file() {
    local src="$1"
    local dst="$2"
    local rel="${dst#$TARGET/}"

    mkdir -p "$(dirname "$dst")"
    if [[ -e "$dst" ]] && [[ "$FORCE" != "true" ]]; then
        skip "$rel"
    else
        cp "$src" "$dst"
        ok "$rel"
    fi
}

copy_dir() {
    local src="$1"
    local dst="$2"

    find "$src" -type f | while read -r file; do
        local rel_path="${file#$src/}"
        copy_file "$file" "$dst/$rel_path"
    done
}

make_symlink() {
    local link_path="$1"
    local target="$2"
    local rel="${link_path#$TARGET/}"

    if [[ -L "$link_path" ]]; then
        skip "$rel (symlink)"
    elif [[ -e "$link_path" ]] && [[ "$FORCE" != "true" ]]; then
        skip "$rel (exists as real directory)"
    else
        mkdir -p "$(dirname "$link_path")"
        ln -sfn "$target" "$link_path"
        ok "$rel -> $target"
    fi
}

# ── Prompt for project name ───────────────────────────────────────────────────
PROJ_NAME="$(basename "$TARGET")"
printf "\nProject name [%s]: " "$PROJ_NAME"
read -r input
PROJ_NAME="${input:-$PROJ_NAME}"

# ── Install ───────────────────────────────────────────────────────────────────
printf "\nInstalling agent-workflow into: %s\n\n" "$TARGET"

# AGENTS.md — substitute {{PROJECT_NAME}}
AGENTS_DST="$TARGET/AGENTS.md"
if [[ -e "$AGENTS_DST" ]] && [[ "$FORCE" != "true" ]]; then
    skip "AGENTS.md"
else
    sed "s/{{PROJECT_NAME}}/$PROJ_NAME/g" "$TEMPLATES/AGENTS.md" > "$AGENTS_DST"
    ok "AGENTS.md"
fi

# CLAUDE.md
copy_file "$TEMPLATES/CLAUDE.md" "$TARGET/CLAUDE.md"

# Pre-commit config
copy_file "$TEMPLATES/.pre-commit-config.yaml" "$TARGET/.pre-commit-config.yaml"

# CI workflow
copy_file "$TEMPLATES/.github/workflows/ci.yml" "$TARGET/.github/workflows/ci.yml"

# check-invariants.sh
copy_file "$TEMPLATES/scripts/check-invariants.sh" "$TARGET/scripts/check-invariants.sh"
chmod +x "$TARGET/scripts/check-invariants.sh"

# Skills
printf "\n  Skills:\n"
copy_dir "$SKILLS_SRC" "$TARGET/docs/agent-rules/skills"

# Archon workflows (master-loop template)
printf "\n  Archon workflows:\n"
if [[ -d "$WORKFLOWS_SRC" ]]; then
    # Only the template — never copy the gitignored .runs/ render cache.
    if [[ -f "$WORKFLOWS_SRC/aw-master-loop.template.yaml.tmpl" ]]; then
        copy_file "$WORKFLOWS_SRC/aw-master-loop.template.yaml.tmpl" \
                  "$TARGET/.archon/workflows/aw-master-loop.template.yaml.tmpl"
    fi
fi

# Gotchas registry (template + seed INDEX)
printf "\n  Gotchas registry:\n"
if [[ -d "$GOTCHAS_SRC" ]]; then
    copy_dir "$GOTCHAS_SRC" "$TARGET/docs/gotchas"
fi

# Scripts for the master loop + gotchas index
printf "\n  Scripts:\n"
for s in aw-run aw-run-all.sh aw-run-tests.sh aw-decide.sh gotchas-index.sh; do
    if [[ -f "$SCRIPTS_SRC/$s" ]]; then
        copy_file "$SCRIPTS_SRC/$s" "$TARGET/scripts/$s"
        chmod +x "$TARGET/scripts/$s"
    fi
done

# Symlinks
printf "\n  Symlinks:\n"
make_symlink "$TARGET/.claude/skills"          "../docs/agent-rules/skills"
make_symlink "$TARGET/.opencode/commands"      "../docs/agent-rules/skills"
make_symlink "$TARGET/.pi/skills"              "../docs/agent-rules/skills"

# Pi settings (only if not present; never overwrites a user's tuning)
if [[ -f "$TEMPLATES/.pi/settings.json" ]]; then
    copy_file "$TEMPLATES/.pi/settings.json" "$TARGET/.pi/settings.json"
fi

# Pi extensions (project-local; auto-discovered by Pi from .pi/extensions/)
if [[ -d "$TEMPLATES/.pi/extensions" ]]; then
    printf "\n  Pi extensions:\n"
    mkdir -p "$TARGET/.pi/extensions"
    for _ext in "$TEMPLATES/.pi/extensions"/*.ts; do
        [[ -e "$_ext" ]] || continue
        copy_file "$_ext" "$TARGET/.pi/extensions/$(basename "$_ext")"
    done
fi

# ── Post-install instructions ─────────────────────────────────────────────────
printf "\n${GREEN}Done.${NC}\n\n"
cat <<'EOF'
Next steps:
  1. Customise AGENTS.md
       → Add your project layout under "Project layout"
       → Add your architectural invariants (see the commented examples)

  2. Add invariant checks to scripts/check-invariants.sh
       → Uncomment or copy the example check() calls
       → Document each rule in docs/agent-rules/architecture-invariants.md

  3. Uncomment the language tracks you use:
       → .pre-commit-config.yaml  (Python / TypeScript / Rust sections)
       → .github/workflows/ci.yml (python / frontend / rust jobs)

  4. Install pre-commit hooks (once, in your project):
       pre-commit install --install-hooks

  5. Write your first progress file:
       → Use /write-progress or follow docs/agent-rules/skills/write-progress/SKILL.md

  6. (Optional) Try the Archon master-loop on one small epic:
       → scripts/aw-run --dry-run <EPIC-ID>             # render only
       → scripts/aw-run <EPIC-ID>                       # run for real
     Defaults: master=claude:sonnet, coder=codex:gpt-5-codex,
               tester=claude:sonnet, max-fix=3, max-arb=3,
               autocommit ON, worktree cleanup ON.
     Requires `archon` v0.3.10+ in PATH (https://github.com/coleam00/Archon).
EOF

# ── Cleanup temp clone (curl-pipe mode) ──────────────────────────────────────
if [[ -n "$CLONED_DIR" ]]; then
    rm -rf "$CLONED_DIR"
fi
