import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { asNote, NoteSchema } from "@/lib/api/routes/notes";
import { asSource, SourceSchema } from "@/lib/api/routes/sources";
import { listBlocks } from "@/lib/blocks";
import { listConnections } from "@/lib/connections";
import { PROVIDER_KEYS, PROVIDERS } from "@/lib/providers";
import { asTask, SuggestionSchema, TaskSchema } from "@/lib/api/routes/tasks";
import { getReadStatus, requestRead } from "@/lib/background-read";
import { GOAL_COLOR_KEYS } from "@/lib/goal-colors";
import { goalWeekLoads, sessionBlocks } from "@/lib/goal-week";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";
import { GOAL_KINDS, goalInputSchema, MAX_GOALS, MAX_MIN_MINUTES, MAX_PER_WEEK, practiceFieldsSchema } from "@/lib/goal-schema";
import { getLatestStatus, listTrajectories } from "@/lib/goal-statuses";
import { getArea, ownsAreas, setGoalArea } from "@/lib/areas";
import { createGoal, deleteGoal, GoalLimitError, listGoals, listGoalUpdatedAt, PracticeError, updateGoal, type GoalDTO } from "@/lib/goals";
import { getPracticeDetail, listPracticeStates, type PracticeSessionView } from "@/lib/practice";
import { statusReason, type PracticeState } from "@/lib/practice-count";
import { listPosts } from "@/lib/posts";
import { getLatestRead } from "@/lib/progress";
import { getSettings, getTimeZone } from "@/lib/settings";
import { CLOCKS, timeZoneSchema } from "@/lib/settings-schema";
import { getGoal, listSources } from "@/lib/sources";
import { buildTrajectory, CONFIDENCES, STATUS_BASES, STATUSES } from "@/lib/status-schema";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { listOpenTasks, listTasks, listTaskSchedules } from "@/lib/tasks";
import { weekObjectiveSchema, weekStartSchema } from "@/lib/week-objective-schema";
import { getWeekObjectives, listObjectivesBetween, setWeekObjective } from "@/lib/week-objectives";
import { startOfDayIn } from "@/lib/zoned-day";

export const TrajectoryDaySchema = z
  .object({
    day: z.iso.date(),
    status: z.enum(STATUSES).nullable(),
    basis: z.enum(STATUS_BASES).nullable(),
    reason: z.string().nullable(),
    carried: z.boolean().openapi({ description: "No read that day: the status is the one before it." }),
  })
  .openapi("TrajectoryDay");

/** A goal's session time on the calendar, clipped to the weeks it's sent for. */
export const ProtectedBlockSchema = z.object({ startsAt: z.iso.datetime(), endsAt: z.iso.datetime() }).openapi("ProtectedBlock");

const PracticeWeekSchema = z
  .object({
    start: z.iso.date().openapi({ description: "The Monday it starts on." }),
    done: z.int().openapi({ description: "Sessions that counted." }),
    planned: z.int().openapi({ description: "Sessions still to come: blocks not over yet, and ones meant for a day from today on." }),
    paused: z.boolean().openapi({ description: "Paused at any point, so it's left out of the status." }),
    beforeStart: z.boolean().openapi({ description: "It started before the practice was made, so it's left out of the status." }),
  })
  .openapi("PracticeWeek");

const PracticeSchema = z
  .object({
    perWeek: z.int().openapi({ description: "How many sessions a week it's meant to have." }),
    minMinutes: z.int().nullable().openapi({ description: "Blocks shorter than this don't count; null: any length." }),
    week: PracticeWeekSchema.extend({
      left: z.int().openapi({ description: "Sessions still to do this week: perWeek less what's counted, never below 0." }),
    }).openapi("PracticeThisWeek"),
    status: z
      .object({
        status: z.enum(["on_track", "at_risk", "off_track"]),
        done: z.int().openapi({ description: "Sessions in the weeks it looked at, each week counted up to perWeek." }),
        expected: z.int().openapi({ description: "What was meant in those weeks: perWeek for each." }),
        weeks: z.int().openapi({ description: "How many full weeks it looked at: up to 4, not paused, since it was made." }),
        reason: z.string().openapi({ description: "In a few words, e.g. \"8 of the last 12\"." }),
      })
      .nullable()
      .openapi({ description: "Counted from the last 4 full weeks; null with none yet, or while it's paused." }),
    paused: z
      .object({
        startsOn: z.iso.date(),
        resumesOn: z.iso.date().nullable().openapi({ description: "The day it picks up again; null until it's resumed." }),
      })
      .nullable()
      .openapi({ description: "The pause it's in today, if any." }),
  })
  .openapi("Practice");

export const GoalSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    description: z.string().nullable(),
    targetDate: z.iso.date().nullable(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts, e.g. Rocket01Icon." }),
    color: z.string().openapi({ description: "A key from lib/goal-colors.ts, e.g. violet." }),
    areaId: z.string().nullable().openapi({ description: "The area the goal sits in; null when none." }),
    updatedAt: z.iso.datetime().openapi({
      description: "When the goal last moved: its latest progress read or note, or when it was made if it has neither.",
    }),
    trajectory: z.array(TrajectoryDaySchema).openapi({ description: "The last 28 days, oldest first." }),
    kind: z.enum(GOAL_KINDS).openapi({ description: "A project (it has a finish line), or a practice kept up a number of times a week." }),
    autoRecaps: z.boolean().openapi({ description: "Its sessions get a recap drafted on their own once they're over." }),
    practice: PracticeSchema.nullable().openapi({ description: "For a practice: its rhythm, this week and its status. Null for a project." }),
  })
  .openapi("Goal");

export const GoalWeekSchema = z
  .object({
    goalId: z.string(),
    objective: z.string().nullable().openapi({ description: "What this week should move for the goal; null when not set." }),
    sessionMinutes: z.int().openapi({ description: "Session time on the calendar this week, gone by or not: room for tasks." }),
    reservedMinutes: z.int().openapi({ description: "Reserved time this week, kept for its own sake: no room for tasks." }),
    plannedMinutes: z.int().openapi({
      description:
        "Open estimates meant for this week (its days, the week itself, or carried into it) plus the session time already gone by. Weighed against sessionMinutes, as the planning board's This week ring.",
    }),
  })
  .openapi("GoalWeek");

const GoalsSchema = z
  .object({
    today: z.iso.date().openapi({ description: "Today in `timeZone`; the trajectories end on it." }),
    max: z.int().openapi({ description: "How many goals someone can have." }),
    goals: z.array(GoalSchema),
    week: z
      .object({
        start: z.iso.date().openapi({ description: "The Monday this week starts on." }),
        goals: z.array(GoalWeekSchema).openapi({ description: "Each goal's week, in the goals' order." }),
      })
      .openapi({ description: "This week, goal by goal, for the cards on Goals home." }),
  })
  .openapi("Goals");

const GoalInputSchema = z
  .object({
    title: z.string(),
    // Left out means null: the Mac app's client leaves out nil fields.
    description: z.string().nullable().optional().openapi({ description: "Left out or null: none." }),
    targetDate: z.string().nullable().optional().openapi({ description: "YYYY-MM-DD; left out or null: none." }),
    icon: z.enum(GOAL_ICON_NAMES),
    color: z.enum(GOAL_COLOR_KEYS),
    perWeek: z.int().optional().openapi({ description: `For a practice: sessions a week, 1 to ${MAX_PER_WEEK}. Left out keeps it.` }),
    minMinutes: z.int().optional().openapi({
      description: `For a practice: the shortest block that counts, up to ${MAX_MIN_MINUTES} minutes; 0 clears it. Left out keeps it.`,
    }),
    autoRecaps: z.boolean().optional().openapi({ description: "Draft its sessions' recaps on their own. Left out keeps it." }),
  })
  .openapi("GoalInput");

// GoalInput plus where to start it, spelled out rather than extended: an extended schema becomes an allOf, which the
// Mac app's generated client turns into a wrapper instead of a plain struct.
const NewGoalSchema = z
  .object({
    title: z.string(),
    description: z.string().nullable().optional().openapi({ description: "Left out or null: none." }),
    targetDate: z.string().nullable().optional().openapi({ description: "YYYY-MM-DD; left out or null: none." }),
    icon: z.enum(GOAL_ICON_NAMES),
    color: z.enum(GOAL_COLOR_KEYS),
    areaId: z.uuid().nullable().optional().openapi({ description: "An area of the person's to start the goal in; left out or null: none." }),
    kind: z.enum(GOAL_KINDS).optional().openapi({ description: "Left out: a project. A practice needs perWeek and has no target date." }),
    perWeek: z.int().optional().openapi({ description: `For a practice: sessions a week, 1 to ${MAX_PER_WEEK}.` }),
    minMinutes: z.int().optional().openapi({
      description: `For a practice: the shortest block that counts, up to ${MAX_MIN_MINUTES} minutes.`,
    }),
    autoRecaps: z.boolean().optional().openapi({ description: "Draft its sessions' recaps on their own." }),
  })
  .openapi("NewGoal");

const GoalAreaInputSchema = z
  .object({
    // An empty string, not null, takes the goal out: the Mac app's generated client can't send an explicit null.
    // A plain string here (checked in the handler), since a union would generate a wrapper type in Swift.
    areaId: z.string().openapi({
      description: "One of the person's areas (its id), or an empty string to take the goal out of its area.",
    }),
  })
  .openapi("GoalAreaInput");

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
  request: { body: { required: true, content: { "application/json": { schema: NewGoalSchema } } } },
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

const GoalAreaSchema = z
  .object({
    id: z.string(),
    name: z.string(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts." }),
  })
  .openapi("GoalArea");

const GoalDetailSchema = z
  .object({
    goal: GoalSchema,
    area: GoalAreaSchema.nullable().openapi({ description: "The area the goal sits in, to show and link to; null when none." }),
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
      protectedMinutes: z.int().openapi({ description: "Session time on the calendar for this goal this week, in minutes; reserved time isn't counted." }),
      protectedBlocks: z
        .array(ProtectedBlockSchema)
        .openapi({
          description:
            "The goal's time on the calendar this week and next that tasks can go in (not reserved time), clipped to those two weeks, earliest first. For weighing what's planned against it.",
        }),
      done: z.array(TaskSchema).openapi({ description: "Tasks checked off this week, most recently first." }),
    }),
    tasks: z.array(TaskSchema).openapi({ description: "Open tasks in their order (checked-off ones move to the activity)." }),
    practice: z
      .object({
        weeks: z.array(PracticeWeekSchema).openapi({ description: "The last 8 full weeks, oldest first." }),
        sessions: z
          .array(
            z
              .object({
                id: z.string().openapi({ description: "The block's id, or the off-calendar session's." }),
                source: z.enum(["block", "day"]).openapi({ description: "A block on the calendar, or one off it (planned for its day, or done)." }),
                day: z.iso.date(),
                state: z.enum(["done", "planned", "missed", "short", "lapsed"]).openapi({
                  description:
                    "done counts; planned is still to come; missed: a block that didn't happen; short: a block under the minimum; lapsed: a day that went by without being ticked off.",
                }),
                title: z.string().nullable().openapi({ description: "A block's own title; null for the practice's." }),
                startsAt: z.iso.datetime().nullable(),
                endsAt: z.iso.datetime().nullable(),
              })
              .openapi("PracticeSession"),
          )
          .openapi({ description: "Every session from the first of those weeks to the end of next week, earliest first." }),
      })
      .nullable()
      .openapi({ description: "For a practice: its last weeks and its sessions. Null for a project." }),
    suggestions: z.array(SuggestionSchema).openapi({ description: "The latest read's suggestions still to handle." }),
    clock: z.enum(CLOCKS).nullable().openapi({ description: "The person's clock; null follows the device." }),
    notes: z.array(NoteSchema).openapi({ description: "The activity, newest first." }),
    author: z.object({ name: z.string(), image: z.string().nullable() }).openapi({ description: "Who the activity is by." }),
    sources: z.array(SourceSchema),
    connectionOptions: z
      .array(
        z
          .object({
            id: z.string(),
            provider: z.enum(PROVIDER_KEYS),
            label: z.string(),
            relationHint: z.string().openapi({ description: "An example relation, for the dialog's placeholder." }),
          })
          .openapi("ConnectionOption"),
      )
      .openapi({ description: "Connected apps a new source can read from." }),
  })
  .openapi("GoalDetail");

const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const GOAL_GONE = "That goal doesn’t exist anymore.";
const AREA_GONE = "That area doesn’t exist anymore.";

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
  responses: {
    202: { description: "Started; poll the goal until readPending is false" },
    400: errorResponses[400],
    401: errorResponses[401],
    404: notFound,
  },
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

const areaRoute = createRoute({
  method: "put",
  path: "/goals/{id}/area",
  operationId: "setGoalArea",
  summary: "Place a goal in an area, or take it out of its area",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: GoalAreaInputSchema } } } },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const asPractice = (goal: GoalDTO, state: PracticeState | undefined): z.infer<typeof PracticeSchema> | null => {
  if (goal.kind !== "practice" || !state) return null;
  const { start, done, planned, paused, beforeStart, left } = state.week;
  return {
    perWeek: goal.perWeek ?? 1,
    minMinutes: goal.minMinutes,
    week: { start, done, planned, paused, beforeStart, left },
    status: state.status && { ...state.status, reason: statusReason(state.status) },
    paused: state.paused,
  };
};

export const asSession = (session: PracticeSessionView) => ({
  ...session,
  startsAt: session.startsAt?.toISOString() ?? null,
  endsAt: session.endsAt?.toISOString() ?? null,
});

export const asGoal = (
  goal: GoalDTO,
  trajectory: z.infer<typeof TrajectoryDaySchema>[],
  updatedAt: Date | undefined,
  practice?: PracticeState,
) => ({
  id: goal.id,
  title: goal.title,
  description: goal.description,
  targetDate: goal.targetDate,
  icon: goal.icon,
  color: goal.color,
  areaId: goal.areaId,
  updatedAt: (updatedAt ?? new Date()).toISOString(),
  trajectory,
  kind: goal.kind,
  autoRecaps: goal.autoRecaps,
  practice: asPractice(goal, practice),
});

/**
 * Goals as Goals home and an area's page show them: each with its last four weeks and when it last moved, and this
 * week goal by goal (its objective and its time). `only` narrows them to some goals, in the same order.
 */
export async function loadGoals(userId: string, timeZone: string | null, only?: (goal: GoalDTO) => boolean) {
  const today = todayIn(timeZone);
  const weekStart = weekStartOf(today);
  const zone = timeZone ?? "UTC";
  const weekBounds = { start: startOfDayIn(weekStart, zone), end: startOfDayIn(addDays(weekStart, 7), zone) };
  const list = (await listGoals(userId)).filter((goal) => !only || only(goal));
  const ids = list.map((goal) => goal.id);
  const [trajectories, updated, tasks, blocks, objectives, practices] = await Promise.all([
    listTrajectories(userId, ids, timeZone),
    listGoalUpdatedAt(userId, ids),
    listOpenTasks(userId),
    listBlocks(userId, weekBounds.start, weekBounds.end),
    listObjectivesBetween(userId, weekStart, weekStart),
    listPracticeStates(
      userId,
      list.filter((goal) => goal.kind === "practice"),
      timeZone,
    ),
  ]);
  const loads = goalWeekLoads(ids, tasks, blocks, weekBounds, today, new Date());
  const objectiveOf = new Map(objectives.map((row) => [row.goalId, row.objective]));
  return {
    today,
    goals: list.map((goal) =>
      asGoal(goal, trajectories.get(goal.id)?.days ?? buildTrajectory([], null, today), updated.get(goal.id), practices.get(goal.id)),
    ),
    week: {
      start: weekStart,
      goals: ids.map((goalId) => ({
        goalId,
        objective: objectiveOf.get(goalId) ?? null,
        ...(loads.get(goalId) ?? { sessionMinutes: 0, reservedMinutes: 0, plannedMinutes: 0 }),
      })),
    },
  };
}

export const goals = new OpenAPIHono<ApiEnv>()
  .openapi(listRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const { today, goals, week } = await loadGoals(userId, timeZone);
    return c.json({ today, max: MAX_GOALS, goals, week }, 200);
  })
  .openapi(createRoute_, async (c) => {
    // Same rules and messages as the web's dialog (lib/goal-schema.ts).
    const body = c.req.valid("json");
    const parsed = goalInputSchema.safeParse(body);
    if (!parsed.success) {
      return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the form."), 400);
    }
    const practiceFields = practiceFieldsSchema.safeParse(body);
    if (!practiceFields.success) {
      return c.json(apiError("invalid_request", practiceFields.error.issues[0]?.message ?? "Check the form."), 400);
    }
    const isPractice = body.kind === "practice";
    const perWeek = practiceFields.data.perWeek;
    if (isPractice && perWeek === undefined) return c.json(apiError("invalid_request", "Say how many times a week."), 400);
    const areaId = body.areaId ?? null;
    if (areaId && !(await ownsAreas(c.var.user.id, [areaId]))) {
      return c.json(apiError("invalid_request", AREA_GONE), 400);
    }
    try {
      const userId = c.var.user.id;
      const goal = await createGoal(userId, parsed.data, areaId, isPractice ? { ...practiceFields.data, perWeek: perWeek! } : null);
      const timeZone = await getTimeZone(userId);
      const practice = isPractice ? (await listPracticeStates(userId, [goal], timeZone)).get(goal.id) : undefined;
      return c.json(asGoal(goal, buildTrajectory([], null, todayIn(timeZone)), new Date(), practice), 201);
    } catch (error) {
      if (error instanceof GoalLimitError) return c.json(apiError("goal_limit", error.message), 400);
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
    // Without a saved zone, "today" is the server's own day, which runs in UTC.
    const zone = timeZone ?? "UTC";
    const weekBounds = { start: startOfDayIn(weekStart, zone), end: startOfDayIn(addDays(weekStart, 7), zone) };
    // This week and next, for the planning board's capacity.
    const twoWeeksEnd = startOfDayIn(addDays(weekStart, 14), zone);
    const [read, status, readStatus, trajectories, objectives, sources, tasks, posts, schedules, settings, connections, blocks, updated, practice] = await Promise.all([
      getLatestRead(userId, id),
      getLatestStatus(userId, id),
      getReadStatus(userId, id),
      listTrajectories(userId, [id], timeZone),
      getWeekObjectives(userId, id, [weekStart, lastWeekStart]),
      listSources(userId, id),
      listTasks(userId, id),
      listPosts(userId, id),
      listTaskSchedules(userId, id),
      getSettings(userId),
      listConnections(userId),
      listBlocks(userId, weekBounds.start, twoWeeksEnd),
      listGoalUpdatedAt(userId, [id]),
      goal.kind === "practice" ? getPracticeDetail(userId, goal, timeZone) : null,
    ]);
    const area = goal.areaId ? await getArea(userId, goal.areaId) : null;
    const trajectory = trajectories.get(id);
    // Blocks clipped to the week, so one running over Sunday midnight counts only its part.
    const goalBlocks = blocks.filter((b) => b.goalId === id);
    // Reserved time is kept for its own sake, so it's no room for tasks.
    const weekBlocks = goalBlocks.filter((b) => b.startsAt < weekBounds.end && !b.reserved);
    const protectedBlocks = sessionBlocks(goalBlocks, id, weekBounds.start, twoWeeksEnd);
    const protectedMinutes = Math.round(
      weekBlocks.reduce(
        (sum, b) => sum + Math.max(0, Math.min(b.endsAt.getTime(), weekBounds.end.getTime()) - Math.max(b.startsAt.getTime(), weekBounds.start.getTime())),
        0,
      ) / 60_000,
    );

    return c.json(
      {
        goal: asGoal(goal, trajectory?.days ?? buildTrajectory([], null, today), updated.get(id), practice?.state),
        area: area && { id: area.id, name: area.name, icon: area.icon },
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
          protectedMinutes,
          protectedBlocks,
          done: tasks.filter((task) => task.doneAt && task.doneAt >= weekBounds.start).map((task) => asTask(task)),
        },
        tasks: tasks.filter((task) => !task.doneAt).map((task) => asTask(task, schedules.get(task.id) ?? null)),
        practice: practice && { weeks: practice.state.weeks, sessions: practice.sessions.map(asSession) },
        suggestions: read?.suggestions ?? [],
        clock: settings.clock,
        notes: posts.map(asNote),
        author: { name: c.var.user.name, image: c.var.user.image ?? null },
        sources: sources.map(asSource),
        connectionOptions: connections
          .filter((connection) => connection.status === "connected")
          .map((connection) => ({
            id: connection.id,
            provider: connection.provider,
            label: PROVIDERS[connection.provider].label,
            relationHint: PROVIDERS[connection.provider].relationHint,
          })),
      },
      200,
    );
  })
  .openapi(updateRoute, async (c) => {
    const body = c.req.valid("json");
    const parsed = goalInputSchema.safeParse(body);
    if (!parsed.success) {
      return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the form."), 400);
    }
    const practiceFields = practiceFieldsSchema.safeParse(body);
    if (!practiceFields.success) {
      return c.json(apiError("invalid_request", practiceFields.error.issues[0]?.message ?? "Check the form."), 400);
    }
    const userId = c.var.user.id;
    const goal = await updateGoal(userId, c.req.valid("param").id, parsed.data, practiceFields.data);
    if (!goal) return c.json(apiError("not_found", GOAL_GONE), 404);
    const timeZone = await getTimeZone(userId);
    const [trajectories, updated, practices] = await Promise.all([
      listTrajectories(userId, [goal.id], timeZone),
      listGoalUpdatedAt(userId, [goal.id]),
      goal.kind === "practice" ? listPracticeStates(userId, [goal], timeZone) : null,
    ]);
    return c.json(asGoal(goal, trajectories.get(goal.id)?.days ?? [], updated.get(goal.id), practices?.get(goal.id)), 200);
  })
  .openapi(deleteRoute, async (c) => {
    const deleted = await deleteGoal(c.var.user.id, c.req.valid("param").id);
    if (!deleted) return c.json(apiError("not_found", GOAL_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(readRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const goal = await getGoal(userId, id);
    if (!goal) return c.json(apiError("not_found", GOAL_GONE), 404);
    if (goal.kind === "practice") return c.json(apiError("practice", "A practice’s status is counted from its sessions, not read."), 400);
    // As the web's "Update status": the read runs after this responds.
    await requestRead(userId, id, { trigger: "manual", settle: false });
    return c.body(null, 202);
  })
  .openapi(areaRoute, async (c) => {
    const areaId = c.req.valid("json").areaId;
    if (areaId && !z.uuid().safeParse(areaId).success) return c.json(apiError("invalid_request", AREA_GONE), 400);
    const result = await setGoalArea(c.var.user.id, c.req.valid("param").id, areaId || null);
    if (result === "goal_not_found") return c.json(apiError("not_found", GOAL_GONE), 404);
    if (result === "area_not_found") return c.json(apiError("not_found", AREA_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(weekRoute, async (c) => {
    const { id, weekStart } = c.req.valid("param");
    const week = weekStartSchema.safeParse(weekStart);
    const objective = weekObjectiveSchema.safeParse(c.req.valid("json").objective);
    if (!week.success) return c.json(apiError("invalid_request", week.error.issues[0]?.message ?? "Pick a valid week."), 400);
    if (!objective.success) {
      return c.json(apiError("invalid_request", objective.error.issues[0]?.message ?? "Check the objective."), 400);
    }
    try {
      if (!(await setWeekObjective(c.var.user.id, id, week.data, objective.data))) {
        return c.json(apiError("not_found", GOAL_GONE), 404);
      }
    } catch (error) {
      if (error instanceof PracticeError) return c.json(apiError("practice", error.message), 400);
      throw error;
    }
    return c.body(null, 204);
  });
