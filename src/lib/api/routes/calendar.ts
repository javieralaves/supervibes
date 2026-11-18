import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { errorResponses } from "@/lib/api/errors";
import { CALENDAR_DAYS_AHEAD, CALENDAR_DAYS_BACK, listBlocksAroundNow, type BlockDTO } from "@/lib/blocks";
import { DEFAULT_GOAL_COLOR, isGoalColor } from "@/lib/goal-colors";
import { listGoals } from "@/lib/goals";
import { draftRecapsAfterResponse, listAutoRecapCandidates } from "@/lib/recap";
import { getSettings, getTimeZone } from "@/lib/settings";
import { CLOCKS, timeZoneSchema } from "@/lib/settings-schema";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { listOpenTasks } from "@/lib/tasks";
import { listObjectivesBetween } from "@/lib/week-objectives";

/*
 * Everything the calendar shows, as app/(app)/calendar/page.tsx loads it: blocks from about five
 * weeks back to six ahead, the goals they belong to, open tasks (for the day strip and the task
 * panel), the sleep schedule and clock, and weekly objectives. Like the page, opening it starts
 * recaps drafting for sessions that just ended.
 */

/** Sessions drafted per visit; any more wait for the next one. Same as the web page. */
const AUTO_RECAPS_PER_VISIT = 3;

export const CalendarBlockSchema = z
  .object({
    id: z.string(),
    goalId: z.string(),
    title: z.string().nullable().openapi({ description: "null for protected time without a name." }),
    description: z.string().nullable().openapi({ description: "For protected time: what the session is for." }),
    startsAt: z.iso.datetime(),
    endsAt: z.iso.datetime(),
    fromSuggestion: z.string().nullable(),
    taskId: z.string().nullable().openapi({ description: "The task it schedules: an intention." }),
    taskDone: z.boolean(),
    hasAgenda: z.boolean(),
    hasRecapDraft: z.boolean().openapi({ description: "A recap waiting to be read and posted." }),
    recapDrafting: z.boolean().openapi({ description: "A recap is drafting itself in the background." }),
    hasRecapPost: z.boolean().openapi({ description: "Its recap has been posted to the goal's activity." }),
  })
  .openapi("CalendarBlock");

const CalendarGoalSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    icon: z.string(),
    color: z.string(),
  })
  .openapi("CalendarGoal");

const CalendarTaskSchema = z
  .object({
    id: z.string(),
    goalId: z.string(),
    title: z.string(),
    minutes: z.int(),
    plannedFor: z.iso.date().nullable(),
    dueOn: z.iso.date().nullable(),
  })
  .openapi("CalendarTask");

const CalendarSchema = z
  .object({
    today: z.iso.date(),
    daysBack: z.int().openapi({ description: "How far back the blocks go, in days." }),
    daysAhead: z.int().openapi({ description: "How far ahead the blocks go, in days." }),
    blocks: z.array(CalendarBlockSchema),
    goals: z.array(CalendarGoalSchema),
    tasks: z.array(CalendarTaskSchema).openapi({ description: "Open tasks across goals, in each goal's order." }),
    settings: z.object({
      sleepStart: z.int(),
      wakeTime: z.int(),
      clock: z.enum(CLOCKS).nullable(),
    }),
    objectives: z.array(z.object({ goalId: z.string(), weekStart: z.iso.date(), objective: z.string() })),
  })
  .openapi("Calendar");

const getRoute = createRoute({
  method: "get",
  path: "/calendar",
  operationId: "getCalendar",
  summary: "Blocks around now, with goals, open tasks, sleep and weekly objectives",
  security: [{ bearerAuth: [] }],
  request: { query: z.object({ timeZone: timeZoneSchema.optional() }) },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: CalendarSchema } } },
    ...errorResponses,
  },
});

export function asCalendarBlock(block: BlockDTO, drafting: Set<string>): z.infer<typeof CalendarBlockSchema> {
  return {
    id: block.id,
    goalId: block.goalId,
    title: block.title,
    description: block.description,
    startsAt: block.startsAt.toISOString(),
    endsAt: block.endsAt.toISOString(),
    fromSuggestion: block.fromSuggestion,
    taskId: block.taskId,
    taskDone: block.taskDone ?? false,
    hasAgenda: block.agenda !== null,
    hasRecapDraft: block.recap !== null,
    recapDrafting: drafting.has(block.id) || (block.recapDrafting ?? false),
    hasRecapPost: Boolean(block.recapPost),
  };
}

export const calendar = new OpenAPIHono<ApiEnv>().openapi(getRoute, async (c) => {
  const userId = c.var.user.id;
  const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
  const today = todayIn(timeZone);
  const [tasks, settings, goals, blocks, toRecap, objectives] = await Promise.all([
    listOpenTasks(userId),
    getSettings(userId),
    listGoals(userId),
    listBlocksAroundNow(userId),
    listAutoRecapCandidates(userId, AUTO_RECAPS_PER_VISIT),
    listObjectivesBetween(
      userId,
      weekStartOf(addDays(today, -CALENDAR_DAYS_BACK)),
      weekStartOf(addDays(today, CALENDAR_DAYS_AHEAD)),
    ),
  ]);
  // Sessions that just ended draft their recaps after this responds, as when the web page opens.
  const drafting = new Set(toRecap);
  draftRecapsAfterResponse(userId, toRecap);

  return c.json(
    {
      today,
      daysBack: CALENDAR_DAYS_BACK,
      daysAhead: CALENDAR_DAYS_AHEAD,
      blocks: blocks.map((block) => asCalendarBlock(block, drafting)),
      goals: goals.map((goal) => ({
        id: goal.id,
        title: goal.title,
        icon: goal.icon,
        color: isGoalColor(goal.color) ? goal.color : DEFAULT_GOAL_COLOR,
      })),
      tasks: tasks.map(({ id, goalId, title, minutes, plannedFor, dueOn }) => ({ id, goalId, title, minutes, plannedFor, dueOn })),
      settings,
      objectives: objectives.map(({ goalId, weekStart, objective }) => ({ goalId, weekStart, objective })),
    },
    200,
  );
});
