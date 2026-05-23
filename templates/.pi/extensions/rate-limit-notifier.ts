/**
 * rate-limit-notifier — agent-workflow Pi extension
 *
 * Detects API throttling in real-time and surfaces it clearly instead of
 * letting the session appear "stuck" for minutes or hours.
 *
 * Catches three signals:
 *   1. HTTP 429 responses (with retry-after / ratelimit-reset headers)
 *   2. Model-generated error messages about rate limits / quota exhaustion
 *   3. Archon's claude.rate_limit_event forwarded as a provider warning
 *
 * Placement:
 *   .pi/extensions/rate-limit-notifier.ts   ← project-local (auto-discovered)
 *   ~/.pi/agent/extensions/                 ← global fallback
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const RATE_LIMIT_PATTERNS: RegExp[] = [
  /rate[\s._-]?limit/i,
  /quota[\s._-]?exceed/i,
  /token[\s._-]?limit/i,
  /out[\s._-]?of[\s._-]?credits/i,
  /monthly[\s._-]?limit/i,
  /weekly[\s._-]?limit/i,
  /usage[\s._-]?limit/i,
  /too[\s._-]?many[\s._-]?requests/i,
  /overloaded/i,
  /capacity/i,
];

// Known limit type descriptions (from Archon's claude.rate_limit_event)
const LIMIT_DESCRIPTIONS: Record<string, string> = {
  five_hour: "5-hour window",
  daily: "daily limit",
  weekly: "weekly limit",
  monthly: "monthly limit",
};

const FALLBACK_MODELS = [
  "pi:github-copilot/gpt-5.3-codex",
  "pi:github-copilot/gemini-3-flash-preview",
  "pi:github-copilot/gpt-5.2",
];

export default function (pi: ExtensionAPI): void {
  let hitCount = 0;
  let firstResetAt: number | null = null;

  // ── Signal 1: HTTP-level rate limit (429) ─────────────────────────────────
  pi.on("after_provider_response", (event, ctx) => {
    if (event.status !== 429) return;

    hitCount++;
    const retryAfter =
      event.headers["retry-after"] ??
      event.headers["x-ratelimit-reset"] ??
      event.headers["ratelimit-reset"] ??
      event.headers["anthropic-ratelimit-tokens-reset"] ??
      null;

    const resetStr = retryAfter ? ` — resets ${formatReset(retryAfter)}` : "";
    const msg = `⛔ HTTP 429 rate limited${resetStr}`;
    ctx.ui.notify(msg, "error");
    ctx.ui.setStatus("rate-limit", msg);

    if (retryAfter) {
      const ts = parseResetTimestamp(retryAfter);
      if (ts && (!firstResetAt || ts < firstResetAt)) firstResetAt = ts;
    }

    console.error(
      `\n${"=".repeat(60)}\n` +
        `⛔  RATE LIMITED (HTTP 429)${resetStr}\n` +
        `    Switch model: ${FALLBACK_MODELS.join(", ")}\n` +
        `${"=".repeat(60)}\n`,
    );
  });

  // ── Signal 2: Model-reported quota / throttle messages ───────────────────
  pi.on("message_end", async (event, ctx) => {
    if (event.message.role !== "assistant") return;

    const blocks = (event.message.content ?? []) as Array<{
      type: string;
      text?: string;
    }>;
    const text = blocks
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join(" ");

    if (!RATE_LIMIT_PATTERNS.some((p) => p.test(text))) return;

    hitCount++;
    const msg = "⛔ Model reported a rate limit / quota issue";
    ctx.ui.notify(msg, "error");
    ctx.ui.setStatus("rate-limit", msg);
  });

  // ── Signal 3: Archon-forwarded provider warning (claude.rate_limit_event) ─
  // Archon forwards provider warnings as system content with the
  // dag.provider_warning_forwarded log event. Pi surfaces these as a
  // special message type we can intercept via message_end on system messages.
  // We also parse the raw text for structured rate limit info.
  pi.on("message_end", async (event, ctx) => {
    if (event.message.role !== "system") return;

    const blocks = (event.message.content ?? []) as Array<{
      type: string;
      text?: string;
    }>;
    const text = blocks
      .filter((b) => b.type === "text")
      .map((b) => b.text ?? "")
      .join(" ");

    // Parse Archon's structured rate limit JSON forwarded as a warning
    try {
      const m = text.match(/"rateLimitInfo"\s*:\s*(\{[^}]+\})/);
      if (m) {
        const info = JSON.parse(m[1]) as {
          rateLimitType?: string;
          resetsAt?: number;
          overageStatus?: string;
          overageDisabledReason?: string;
        };
        hitCount++;
        const limitDesc =
          LIMIT_DESCRIPTIONS[info.rateLimitType ?? ""] ?? info.rateLimitType ?? "unknown";
        const resetStr = info.resetsAt ? ` — resets ${formatReset(String(info.resetsAt))}` : "";
        const reason = info.overageDisabledReason ? ` (${info.overageDisabledReason})` : "";
        const msg = `⛔ Rate limit: ${limitDesc}${reason}${resetStr}`;

        ctx.ui.notify(msg, "error");
        ctx.ui.setStatus("rate-limit", msg);

        if (info.resetsAt && (!firstResetAt || info.resetsAt < firstResetAt)) {
          firstResetAt = info.resetsAt;
        }

        console.error(
          `\n${"=".repeat(60)}\n` +
            `⛔  RATE LIMIT DETECTED\n` +
            `    Type:    ${limitDesc}\n` +
            (info.overageDisabledReason ? `    Reason:  ${info.overageDisabledReason}\n` : "") +
            (info.resetsAt
              ? `    Resets:  ${new Date(info.resetsAt * 1000).toLocaleString()}\n`
              : "") +
            `    Switch:  ${FALLBACK_MODELS.join("\n             ")}\n` +
            `${"=".repeat(60)}\n`,
        );
      }
    } catch {
      // not structured JSON — fall through
    }
  });

  // ── Session summary ────────────────────────────────────────────────────────
  pi.on("agent_end", async (_event, ctx) => {
    if (hitCount === 0) return;

    const resetStr = firstResetAt
      ? `\n    Earliest reset: ${new Date(firstResetAt * 1000).toLocaleString()}`
      : "";
    const msg =
      `⛔ ${hitCount} rate limit event(s) this session.${resetStr}\n` +
      `    Try a different model: ${FALLBACK_MODELS[0]}`;

    ctx.ui.notify(msg, "error");
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function parseResetTimestamp(raw: string): number | null {
  const n = Number(raw);
  if (isNaN(n)) return null;
  // If it looks like a Unix timestamp (> year 2020)
  if (n > 1_580_000_000) return n;
  // If it looks like "seconds to wait"
  return Math.floor(Date.now() / 1000) + n;
}

function formatReset(raw: string): string {
  const ts = parseResetTimestamp(raw);
  if (!ts) return raw;

  const d = new Date(ts * 1000);
  const minsFromNow = Math.ceil((ts * 1000 - Date.now()) / 60000);

  if (minsFromNow <= 0) return "now";
  if (minsFromNow < 60) return `at ${d.toLocaleTimeString()} (in ${minsFromNow} min)`;
  if (minsFromNow < 24 * 60)
    return `at ${d.toLocaleTimeString()} (in ${Math.round(minsFromNow / 60)}h)`;
  return `on ${d.toLocaleDateString()} ${d.toLocaleTimeString()}`;
}
