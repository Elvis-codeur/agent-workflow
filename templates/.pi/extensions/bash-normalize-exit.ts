/**
 * bash-normalize-exit — agent-workflow built-in Pi extension
 *
 * Pi's bash tool reports ANY non-zero exit code as "⚠️ Tool bash failed".
 * This trips up perfectly normal grep/find/ls commands that return exit 1
 * to signal "no results found" — which is NOT an error.
 *
 * POSIX exit-code contract:
 *   grep  — 0 = match found  | 1 = no match (normal) | 2 = real error
 *   find  — 0 = ok (even if nothing found) | 1 = traversal error
 *   ls    — 0 = ok | 1-2 = not found / error
 *
 * This extension intercepts bash tool calls whose primary command is
 * grep, find, or ls (optionally after a `cd ... && ` preamble) and wraps
 * the command so that exit code 1 is normalized to 0.
 * Exit codes ≥ 2 (bad regex, permission denied, etc.) are always preserved.
 *
 * Placement:
 *   .pi/extensions/bash-normalize-exit.ts   ← project-local (auto-discovered)
 *   ~/.pi/agent/extensions/                  ← global fallback
 *
 * No configuration needed — just drop the file and Pi picks it up.
 * Hot-reload while Pi is running: /reload
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI): void {
  pi.on("tool_call", async (event) => {
    if (!isToolCallEventType("bash", event)) return;

    const cmd: string = event.input.command ?? "";
    if (!isSearchCommand(cmd)) return;

    // Wrap the command in a subshell; map exit 0-1 → 0, exit 2+ → error.
    // The original stdout/stderr is still forwarded to the agent, so it
    // can still read "no such file" or "0 matches" from the output —
    // only the exit code is normalised, nothing is hidden.
    event.input.command = [
      `( ${cmd}`,
      ")",
      "__aw_rc=$?",
      `[ "$__aw_rc" -le 1 ] && exit 0 || exit "$__aw_rc"`,
    ].join("\n");
  });
}

/**
 * Returns true when the primary executable of the command is grep, find,
 * or ls — possibly preceded by an optional `cd /some/path && ` preamble.
 *
 * Explicitly excluded (left untouched so real failures surface):
 *   - Multi-step scripts:  cd /repo && uv run pytest
 *   - Pipelines into tools: cat file | grep pattern | wc -l  ← wc exits 0
 *   - Compound scripts with newlines / heredocs
 */
function isSearchCommand(cmd: string): boolean {
  // Normalise: collapse leading whitespace, drop optional `cd ... && `
  const stripped = cmd
    .trim()
    .replace(/^cd\s+\S[^&\n]*&&\s*/, "")
    .trimStart();

  return /^(grep|find|ls)(\s|$)/.test(stripped);
}
