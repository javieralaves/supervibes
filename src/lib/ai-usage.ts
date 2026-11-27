import "server-only";

import type Anthropic from "@anthropic-ai/sdk";
import { and, desc, eq, gte } from "drizzle-orm";

import { db } from "@/db";
import { aiCalls, goals } from "@/db/schema";
import { costMicros, type TokenCounts } from "@/lib/ai-pricing";

/*
 * Records what each Claude API call costs, so the Usage section in Settings can
 * show spend per feature and over time. Recording never throws: a failed write
 * is logged and the feature carries on.
 */

export type AiFeature =
  | "progress_read"
  | "area_read"
  | "recap"
  | "agenda"
  | "gap_read"
  | "stand_read"
  | "quest_suggest"
  | "season_read"
  | "quest_read"
  | "plate_sort";
export type AiTrigger = "manual" | "note" | "recap" | "cron" | "draft" | "redraft" | "auto";

/** Who and what a call is for; passed down to whatever makes the call. */
/** `goalId` is null for a call about something other than one goal (an area's read). */
export type AiCallContext = { userId: string; goalId: string | null; feature: AiFeature; trigger: AiTrigger };

/** Running totals for one logical call, which can span several API requests. */
export class CallMeter {
  private readonly started = Date.now();
  private tokens: TokenCounts = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
  private cost: number | null = 0;
  private model: string;
  private requests = 0;
  private toolCalls = 0;

  constructor(
    private readonly context: AiCallContext,
    /** The model the request asks for; usage that doesn't name one is priced as this. */
    private readonly requestedModel: string,
  ) {
    this.model = requestedModel;
  }

  /** Adds one API response's usage. */
  add(message: Anthropic.Beta.BetaMessage) {
    this.requests++;
    this.model = message.model;
    this.toolCalls += message.content.filter((b) => b.type === "mcp_tool_use").length;

    // Per-iteration usage, when the API gives it, names the model behind each part
    // (a declined request answered by a fallback model is billed at that model's rates).
    const parts = message.usage.iterations?.length
      ? message.usage.iterations.map((it) => ({ model: "model" in it && it.model ? String(it.model) : this.requestedModel, usage: it }))
      : [{ model: message.model, usage: message.usage }];
    for (const { model, usage } of parts) {
      const counts: TokenCounts = {
        input: usage.input_tokens ?? 0,
        output: usage.output_tokens ?? 0,
        cacheRead: usage.cache_read_input_tokens ?? 0,
        cacheWrite: usage.cache_creation_input_tokens ?? 0,
      };
      this.tokens.input += counts.input;
      this.tokens.output += counts.output;
      this.tokens.cacheRead += counts.cacheRead;
      this.tokens.cacheWrite += counts.cacheWrite;
      const cost = costMicros(model, counts);
      this.cost = this.cost === null || cost === null ? null : this.cost + cost;
    }
  }

  /** Writes the call. `outcome` is the last stop reason, or "error" if it threw. */
  async record(outcome: string) {
    try {
      await db.insert(aiCalls).values({
        userId: this.context.userId,
        goalId: this.context.goalId,
        feature: this.context.feature,
        trigger: this.context.trigger,
        model: this.model,
        inputTokens: this.tokens.input,
        cacheReadTokens: this.tokens.cacheRead,
        cacheWriteTokens: this.tokens.cacheWrite,
        outputTokens: this.tokens.output,
        toolCalls: this.toolCalls,
        requests: Math.max(this.requests, 1),
        durationMs: Date.now() - this.started,
        outcome,
        costMicros: this.cost,
      });
    } catch (error) {
      console.error("[ai-usage] couldn't record a call", error);
    }
  }
}

/** A recorded call as the Usage section sees it; dates are ISO strings. */
export type AiCallView = {
  id: string;
  feature: AiFeature;
  trigger: AiTrigger;
  goalTitle: string | null;
  model: string;
  /** All input tokens: uncached, cache reads and cache writes. */
  inputTokens: number;
  outputTokens: number;
  toolCalls: number;
  durationMs: number;
  outcome: string;
  /** Dollars, or null for an unpriced model. */
  cost: number | null;
  createdAt: string;
};

/** The user's calls over the last `days` days, newest first. */
export async function listRecentCalls(userId: string, days = 30): Promise<AiCallView[]> {
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const rows = await db
    .select({
      id: aiCalls.id,
      feature: aiCalls.feature,
      trigger: aiCalls.trigger,
      goalTitle: goals.title,
      model: aiCalls.model,
      inputTokens: aiCalls.inputTokens,
      cacheReadTokens: aiCalls.cacheReadTokens,
      cacheWriteTokens: aiCalls.cacheWriteTokens,
      outputTokens: aiCalls.outputTokens,
      toolCalls: aiCalls.toolCalls,
      durationMs: aiCalls.durationMs,
      outcome: aiCalls.outcome,
      costMicros: aiCalls.costMicros,
      createdAt: aiCalls.createdAt,
    })
    .from(aiCalls)
    .leftJoin(goals, eq(goals.id, aiCalls.goalId))
    .where(and(eq(aiCalls.userId, userId), gte(aiCalls.createdAt, since)))
    .orderBy(desc(aiCalls.createdAt))
    .limit(5000);
  return rows.map((r) => ({
    id: r.id,
    feature: r.feature as AiFeature,
    trigger: r.trigger as AiTrigger,
    goalTitle: r.goalTitle,
    model: r.model,
    inputTokens: r.inputTokens + r.cacheReadTokens + r.cacheWriteTokens,
    outputTokens: r.outputTokens,
    toolCalls: r.toolCalls,
    durationMs: r.durationMs,
    outcome: r.outcome,
    cost: r.costMicros === null ? null : r.costMicros / 1_000_000,
    createdAt: r.createdAt.toISOString(),
  }));
}
