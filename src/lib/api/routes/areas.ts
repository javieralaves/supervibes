import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { GoalSchema, GoalWeekSchema, loadGoals } from "@/lib/api/routes/goals";
import { AreaReadError, getAreaRead, readArea, type AreaReadDTO } from "@/lib/area-read";
import { areaInputSchema, combineTrajectories, MAX_AREAS, worstStatus } from "@/lib/area-schema";
import { AreaLimitError, createArea, deleteArea, getArea, listAreas, reorderAreas, updateArea, type AreaDTO } from "@/lib/areas";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";
import { listGoals } from "@/lib/goals";
import { listTrajectories } from "@/lib/goal-statuses";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { buildTrajectory, STATUSES } from "@/lib/status-schema";

/*
 * Areas: the parts of someone's life their goals sit in. An area's status is its goals' statuses rolled up
 * (src/lib/area-schema.ts). Its read (src/lib/area-read.ts) is words only, written when the person asks.
 */

const AreaSchema = z
  .object({
    id: z.string(),
    name: z.string(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts, e.g. LaptopIcon." }),
    now: z.string().nullable().openapi({ description: "Where the person is in this area, in their words; null until said." }),
    want: z.string().nullable().openapi({ description: "Where they want it to go, in their words; null until said." }),
    status: z.enum(STATUSES).nullable().openapi({
      description: "The worst of its goals' latest statuses; null with no goals, or none with a status yet.",
    }),
    goalIds: z.array(z.string()).openapi({ description: "Its goals, in the goals' order." }),
  })
  .openapi("Area");

const AreasSchema = z
  .object({
    max: z.int().openapi({ description: "How many areas someone can have." }),
    areas: z.array(AreaSchema),
  })
  .openapi("Areas");

const AreaTrajectoryDaySchema = z
  .object({
    day: z.iso.date(),
    status: z.enum(STATUSES).nullable(),
    carried: z.boolean().openapi({ description: "No goal in the area had a read that day." }),
  })
  .openapi("AreaTrajectoryDay");

const AreaReadSchema = z
  .object({
    headline: z.string(),
    summary: z.string(),
    goalIds: z.array(z.string()).openapi({ description: "The goals whose reads it drew on." }),
    usedCalendar: z.boolean().openapi({ description: "It drew on the person's time on the calendar." }),
    createdAt: z.iso.datetime(),
  })
  .openapi("AreaRead");

const AreaDetailSchema = z
  .object({
    area: AreaSchema,
    read: AreaReadSchema.nullable().openapi({ description: "Its latest read; null until the person asks for one." }),
    today: z.iso.date(),
    trajectory: z.array(AreaTrajectoryDaySchema).openapi({
      description: "The last 28 days, oldest first: each day the worst of its goals' statuses.",
    }),
    goals: z.array(GoalSchema).openapi({ description: "Its goals, as GET /goals has them." }),
    week: z
      .object({
        start: z.iso.date().openapi({ description: "The Monday this week starts on." }),
        goals: z.array(GoalWeekSchema).openapi({ description: "Each of its goals' week, in the goals' order." }),
      })
      .openapi({ description: "This week, for its goals." }),
  })
  .openapi("AreaDetail");

const AreaInputSchema = z
  .object({
    name: z.string(),
    icon: z.enum(GOAL_ICON_NAMES),
    // Left out means null: the Mac app's client leaves out nil fields.
    now: z.string().nullable().optional().openapi({ description: "Left out or null: not said yet." }),
    want: z.string().nullable().optional().openapi({ description: "Left out or null: not said yet." }),
  })
  .openapi("AreaInput");

const AreaOrderSchema = z
  .object({ ids: z.array(z.uuid()).openapi({ description: "Every one of the person's areas, each once, in the new order." }) })
  .openapi("AreaOrder");

const areaParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const AREA_GONE = "That area doesn’t exist anymore.";

const listRoute = createRoute({
  method: "get",
  path: "/areas",
  operationId: "listAreas",
  summary: "Areas in order, each with its status and goals",
  security: [{ bearerAuth: [] }],
  request: {
    query: z.object({
      timeZone: timeZoneSchema.optional().openapi({ description: "The device's time zone; defaults to the stored one." }),
    }),
  },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: AreasSchema } } },
    ...errorResponses,
  },
});

const createRoute_ = createRoute({
  method: "post",
  path: "/areas",
  operationId: "createArea",
  summary: "Add an area",
  security: [{ bearerAuth: [] }],
  request: { body: { required: true, content: { "application/json": { schema: AreaInputSchema } } } },
  responses: {
    201: { description: "Created", content: { "application/json": { schema: AreaSchema } } },
    ...errorResponses,
  },
});

const readRoute = createRoute({
  method: "post",
  path: "/areas/{id}/read",
  operationId: "readArea",
  summary: "Write the area's read from its goals' reads and the calendar, replacing the last; takes a few seconds",
  security: [{ bearerAuth: [] }],
  request: { params: areaParam },
  responses: {
    200: { description: "Read", content: { "application/json": { schema: AreaReadSchema } } },
    ...errorResponses,
    404: notFound,
  },
});

const getRoute = createRoute({
  method: "get",
  path: "/areas/{id}",
  operationId: "getArea",
  summary: "One area's page: its words, status over the last four weeks, and its goals",
  security: [{ bearerAuth: [] }],
  request: { params: areaParam, query: z.object({ timeZone: timeZoneSchema.optional() }) },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: AreaDetailSchema } } },
    ...errorResponses,
    404: notFound,
  },
});

const updateRoute = createRoute({
  method: "patch",
  path: "/areas/{id}",
  operationId: "updateArea",
  summary: "Edit an area: its name, icon and words, sent whole",
  security: [{ bearerAuth: [] }],
  request: { params: areaParam, body: { required: true, content: { "application/json": { schema: AreaInputSchema } } } },
  responses: {
    200: { description: "Saved", content: { "application/json": { schema: AreaSchema } } },
    ...errorResponses,
    404: notFound,
  },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/areas/{id}",
  operationId: "deleteArea",
  summary: "Remove an area; its goals stay, with no area",
  security: [{ bearerAuth: [] }],
  request: { params: areaParam },
  responses: { 204: { description: "Removed" }, 401: errorResponses[401], 404: notFound },
});

const orderRoute = createRoute({
  method: "put",
  path: "/areas/order",
  operationId: "reorderAreas",
  summary: "Put the areas in a new order",
  security: [{ bearerAuth: [] }],
  request: { body: { required: true, content: { "application/json": { schema: AreaOrderSchema } } } },
  responses: { 204: { description: "Saved" }, ...errorResponses },
});

/**
 * The person's areas as the API sends them, each with its goals and its status: the worst of those goals'
 * statuses today (the last day of their trajectories, so a status from before the window still counts).
 */
async function asAreas(userId: string, list: AreaDTO[], timeZone: string | null) {
  const goals = (await listGoals(userId)).filter((goal) => goal.areaId);
  const trajectories = await listTrajectories(
    userId,
    goals.map((goal) => goal.id),
    timeZone,
  );
  return list.map((area) => {
    const goalIds = goals.filter((goal) => goal.areaId === area.id).map((goal) => goal.id);
    return {
      id: area.id,
      name: area.name,
      icon: area.icon,
      now: area.now,
      want: area.want,
      status: worstStatus(goalIds.map((id) => trajectories.get(id)?.days.at(-1)?.status)),
      goalIds,
    };
  });
}

const asRead = (read: AreaReadDTO) => ({ ...read, createdAt: read.createdAt.toISOString() });

const invalid = (issues: { message: string }[]) => apiError("invalid_request", issues[0]?.message ?? "Check the form.");

export const areas = new OpenAPIHono<ApiEnv>()
  .openapi(listRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    return c.json({ max: MAX_AREAS, areas: await asAreas(userId, await listAreas(userId), timeZone) }, 200);
  })
  .openapi(createRoute_, async (c) => {
    const parsed = areaInputSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) return c.json(invalid(parsed.error.issues), 400);
    try {
      const area = await createArea(c.var.user.id, parsed.data);
      return c.json({ ...area, status: null, goalIds: [] }, 201);
    } catch (error) {
      if (error instanceof AreaLimitError) {
        return c.json(apiError("area_limit", `You can have up to ${MAX_AREAS} areas.`), 400);
      }
      throw error;
    }
  })
  // Before /areas/{id}, so "order" isn't read as an id.
  .openapi(orderRoute, async (c) => {
    if (!(await reorderAreas(c.var.user.id, c.req.valid("json").ids))) {
      return c.json(apiError("invalid_request", "Send every area once, in the new order."), 400);
    }
    return c.body(null, 204);
  })
  .openapi(getRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const area = await getArea(userId, id);
    if (!area) return c.json(apiError("not_found", AREA_GONE), 404);
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const [{ today, goals, week }, read] = await Promise.all([
      loadGoals(userId, timeZone, (goal) => goal.areaId === id),
      getAreaRead(userId, id),
    ]);
    const days = buildTrajectory([], null, today).map((d) => d.day);
    const trajectory = combineTrajectories(
      goals.map((goal) => goal.trajectory),
      days,
    );
    const view = {
      id: area.id,
      name: area.name,
      icon: area.icon,
      now: area.now,
      want: area.want,
      // Its status today is the trajectory's last day, as asAreas works it out for the list.
      status: trajectory.at(-1)?.status ?? null,
      goalIds: goals.map((goal) => goal.id),
    };
    return c.json({ area: view, read: read && asRead(read), today, trajectory, goals, week }, 200);
  })
  .openapi(readRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    if (!(await getArea(userId, id))) return c.json(apiError("not_found", AREA_GONE), 404);
    try {
      return c.json(asRead(await readArea(userId, id)), 200);
    } catch (error) {
      if (error instanceof AreaReadError) return c.json(apiError("read_failed", error.message), 400);
      console.error("[area-read] failed", error);
      return c.json(apiError("read_failed", "Couldn’t read this area. Try again."), 400);
    }
  })
  .openapi(updateRoute, async (c) => {
    const parsed = areaInputSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) return c.json(invalid(parsed.error.issues), 400);
    const userId = c.var.user.id;
    const area = await updateArea(userId, c.req.valid("param").id, parsed.data);
    if (!area) return c.json(apiError("not_found", AREA_GONE), 404);
    const [view] = await asAreas(userId, [area], await getTimeZone(userId));
    return c.json(view, 200);
  })
  .openapi(deleteRoute, async (c) => {
    if (!(await deleteArea(c.var.user.id, c.req.valid("param").id))) {
      return c.json(apiError("not_found", AREA_GONE), 404);
    }
    return c.body(null, 204);
  });
