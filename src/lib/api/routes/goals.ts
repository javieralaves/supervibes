import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, errorResponses } from "@/lib/api/errors";
import { GOAL_COLOR_KEYS } from "@/lib/goal-colors";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";
import { goalInputSchema, MAX_GOALS } from "@/lib/goal-schema";
import { listTrajectories } from "@/lib/goal-statuses";
import { createGoal, GoalLimitError, listGoals, type GoalDTO } from "@/lib/goals";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { buildTrajectory, STATUS_BASES, STATUSES } from "@/lib/status-schema";
import { todayIn } from "@/lib/target-date";

const TrajectoryDaySchema = z
  .object({
    day: z.iso.date(),
    status: z.enum(STATUSES).nullable(),
    basis: z.enum(STATUS_BASES).nullable(),
    reason: z.string().nullable(),
    carried: z.boolean().openapi({ description: "No read that day: the status is the one before it." }),
  })
  .openapi("TrajectoryDay");

const GoalSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    description: z.string().nullable(),
    targetDate: z.iso.date().nullable(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts, e.g. Rocket01Icon." }),
    color: z.string().openapi({ description: "A key from lib/goal-colors.ts, e.g. violet." }),
    trajectory: z.array(TrajectoryDaySchema).openapi({ description: "The last 28 days, oldest first." }),
  })
  .openapi("Goal");

const GoalsSchema = z
  .object({
    today: z.iso.date().openapi({ description: "Today in `timeZone`; the trajectories end on it." }),
    max: z.int().openapi({ description: "How many goals someone can have." }),
    goals: z.array(GoalSchema),
  })
  .openapi("Goals");

const GoalInputSchema = z
  .object({
    title: z.string(),
    description: z.string().nullable(),
    targetDate: z.string().nullable().openapi({ description: "YYYY-MM-DD, or null." }),
    icon: z.enum(GOAL_ICON_NAMES),
    color: z.enum(GOAL_COLOR_KEYS),
  })
  .openapi("GoalInput");

const listRoute = createRoute({
  method: "get",
  path: "/goals",
  operationId: "listGoals",
  summary: "Goals in order, each with its status over the last four weeks",
  security: [{ bearerAuth: [] }],
  request: {
    query: z.object({
      timeZone: timeZoneSchema.optional().openapi({ description: "The device's time zone; defaults to the stored one." }),
    }),
  },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: GoalsSchema } } },
    ...errorResponses,
  },
});

const createRoute_ = createRoute({
  method: "post",
  path: "/goals",
  operationId: "createGoal",
  summary: "Add a goal",
  security: [{ bearerAuth: [] }],
  request: { body: { required: true, content: { "application/json": { schema: GoalInputSchema } } } },
  responses: {
    201: { description: "Created", content: { "application/json": { schema: GoalSchema } } },
    ...errorResponses,
  },
});

const asGoal = (goal: GoalDTO, trajectory: z.infer<typeof TrajectoryDaySchema>[]) => ({
  id: goal.id,
  title: goal.title,
  description: goal.description,
  targetDate: goal.targetDate,
  icon: goal.icon,
  color: goal.color,
  trajectory,
});

export const goals = new OpenAPIHono<ApiEnv>()
  .openapi(listRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const list = await listGoals(userId);
    const trajectories = await listTrajectories(userId, list.map((goal) => goal.id), timeZone);
    const today = todayIn(timeZone);
    return c.json(
      {
        today,
        max: MAX_GOALS,
        goals: list.map((goal) => asGoal(goal, trajectories.get(goal.id)?.days ?? buildTrajectory([], null, today))),
      },
      200,
    );
  })
  .openapi(createRoute_, async (c) => {
    // Same rules and messages as the web's dialog (lib/goal-schema.ts).
    const parsed = goalInputSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) {
      return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the form."), 400);
    }
    try {
      const goal = await createGoal(c.var.user.id, parsed.data);
      return c.json(asGoal(goal, buildTrajectory([], null, todayIn(await getTimeZone(c.var.user.id)))), 201);
    } catch (error) {
      if (error instanceof GoalLimitError) {
        return c.json(apiError("goal_limit", `You can have up to ${MAX_GOALS} goals.`), 400);
      }
      throw error;
    }
  });
