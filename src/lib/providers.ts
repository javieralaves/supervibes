/**
 * Apps Supervibes can read context from, via their hosted MCP servers.
 * Client-safe: no secrets here.
 *
 * `readingTools` is what progress reads and recaps may call in each app: the
 * read-only tools that show activity. Every tool offered is sent with every
 * request as a schema, so each one costs input tokens whether it's used or not;
 * the apps' admin, settings and lookup tools are left out on purpose.
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
    readingTools: [
      "list_issues",
      "get_issue",
      "list_comments",
      "list_projects",
      "get_project",
      "list_milestones",
      "get_milestone",
      "list_cycles",
      "list_documents",
      "get_document",
      "get_status_updates",
      "list_teams",
    ],
  },
  github: {
    label: "GitHub",
    description: "Commits, pull requests and issues.",
    /** GitHub's read-only MCP endpoint: write tools aren't even offered. */
    serverUrl: "https://api.githubcopilot.com/mcp/readonly",
    oauthScope: undefined,
    /** GitHub has no dynamic registration; uses a GitHub App with read-only permissions. */
    registration: "static",
    clientEnv: { id: "GITHUB_CLIENT_ID", secret: "GITHUB_CLIENT_SECRET" },
    relationHint:
      "e.g. The javieralaves/supervibes repo. Merged PRs are progress; open PRs show what I’m in the middle of.",
    readingTools: [
      "list_commits",
      "get_commit",
      "search_commits",
      "list_pull_requests",
      "pull_request_read",
      "search_pull_requests",
      "list_issues",
      "issue_read",
      "list_releases",
    ],
  },
  granola: {
    label: "Granola",
    description: "Meeting notes and summaries.",
    serverUrl: "https://mcp.granola.ai/mcp",
    oauthScope: "mcp",
    registration: "dynamic",
    relationHint:
      "e.g. Meetings with Pablo about design. Decisions made there shape the direction; skip routine check-ins.",
    readingTools: [
      "list_meetings",
      "search_meetings",
      "get_meetings",
      "get_meeting_transcript",
      "search_transcripts",
      "list_meeting_folders",
    ],
  },
  slack: {
    label: "Slack",
    description: "Messages, threads and canvases.",
    serverUrl: "https://mcp.slack.com/mcp",
    /**
     * Read-only user scopes for channels the person can see. No DM scopes (im:*, mpim:*) and
     * nothing that writes: Slack only offers the tools these scopes allow.
     */
    oauthScope: "search:read.public search:read.private channels:history groups:history users:read canvases:read",
    /**
     * Slack has no dynamic registration: a Slack app with "Enable Slack MCP Server" switched on
     * (its Agents settings). Slack only lets internal or Marketplace apps use MCP, so an internal
     * app works in its own workspace only.
     */
    registration: "static",
    clientEnv: { id: "SLACK_CLIENT_ID", secret: "SLACK_CLIENT_SECRET" },
    relationHint:
      "e.g. #supervibes-design and threads with Pablo. Decisions made there shape the direction; skip day-to-day chatter.",
    readingTools: [
      "slack_search_public_and_private",
      "slack_search_public",
      "slack_search_channels",
      "slack_read_channel",
      "slack_read_thread",
      "slack_read_canvas",
    ],
  },
} as const;

export type ProviderKey = keyof typeof PROVIDERS;

export const PROVIDER_KEYS = Object.keys(PROVIDERS) as [ProviderKey, ...ProviderKey[]];

export function isProvider(value: string): value is ProviderKey {
  return value in PROVIDERS;
}
