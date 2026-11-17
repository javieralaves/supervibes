/**
 * Apps Supervibes can read context from, via their hosted MCP servers.
 * Client-safe: no secrets here.
 */
export const PROVIDERS = {
  linear: {
    label: "Linear",
    description: "Issues, projects and cycles.",
    serverUrl: "https://mcp.linear.app/mcp",
    /** Linear offers "read write"; ask for read only. */
    oauthScope: "read",
    registration: "dynamic",
    relationHint:
      "e.g. The Supervibes project. Shipped issues are direct progress; feedback from user calls shapes where it’s going. Ignore routine bug triage.",
  },
  github: {
    label: "GitHub",
    description: "Commits, pull requests and issues.",
    /** GitHub's read-only MCP endpoint: write tools aren't even offered. */
    serverUrl: "https://api.githubcopilot.com/mcp/readonly",
    oauthScope: undefined,
    /** GitHub has no dynamic registration; uses a GitHub App with read-only permissions. */
    registration: "static",
    relationHint:
      "e.g. The javieralaves/supervibes repo. Merged PRs are progress; open PRs show what I’m in the middle of.",
  },
  granola: {
    label: "Granola",
    description: "Meeting notes and summaries.",
    serverUrl: "https://mcp.granola.ai/mcp",
    oauthScope: "mcp",
    registration: "dynamic",
    relationHint:
      "e.g. Meetings with Pablo about design. Decisions made there shape the direction; skip routine check-ins.",
  },
} as const;

export type ProviderKey = keyof typeof PROVIDERS;

export const PROVIDER_KEYS = Object.keys(PROVIDERS) as [ProviderKey, ...ProviderKey[]];

/** A provider key from a stored key or, for older rows, its label ("Linear"). */
export function toProvider(value: string): ProviderKey | null {
  if (isProvider(value)) return value;
  return PROVIDER_KEYS.find((key) => PROVIDERS[key].label === value) ?? null;
}

export function isProvider(value: string): value is ProviderKey {
  return value in PROVIDERS;
}
