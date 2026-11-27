import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, errorResponses } from "@/lib/api/errors";
import { AreaLimitError } from "@/lib/areas";
import { FirstRunError, MAX_PLATE_TEXT, savePlate, sortedAreaSchema, sortedItemSchema, sortPlate } from "@/lib/first-run";
import { GoalLimitError } from "@/lib/goals";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { todayIn } from "@/lib/target-date";

/*
 * First run's shared start (src/lib/first-run.ts): sort what someone typed into areas, projects and practices, then,
 * once they've fixed what's off, make it.
 */

const SortedItemSchema = sortedItemSchema
  .extend({
    detail: z.string().nullable().openapi({ description: "A few words they said that help place it: a deadline, who it's with." }),
    perWeek: z.int().nullable().openapi({ description: "For a practice, times a week; null when they didn't say (ask before saving)." }),
    targetDate: z.iso.date().nullable().openapi({ description: "For a project, the day they want it done by, if they said." }),
    tasks: z.array(z.string()).openapi({ description: "One-off things to do on a project, saved to Later." }),
  })
  .openapi("SortedItem");

const SortedAreaSchema = sortedAreaSchema.extend({ items: z.array(SortedItemSchema) }).openapi("SortedArea");
const SortedPlateSchema = z.object({ areas: z.array(SortedAreaSchema) }).openapi("SortedPlate");

const PlateTextSchema = z
  .object({
    text: z.string().trim().min(1, "Write a few things down first.").max(MAX_PLATE_TEXT, "That’s a lot at once. Try a shorter list."),
    timeZone: timeZoneSchema.optional().openapi({ description: "The device's time zone, for working out dates; defaults to the stored one." }),
  })
  .openapi("PlateText");

const SavedPlateSchema = z
  .object({ areas: z.int(), projects: z.int(), practices: z.int(), tasks: z.int() })
  .openapi("SavedPlate", { description: "How much was made: new areas, projects, practices and tasks." });

const json = <T extends z.ZodType>(schema: T, description = "OK") => ({ description, content: { "application/json": { schema } } });
const secured = [{ bearerAuth: [] }];

const sortRoute = createRoute({
  method: "post",
  path: "/first-run/sort",
  operationId: "sortPlate",
  summary: "Sort what someone typed into areas, projects and practices; nothing is saved; takes a few seconds",
  security: secured,
  request: { body: { content: { "application/json": { schema: PlateTextSchema } } } },
  responses: { 200: json(SortedPlateSchema), ...errorResponses },
});

const saveRoute = createRoute({
  method: "post",
  path: "/first-run/save",
  operationId: "savePlate",
  summary: "Make a sorted plate: the areas not there yet, each project and practice in its area, and the projects' tasks",
  security: secured,
  request: { body: { content: { "application/json": { schema: SortedPlateSchema } } } },
  responses: { 201: json(SavedPlateSchema, "Made"), ...errorResponses },
});

function failure(error: unknown) {
  if (error instanceof FirstRunError) return apiError("first_run", error.message);
  if (error instanceof GoalLimitError || error instanceof AreaLimitError) return apiError("limit", error.message);
  throw error;
}

export const firstRun = new OpenAPIHono<ApiEnv>()
  .openapi(sortRoute, async (c) => {
    const userId = c.var.user.id;
    const { text, timeZone } = c.req.valid("json");
    try {
      const today = todayIn(timeZone ?? (await getTimeZone(userId)));
      return c.json(await sortPlate(userId, text, today), 200);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  })
  .openapi(saveRoute, async (c) => {
    try {
      return c.json(await savePlate(c.var.user.id, c.req.valid("json")), 201);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  });
