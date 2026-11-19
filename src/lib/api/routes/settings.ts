import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, errorResponses } from "@/lib/api/errors";
import { saveSettings } from "@/lib/settings";
import { CLOCKS, settingsSchema } from "@/lib/settings-schema";

export const SettingsSchema = z
  .object({
    sleepStart: z.int().openapi({ description: "Bedtime, minutes after local midnight, on the quarter hour." }),
    wakeTime: z.int().openapi({ description: "Wake-up time, minutes after local midnight, on the quarter hour." }),
    // Left out means null: the Mac app's client leaves out a nil clock.
    clock: z.enum(CLOCKS).nullable().optional().openapi({ description: "Null or left out follows the device." }),
  })
  .openapi("Settings");

const putSettings = createRoute({
  method: "put",
  path: "/settings",
  operationId: "putSettings",
  summary: "Save the sleep schedule and clock",
  security: [{ bearerAuth: [] }],
  request: {
    body: { required: true, content: { "application/json": { schema: SettingsSchema } } },
  },
  responses: {
    200: { description: "Saved", content: { "application/json": { schema: SettingsSchema } } },
    ...errorResponses,
  },
});

export const settings = new OpenAPIHono<ApiEnv>().openapi(putSettings, async (c) => {
  // The shape is checked against SettingsSchema; the rules (quarter hours, bedtime ≠ wake-up) are the web app's.
  const body = c.req.valid("json");
  const parsed = settingsSchema.safeParse({ ...body, clock: body.clock ?? null });
  if (!parsed.success) {
    return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check your settings."), 400);
  }
  await saveSettings(c.var.user.id, parsed.data);
  return c.json(parsed.data, 200);
});
