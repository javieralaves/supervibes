import "server-only";

import Anthropic from "@anthropic-ai/sdk";
import { and, eq, inArray } from "drizzle-orm";

import { db } from "@/db";
import { goalSources } from "@/db/schema";
import { CallMeter, type AiCallContext } from "@/lib/ai-usage";
import { getUsableConnection, markConnectionError } from "@/lib/connections";
import { PROVIDERS, type ProviderKey } from "@/lib/providers";

/*
 * Reading a goal's connected apps with Claude, shared by progress reads and
 * session recaps. Each app is a remote MCP server; only its read-only tools
 * can be called.
 */

const MODEL = "claude-sonnet-5-5";

export type GoalSource = { id: string; connectionId: string; relation: string };
type Server = { provider: ProviderKey; serverUrl: string; token: string; readTools: string[] };

export type GoalApps = {
  /** All of the goal's enabled sources. */
  sources: GoalSource[];
  /** The ones whose app could be reached. */
  usable: GoalSource[];
  /** One MCP server per connected app, keyed by connection id. */
  servers: Map<string, Server>;
};

/**
 * Connects to the apps behind a goal's enabled sources. Sources whose app
 * can't be reached are left out and flagged on the source.
 */
export async function openGoalApps(userId: string, goalId: string): Promise<GoalApps> {
  const sources = await db
    .select({ id: goalSources.id, connectionId: goalSources.connectionId, relation: goalSources.relation })
    .from(goalSources)
    .where(and(eq(goalSources.goalId, goalId), eq(goalSources.userId, userId), eq(goalSources.enabled, true)));

  const servers = new Map<string, Server>();
  const usable: GoalSource[] = [];
  for (const source of sources) {
    let connection = null;
    try {
      connection = await getUsableConnection(userId, source.connectionId);
    } catch {
      await markConnectionError(userId, source.connectionId, "Sign-in expired. Reconnect it.");
    }
    if (!connection || connection.readTools.length === 0) {
      await db
        .update(goalSources)
        .set({ lastError: `Couldn't reach this app. Reconnect it on the Connections page.` })
        .where(eq(goalSources.id, source.id));
      continue;
    }
    servers.set(connection.id, {
      provider: connection.provider,
      serverUrl: connection.serverUrl,
      token: connection.accessToken,
      readTools: readingTools(connection.provider, connection.readTools),
    });
    usable.push(source);
  }
  return { sources, usable, servers };
}

/**
 * The app's read-only tools that reads and recaps use (see PROVIDERS). If the app
 * has renamed them all, falls back to every read-only tool rather than none.
 */
function readingTools(provider: ProviderKey, readTools: string[]): string[] {
  const wanted = new Set<string>(PROVIDERS[provider].readingTools);
  const kept = readTools.filter((name) => wanted.has(name));
  if (kept.length === 0) {
    console.warn(`[goal-apps] none of ${provider}'s reading tools are offered; using all ${readTools.length} read-only tools`);
    return readTools;
  }
  if (kept.length < wanted.size) {
    const missing = [...wanted].filter((name) => !readTools.includes(name));
    console.warn(`[goal-apps] ${provider} no longer offers: ${missing.join(", ")}`);
  }
  return kept;
}

function serverName(apps: GoalApps, connectionId: string) {
  return `${apps.servers.get(connectionId)!.provider}-${connectionId.slice(0, 8)}`;
}

/** Numbered prompt lines: each reachable source, the app it's in, and the person's description of it. */
export function sourceLines(apps: GoalApps): string[] {
  return apps.usable.map((s, i) => {
    const server = apps.servers.get(s.connectionId)!;
    return `${i + 1}. ${PROVIDERS[server.provider].label} (tools from "${serverName(apps, s.connectionId)}"): ${s.relation}`;
  });
}

/** Provider keys of the apps that could be reached, e.g. ["linear", "github"]. */
export function reachedProviders(apps: GoalApps): ProviderKey[] {
  return [...new Set([...apps.servers.values()].map((s) => s.provider))];
}

/** Clears the error flag on the sources that were just read. */
export async function clearSourceErrors(apps: GoalApps) {
  if (apps.usable.length === 0) return;
  await db
    .update(goalSources)
    .set({ lastError: null })
    .where(inArray(goalSources.id, apps.usable.map((s) => s.id)));
}

/**
 * One structured answer from Claude, with the goal's apps available as tools.
 * Returns the final message and the text of every tool result, so callers can
 * check that links in the answer really came from an app.
 */
export async function askWithApps(
  apps: GoalApps,
  options: {
    system: string;
    prompt: string;
    schema: Record<string, unknown>;
    effort: "low" | "medium" | "high";
    maxTokens: number;
    /** Who and what it's for, to record its tokens and cost. */
    context: AiCallContext;
  },
): Promise<{ message: Anthropic.Beta.BetaMessage; toolText: string }> {
  const ids = [...apps.servers.keys()];
  const mcpServers = ids.map((id) => ({
    type: "url" as const,
    url: apps.servers.get(id)!.serverUrl,
    name: serverName(apps, id),
    authorization_token: apps.servers.get(id)!.token,
  }));
  const toolsets = ids.map((id) => ({
    type: "mcp_toolset" as const,
    mcp_server_name: serverName(apps, id),
    // Allowlist mode: only the server's read-only tools can be called.
    default_config: { enabled: false },
    configs: Object.fromEntries(apps.servers.get(id)!.readTools.map((name) => [name, { enabled: true }])),
  }));

  const hasServers = mcpServers.length > 0;
  const client = new Anthropic();
  const messages: Anthropic.Beta.BetaMessageParam[] = [{ role: "user", content: options.prompt }];
  const toolText: string[] = [];
  const meter = new CallMeter(options.context, MODEL);
  let message: Anthropic.Beta.BetaMessage | undefined;
  let outcome = "error";
  try {
    // The API may pause a long server-side tool loop; resume it a few times.
    for (let turn = 0; turn < 4; turn++) {
      message = await client.beta.messages
        .stream({
          model: MODEL,
          max_tokens: options.maxTokens,
          betas: [...(hasServers ? (["mcp-client-2025-11-20"] as const) : []), "server-side-fallback-2026-07-01"],
          fallbacks: "default",
          // Two cache points (5-minute TTL). The one on the system prompt covers the app tool
          // definitions and instructions, which repeat across calls with the same apps (a recap
          // drafted again, a read soon after another). The automatic one moves to the end of
          // the request as the tool loop grows, so each step after the first reads everything
          // before it from cache instead of paying full price for it again.
          system: [{ type: "text", text: options.system, cache_control: { type: "ephemeral" } }],
          cache_control: { type: "ephemeral" },
          output_config: { effort: options.effort, format: { type: "json_schema", schema: options.schema } },
          ...(hasServers ? { mcp_servers: mcpServers, tools: toolsets } : {}),
          messages,
        })
        .finalMessage();
      meter.add(message);
      outcome = message.stop_reason ?? "unknown";
      for (const block of message.content) {
        if (block.type !== "mcp_tool_result") continue;
        toolText.push(typeof block.content === "string" ? block.content : block.content.map((c) => c.text).join("\n"));
      }
      if (message.stop_reason !== "pause_turn") break;
      messages.push({ role: "assistant", content: message.content });
    }
  } finally {
    // Recorded even when a request throws partway, so failed calls still show their cost.
    await meter.record(outcome);
  }
  return { message: message!, toolText: toolText.join("\n") };
}

/** The last text block of a message, which holds the structured answer. */
export function answerText(message: Anthropic.Beta.BetaMessage): string | null {
  const text = message.content.findLast((b) => b.type === "text");
  return text && text.type === "text" ? text.text : null;
}
