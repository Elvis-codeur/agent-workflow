#!/usr/bin/env bash
# Architectural-invariant checks. Run by CI on every PR and locally via
# `./scripts/check-invariants.sh`.
#
# Each check is a coarse grep. The full rationale for each rule lives in:
#     docs/agent-rules/architecture-invariants.md
#
# Adding a new invariant:
#   1. Document it in architecture-invariants.md first.
#   2. Add a `check` call below.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

violations=0

# check NAME DESCRIPTION COMMAND...
#   COMMAND succeeds (exit 0) when it FINDS a violation.
#   We invert: success of the grep = failure of the invariant.
check() {
    local name="$1"; shift
    local description="$1"; shift

    if output=$("$@" 2>/dev/null); then
        printf "  ✗ %-32s %s\n" "$name" "$description"
        echo "$output" | sed 's/^/      /'
        violations=$((violations + 1))
    else
        printf "  ✓ %-32s\n" "$name"
    fi
}

printf "Architectural invariants:\n\n"

# ── Add your invariant checks below ───────────────────────────────────────────
#
# Example — block a deprecated import:
#
# check "no-old-client" \
#     "Use NewClient, not DeprecatedClient" \
#     grep -rEn \
#         --include='*.ts' --include='*.tsx' \
#         'DeprecatedClient' \
#         src
#
# Example — prevent synchronous calls in async context:
#
# check "no-sync-fetch" \
#     "Use async fetch(), not syncFetch()" \
#     grep -rEn \
#         --include='*.ts' \
#         'syncFetch\(' \
#         src
#
# Example — block hook bypass in scripts and CI:
#
# check "no-hook-bypass" \
#     "scripts/ and workflows/ must not bypass hooks" \
#     grep -rEn \
#         --include='*.sh' --include='*.yml' --include='*.yaml' \
#         --exclude='check-invariants.sh' \
#         '(--no-verify|--no-gpg-sign|SKIP=|HUSKY=0)' \
#         scripts .github/workflows
#
# ─────────────────────────────────────────────────────────────────────────────

printf "\n"
if [ "$violations" -gt 0 ]; then
    printf "✗ %d invariant(s) violated. See docs/agent-rules/architecture-invariants.md\n" "$violations"
    exit 1
fi

printf "✓ All architectural invariants pass.\n"
