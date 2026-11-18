import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { errorResponses } from "@/lib/api/errors";
import { getSettings, getTimeZone } from "@/lib/settings";
import { CLOCKS } from "@/lib/settings-schema";

const MeSchema = z
  .object({
    user: z.object({
      id: z.string(),
      email: z.string(),
      name: z.string(),
      image: z.string().nullable(),
    }),
    settings: z.object({
      sleepStart: z.int().openapi({ description: "Bedtime, minutes after local midnight." }),
      wakeTime: z.int().openapi({ description: "Wake-up time, minutes after local midnight." }),
      clock: z.enum(CLOCKS).nullable().openapi({ description: "null follows the device." }),
      timeZone: z.string().nullable().openapi({ description: "As the web app last reported it." }),
    }),
  })
  .openapi("Me");

const getMe = createRoute({
  method: "get",
  path: "/me",
  operationId: "getMe",
  summary: "The signed-in person and their settings",
  security: [{ bearerAuth: [] }],
  responses: {
    200: { description: "OK", content: { "application/json": { schema: MeSchema } } },
    401: errorResponses[401],
  },
});

export const me = new OpenAPIHono<ApiEnv>().openapi(getMe, async (c) => {
  const user = c.var.user;
  const [settings, timeZone] = await Promise.all([getSettings(user.id), getTimeZone(user.id)]);
  return c.json(
    {
      user: { id: user.id, email: user.email, name: user.name, image: user.image ?? null },
      settings: { ...settings, timeZone },
    },
    200,
  );
});
