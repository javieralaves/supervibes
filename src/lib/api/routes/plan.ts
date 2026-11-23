import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { errorResponses } from "@/lib/api/errors";
import { ProtectedBlockSchema } from "@/lib/api/routes/goals";
import { asTask, TaskSchema } from "@/lib/api/routes/tasks";
import { listBlocks } from "@/lib/blocks";
import { sessionBlocks } from "@/lib/goal-week";
import { listGoals } from "@/lib/goals";
import { getSettings, getTimeZone } from "@/lib/settings";
import { CLOCKS, timeZoneSchema } from "@/lib/settings-schema";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { listOpenTasks, listTaskSchedules, listTasksDoneSince } from "@/lib/tasks";
import { listObjectivesBetween } from "@/lib/week-objectives";
import { startOfDayIn } from "@/lib/zoned-day";

/*
 * The planning board, across goals: each goal's open tasks, what it finished this week, its
 * objective, and its session time this week and next to weigh them against; and every block in
 * those two weeks with the person's waking hours, for finding time when a day is over. The Mac app shows it
 * for every goal (Plan on the rail) or one (Plan tasks on a goal's page).
 */

const PlanGoalSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts, e.g. Rocket01Icon." }),
    color: z.string().openapi({ description: "A key from lib/goal-colors.ts, e.g. violet." }),
    objective: z.string().nullable().openapi({ description: "What this week should move for the goal; null when not set." }),
    tasks: z.array(TaskSchema).openapi({ description: "Open tasks in their order." }),
    done: z.array(TaskSchema).openapi({ description: "Tasks checked off this week, most recently first." }),
    protectedBlocks: z.array(ProtectedBlockSchema).openapi({
      description: "Its sessions this week and next (not reserved time), clipped to those two weeks, earliest first.",
    }),
  })
  .openapi("PlanGoal");

const PlanBlockSchema = z
  .object({
    id: z.string(),
    goalId: z.string(),
    startsAt: z.iso.datetime(),
    endsAt: z.iso.datetime(),
    reserved: z.boolean().openapi({ description: "Kept for its own sake: no room for tasks." }),
    taskId: z.string().nullable().openapi({ description: "The task it gives a time to, if it does." }),
  })
  .openapi("PlanBlock");

const PlanSchema = z
  .object({
    today: z.iso.date().openapi({ description: "Today in `timeZone`." }),
    weekStart: z.iso.date().openapi({ description: "The Monday this week starts on." }),
    clock: z.enum(CLOCKS).nullable().openapi({ description: "The person's clock; null follows the device." }),
    wakeTime: z.int().openapi({ description: "When their day starts, in minutes after midnight." }),
    sleepStart: z.int().openapi({ description: "When they go to sleep, in minutes after midnight (before wakeTime: after midnight)." }),
    blocks: z.array(PlanBlockSchema).openapi({
      description: "Every block this week and next, across goals, earliest first: for finding free time and giving time.",
    }),
    goals: z.array(PlanGoalSchema).openapi({ description: "Every goal, in their order." }),
  })
  .openapi("Plan");

const planRoute = createRoute({
  method: "get",
  path: "/plan",
  operationId: "getPlan",
  summary: "The planning board across goals: tasks, this week's done ones, objectives and session time",
  security: [{ bearerAuth: [] }],
  request: { query: z.object({ timeZone: timeZoneSchema.optional() }) },
  responses: {
    200: { description: "OK", content: { "application/json": { schema: PlanSchema } } },
    ...errorResponses,
  },
});

export const plan = new OpenAPIHono<ApiEnv>().openapi(planRoute, async (c) => {
  const userId = c.var.user.id;
  const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
  const zone = timeZone ?? "UTC";
  const today = todayIn(timeZone);
  const weekStart = weekStartOf(today);
  const weekBegins = startOfDayIn(weekStart, zone);
  const twoWeeksEnd = startOfDayIn(addDays(weekStart, 14), zone);
  const [list, open, done, schedules, blocks, objectives, settings] = await Promise.all([
    listGoals(userId),
    listOpenTasks(userId),
    listTasksDoneSince(userId, weekBegins),
    listTaskSchedules(userId),
    listBlocks(userId, weekBegins, twoWeeksEnd),
    listObjectivesBetween(userId, weekStart, weekStart),
    getSettings(userId),
  ]);
  const objectiveOf = new Map(objectives.map((row) => [row.goalId, row.objective]));
  return c.json(
    {
      today,
      weekStart,
      clock: settings.clock,
      wakeTime: settings.wakeTime,
      sleepStart: settings.sleepStart,
      blocks: blocks.map((block) => ({
        id: block.id,
        goalId: block.goalId,
        startsAt: block.startsAt.toISOString(),
        endsAt: block.endsAt.toISOString(),
        reserved: block.reserved,
        taskId: block.taskId,
      })),
      goals: list.map((goal) => ({
        id: goal.id,
        title: goal.title,
        icon: goal.icon,
        color: goal.color,
        objective: objectiveOf.get(goal.id) ?? null,
        tasks: open.filter((task) => task.goalId === goal.id).map((task) => asTask(task, schedules.get(task.id) ?? null)),
        done: done.filter((task) => task.goalId === goal.id).map((task) => asTask(task)),
        protectedBlocks: sessionBlocks(blocks, goal.id, weekBegins, twoWeeksEnd),
      })),
    },
    200,
  );
});
