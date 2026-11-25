import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { errorResponses } from "@/lib/api/errors";
import { listRecentCalls } from "@/lib/ai-usage";

const DAYS = 30;

const UsageCallSchema = z
  .object({
    id: z.string(),
    feature: z.enum(["progress_read", "area_read", "recap", "agenda"]),
    trigger: z.enum(["manual", "note", "recap", "cron", "draft", "redraft", "auto"]),
    goalTitle: z.string().nullable(),
    model: z.string(),
    inputTokens: z.int().openapi({ description: "All input tokens: uncached, cache reads and cache writes." }),
    outputTokens: z.int(),
    toolCalls: z.int(),
    durationMs: z.int(),
    outcome: z.string(),
    cost: z.number().nullable().openapi({ description: "Dollars, or null for a model without a known price." }),
    createdAt: z.iso.datetime(),
  })
  .openapi("UsageCall");

const UsageSchema = z
  .object({
    days: z.int().openapi({ description: "How many days back `calls` goes." }),
    calls: z.array(UsageCallSchema).openapi({ description: "Newest first. Days are the viewer's to work out." }),
  })
  .openapi("Usage");

const getUsage = createRoute({
  method: "get",
  path: "/usage",
  operationId: "getUsage",
  summary: "What calls to Claude cost over the last 30 days",
  security: [{ bearerAuth: [] }],
  responses: {
    200: { description: "OK", content: { "application/json": { schema: UsageSchema } } },
    401: errorResponses[401],
  },
});

export const usage = new OpenAPIHono<ApiEnv>().openapi(getUsage, async (c) => {
  const calls = await listRecentCalls(c.var.user.id, DAYS);
  return c.json({ days: DAYS, calls }, 200);
});
