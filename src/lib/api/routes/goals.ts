import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { getReadStatus, requestRead } from "@/lib/background-read";
import { GOAL_COLOR_KEYS } from "@/lib/goal-colors";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";
import { goalInputSchema, MAX_GOALS } from "@/lib/goal-schema";
import { getLatestStatus, listTrajectories } from "@/lib/goal-statuses";
import { createGoal, deleteGoal, GoalLimitError, listGoals, updateGoal, type GoalDTO } from "@/lib/goals";
import { listPosts } from "@/lib/posts";
import { getLatestRead } from "@/lib/progress";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { getGoal, listSources } from "@/lib/sources";
import { buildTrajectory, CONFIDENCES, STATUS_BASES, STATUSES } from "@/lib/status-schema";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { listTasks } from "@/lib/tasks";
import { weekObjectiveSchema, weekStartSchema } from "@/lib/week-objective-schema";
import { getWeekObjectives, setWeekObjective } from "@/lib/week-objectives";

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

const ReadSchema = z
  .object({
    headline: z.string(),
    summary: z.string(),
    basedOn: z.array(z.string()).openapi({ description: "Provider keys or labels, plus \"notes\" and \"tasks\"." }),
    createdAt: z.iso.datetime(),
  })
  .openapi("GoalRead");

const StatusViewSchema = z
  .object({
    status: z.enum(STATUSES),
    basis: z.enum(STATUS_BASES),
    reason: z.string(),
    outlook: z
      .object({
        status: z.enum(["on_track", "at_risk", "off_track"]),
        finishFrom: z.iso.date().nullable(),
        finishTo: z.iso.date().nullable(),
        confidence: z.enum(CONFIDENCES),
      })
      .nullable(),
    at: z.iso.datetime(),
  })
  .openapi("GoalStatusView");

const GoalDetailSchema = z
  .object({
    goal: GoalSchema,
    today: z.iso.date(),
    read: ReadSchema.nullable(),
    status: StatusViewSchema.nullable(),
    readsInTrajectory: z.int().openapi({ description: "How many reads the trajectory rests on." }),
    readPending: z.boolean().openapi({ description: "A progress read is running; poll until it lands." }),
    readError: z.string().nullable(),
    canRead: z.boolean().openapi({ description: "There's a source, task or note to read." }),
    week: z.object({
      start: z.iso.date().openapi({ description: "The Monday this week starts on." }),
      objective: z.string().nullable(),
      lastWeek: z.string().nullable(),
    }),
  })
  .openapi("GoalDetail");

const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const GOAL_GONE = "That goal doesn’t exist anymore.";

const getRoute = createRoute({
  method: "get",
  path: "/goals/{id}",
  operationId: "getGoal",
  summary: "One goal's page: its read, status, trail and this week",
  security: [{ bearerAuth: [] }],
  request: {
    params: goalParam,
    query: z.object({ timeZone: timeZoneSchema.optional() }),
  },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: GoalDetailSchema } } },
    ...errorResponses,
    404: notFound,
  },
});

const updateRoute = createRoute({
  method: "patch",
  path: "/goals/{id}",
  operationId: "updateGoal",
  summary: "Edit a goal",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: GoalInputSchema } } } },
  responses: {
    200: { description: "Saved", content: { "application/json": { schema: GoalSchema } } },
    ...errorResponses,
    404: notFound,
  },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/goals/{id}",
  operationId: "deleteGoal",
  summary: "Delete a goal, with its sources and reads",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam },
  responses: { 204: { description: "Deleted" }, 401: errorResponses[401], 404: notFound },
});

const readRoute = createRoute({
  method: "post",
  path: "/goals/{id}/read",
  operationId: "requestGoalRead",
  summary: "Update status: start a progress read in the background",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam },
  responses: { 202: { description: "Started; poll the goal until readPending is false" }, 401: errorResponses[401], 404: notFound },
});

const weekRoute = createRoute({
  method: "put",
  path: "/goals/{id}/weeks/{weekStart}",
  operationId: "setWeekObjective",
  summary: "What a week should move for the goal; empty clears it",
  security: [{ bearerAuth: [] }],
  request: {
    params: goalParam.extend({ weekStart: z.iso.date().openapi({ param: { name: "weekStart", in: "path" } }) }),
    body: {
      required: true,
      content: { "application/json": { schema: z.object({ objective: z.string() }).openapi("WeekObjectiveInput") } },
    },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
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
    })
  .openapi(getRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const goal = await getGoal(userId, id);
    if (!goal) return c.json(apiError("not_found", GOAL_GONE), 404);

    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const today = todayIn(timeZone);
    const weekStart = weekStartOf(today);
    const lastWeekStart = addDays(weekStart, -7);
    const [read, status, readStatus, trajectories, objectives, sources, tasks, posts] = await Promise.all([
      getLatestRead(userId, id),
      getLatestStatus(userId, id),
      getReadStatus(userId, id),
      listTrajectories(userId, [id], timeZone),
      getWeekObjectives(userId, id, [weekStart, lastWeekStart]),
      listSources(userId, id),
      listTasks(userId, id),
      listPosts(userId, id, 1),
    ]);
    const trajectory = trajectories.get(id);

    return c.json(
      {
        goal: asGoal(goal, trajectory?.days ?? buildTrajectory([], null, today)),
        today,
        read: read && {
          headline: read.headline,
          summary: read.summary,
          basedOn: read.basedOn,
          createdAt: read.createdAt.toISOString(),
        },
        status,
        readsInTrajectory: trajectory?.reads ?? 0,
        readPending: readStatus.pending,
        readError: readStatus.error,
        canRead: sources.length > 0 || tasks.length > 0 || posts.length > 0,
        week: {
          start: weekStart,
          objective: objectives.get(weekStart) ?? null,
          lastWeek: objectives.get(lastWeekStart) ?? null,
        },
      },
      200,
    );
  })
  .openapi(updateRoute, async (c) => {
    const parsed = goalInputSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) {
      return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the form."), 400);
    }
    const userId = c.var.user.id;
    const goal = await updateGoal(userId, c.req.valid("param").id, parsed.data);
    if (!goal) return c.json(apiError("not_found", GOAL_GONE), 404);
    const trajectories = await listTrajectories(userId, [goal.id], await getTimeZone(userId));
    return c.json(asGoal(goal, trajectories.get(goal.id)?.days ?? []), 200);
  })
  .openapi(deleteRoute, async (c) => {
    const deleted = await deleteGoal(c.var.user.id, c.req.valid("param").id);
    if (!deleted) return c.json(apiError("not_found", GOAL_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(readRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    if (!(await getGoal(userId, id))) return c.json(apiError("not_found", GOAL_GONE), 404);
    // As the web's "Update status": the read runs after this responds.
    await requestRead(userId, id, { trigger: "manual", settle: false });
    return c.body(null, 202);
  })
  .openapi(weekRoute, async (c) => {
    const { id, weekStart } = c.req.valid("param");
    const week = weekStartSchema.safeParse(weekStart);
    const objective = weekObjectiveSchema.safeParse(c.req.valid("json").objective);
    if (!week.success) return c.json(apiError("invalid_request", week.error.issues[0]?.message ?? "Pick a valid week."), 400);
    if (!objective.success) {
      return c.json(apiError("invalid_request", objective.error.issues[0]?.message ?? "Check the objective."), 400);
    }
    if (!(await setWeekObjective(c.var.user.id, id, week.data, objective.data))) {
      return c.json(apiError("not_found", GOAL_GONE), 404);
    }
    return c.body(null, 204);
  });
