import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { errorResponses } from "@/lib/api/errors";
import { listBlocks } from "@/lib/blocks";
import { GOAL_COLORS, isGoalColor, DEFAULT_GOAL_COLOR } from "@/lib/goal-colors";
import { listGoals } from "@/lib/goals";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { todayIn } from "@/lib/target-date";
import { dayBoundsIn } from "@/lib/zoned-day";

const GoalColorSchema = z
  .object({
    key: z.string().openapi({ example: "violet" }),
    light: z.string().openapi({ description: "Hex for light mode.", example: "#8b3df0" }),
    dark: z.string().openapi({ description: "Hex for dark mode.", example: "#b88bff" }),
  })
  .openapi("GoalColor");

const TodayBlockSchema = z
  .object({
    id: z.string(),
    kind: z.enum(["intention", "protected"]).openapi({
      description: "An intention schedules a task; protected time is held for the goal.",
    }),
    title: z.string().nullable().openapi({ description: "null for protected time without a name; show the goal's title." }),
    description: z.string().nullable().openapi({ description: "For protected time: what the session is for." }),
    startsAt: z.iso.datetime(),
    endsAt: z.iso.datetime(),
    taskId: z.string().nullable(),
    taskDone: z.boolean(),
    hasAgenda: z.boolean(),
    goal: z.object({
      id: z.string(),
      title: z.string(),
      color: GoalColorSchema,
    }),
  })
  .openapi("TodayBlock");

const TodaySchema = z
  .object({
    day: z.iso.date().openapi({ description: "The calendar day, in `timeZone`." }),
    timeZone: z.string(),
    blocks: z.array(TodayBlockSchema).openapi({ description: "Every block that overlaps the day, earliest first." }),
  })
  .openapi("Today");

const getToday = createRoute({
  method: "get",
  path: "/today",
  operationId: "getToday",
  summary: "Today's blocks, for the menu bar, widgets and notifications",
  security: [{ bearerAuth: [] }],
  request: {
    query: z.object({
      timeZone: timeZoneSchema.optional().openapi({
        description: "The device's time zone. Defaults to the one the web app last reported, then UTC.",
        example: "Europe/Madrid",
      }),
    }),
  },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: TodaySchema } } },
    ...errorResponses,
  },
});

export const today = new OpenAPIHono<ApiEnv>().openapi(getToday, async (c) => {
  const userId = c.var.user.id;
  const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId)) ?? "UTC";
  const day = todayIn(timeZone);
  const { start, end } = dayBoundsIn(day, timeZone);

  const [blocks, goals] = await Promise.all([listBlocks(userId, start, end), listGoals(userId)]);
  const goalsById = new Map(goals.map((goal) => [goal.id, goal]));

  return c.json(
    {
      day,
      timeZone,
      blocks: blocks.flatMap((block) => {
        const goal = goalsById.get(block.goalId);
        if (!goal) return [];
        const key = isGoalColor(goal.color) ? goal.color : DEFAULT_GOAL_COLOR;
        return [
          {
            id: block.id,
            kind: block.taskId ? ("intention" as const) : ("protected" as const),
            title: block.title,
            description: block.description,
            startsAt: block.startsAt.toISOString(),
            endsAt: block.endsAt.toISOString(),
            taskId: block.taskId,
            taskDone: block.taskDone ?? false,
            hasAgenda: block.agenda !== null,
            goal: {
              id: goal.id,
              title: goal.title,
              color: { key, light: GOAL_COLORS[key].light, dark: GOAL_COLORS[key].dark },
            },
          },
        ];
      }),
    },
    200,
  );
});
