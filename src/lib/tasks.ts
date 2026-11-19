import "server-only";

import { and, asc, desc, eq, gt, gte, inArray, isNotNull, isNull, max, min, sql } from "drizzle-orm";

import { db } from "@/db";
import { calendarBlocks, goals, goalTasks } from "@/db/schema";
import { createTaskDonePost, deleteTaskDonePosts } from "@/lib/posts";
import { getTimeZone } from "@/lib/settings";
import { todayIn, weekStartOf } from "@/lib/target-date";
import { resolvePlacement, weekProblem, type PlacementPatch } from "@/lib/task-horizon";
import { DEFAULT_TASK_MINUTES } from "@/lib/task-schema";

/*
 * Tasks on a goal. Same rule as everything else: every query filters on the
 * owner, and writes check the goal belongs to them.
 */

export type TaskDTO = {
  id: string;
  goalId: string;
  title: string;
  description: string | null;
  minutes: number;
  doneAt: Date | null;
  /** The day they mean to do it, "YYYY-MM-DD", if they've picked one. */
  plannedFor: string | null;
  /** The Monday of the week they mean to do it, if they've picked one (a planned day picks its week). */
  plannedWeek: string | null;
  /** The day it's due, "YYYY-MM-DD", if it has a deadline. */
  dueOn: string | null;
  createdAt: Date;
};

const columns = {
  id: goalTasks.id,
  goalId: goalTasks.goalId,
  title: goalTasks.title,
  description: goalTasks.description,
  minutes: goalTasks.minutes,
  doneAt: goalTasks.doneAt,
  plannedFor: goalTasks.plannedFor,
  plannedWeek: goalTasks.plannedWeek,
  dueOn: goalTasks.dueOn,
  createdAt: goalTasks.createdAt,
};

const mine = (userId: string, taskId: string) => and(eq(goalTasks.id, taskId), eq(goalTasks.userId, userId));

/** Open tasks in their order, then done ones, most recently finished first. */
export async function listTasks(userId: string, goalId: string): Promise<TaskDTO[]> {
  return db
    .select(columns)
    .from(goalTasks)
    .where(and(eq(goalTasks.goalId, goalId), eq(goalTasks.userId, userId)))
    .orderBy(sql`${goalTasks.doneAt} is not null`, desc(goalTasks.doneAt), asc(goalTasks.position), asc(goalTasks.createdAt));
}

/**
 * What a progress read needs: every open task in order, and tasks finished in
 * the last `days` days, most recent first.
 */
export async function listTasksForRead(userId: string, goalId: string, days: number) {
  const mineOnGoal = and(eq(goalTasks.goalId, goalId), eq(goalTasks.userId, userId));
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
  const [open, done] = await Promise.all([
    db
      .select(columns)
      .from(goalTasks)
      .where(and(mineOnGoal, isNull(goalTasks.doneAt)))
      .orderBy(asc(goalTasks.position), asc(goalTasks.createdAt))
      // Prompts list every planned task and count what's in Later past a few.
      .limit(200),
    db
      .select(columns)
      .from(goalTasks)
      .where(and(mineOnGoal, gte(goalTasks.doneAt, since)))
      .orderBy(desc(goalTasks.doneAt))
      .limit(30),
  ]);
  return { open, done };
}

export async function getTask(userId: string, taskId: string): Promise<TaskDTO | null> {
  const [task] = await db.select(columns).from(goalTasks).where(mine(userId, taskId));
  return task ?? null;
}

/** Every open task across the user's goals, in each goal's order. */
export async function listOpenTasks(userId: string): Promise<TaskDTO[]> {
  return db
    .select(columns)
    .from(goalTasks)
    .where(and(eq(goalTasks.userId, userId), isNull(goalTasks.doneAt)))
    .orderBy(asc(goalTasks.position), asc(goalTasks.createdAt));
}

/** When each of a goal's tasks is next on the calendar, for tasks that are. */
export async function listTaskSchedules(userId: string, goalId: string): Promise<Map<string, Date>> {
  const rows = await db
    .select({ taskId: calendarBlocks.taskId, next: min(calendarBlocks.startsAt) })
    .from(calendarBlocks)
    .where(
      and(
        eq(calendarBlocks.userId, userId),
        eq(calendarBlocks.goalId, goalId),
        isNotNull(calendarBlocks.taskId),
        gt(calendarBlocks.endsAt, new Date()),
      ),
    )
    .groupBy(calendarBlocks.taskId);
  return new Map(rows.filter((r) => r.taskId && r.next).map((r) => [r.taskId!, r.next!]));
}

/**
 * Checks a task off (or reopens it). Checking off posts a "Completed a task"
 * entry to the goal's activity; reopening takes it back. One entry per completion.
 */
export async function markTaskDone(userId: string, taskId: string, done: boolean): Promise<TaskDTO | null> {
  const task = await setTaskDone(userId, taskId, done);
  if (!task) return null;
  await deleteTaskDonePosts(userId, task.id);
  if (done) await createTaskDonePost(userId, task.goalId, task.id, task.title);
  return task;
}

/** A planned week that isn't this week or next. Its message is for the person. */
export class PlacementError extends Error {}

type Placed = Pick<TaskDTO, "plannedFor" | "plannedWeek">;

/** Applies a change to where a task is planned, against today in the person's time zone. */
async function applyPlacement(userId: string, current: Placed, patch: PlacementPatch): Promise<Placed> {
  const today = todayIn(await getTimeZone(userId));
  const problem = patch.plannedWeek ? weekProblem(patch.plannedWeek, today) : null;
  if (problem) throw new PlacementError(problem);
  return resolvePlacement(current, patch, today);
}

const touchesPlacement = (patch: PlacementPatch) => patch.plannedFor !== undefined || patch.plannedWeek !== undefined;

/**
 * Adds a task at the end of the goal's open tasks: not planned yet (Later) unless it's given a
 * day or a week. Throws PlacementError for a week that can't be planned for.
 */
export async function createTask(
  userId: string,
  goalId: string,
  title: string,
  extra: { minutes?: number; description?: string | null } & PlacementPatch = {},
): Promise<TaskDTO | null> {
  const [goal] = await db
    .select({ id: goals.id })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return null;
  const placed = touchesPlacement(extra)
    ? await applyPlacement(userId, { plannedFor: null, plannedWeek: null }, extra)
    : { plannedFor: null, plannedWeek: null };
  const [{ last }] = await db
    .select({ last: max(goalTasks.position) })
    .from(goalTasks)
    .where(and(eq(goalTasks.goalId, goalId), isNull(goalTasks.doneAt)));
  const [task] = await db
    .insert(goalTasks)
    .values({
      userId,
      goalId,
      title,
      minutes: extra.minutes ?? DEFAULT_TASK_MINUTES,
      description: extra.description ?? null,
      ...placed,
      position: (last ?? -1) + 1,
    })
    .returning(columns);
  return task;
}

/**
 * Puts a goal's open tasks in the given order. `ids` must be exactly the goal's
 * open tasks, so a list from a page that's out of date can't drop or invent any;
 * returns false when it isn't. Renumbers them 0…n in one statement.
 */
export async function reorderTasks(userId: string, goalId: string, ids: string[]): Promise<boolean> {
  const open = await db
    .select({ id: goalTasks.id })
    .from(goalTasks)
    .where(and(eq(goalTasks.userId, userId), eq(goalTasks.goalId, goalId), isNull(goalTasks.doneAt)));
  const openIds = new Set(open.map((t) => t.id));
  if (ids.length !== openIds.size || new Set(ids).size !== ids.length || !ids.every((id) => openIds.has(id))) return false;
  if (ids.length === 0) return true;
  const cases = sql.join(
    ids.map((id, i) => sql`when ${goalTasks.id} = ${id} then ${i}::integer`),
    sql` `,
  );
  await db
    .update(goalTasks)
    .set({ position: sql`case ${cases} end` })
    .where(and(eq(goalTasks.userId, userId), eq(goalTasks.goalId, goalId), inArray(goalTasks.id, ids)));
  return true;
}

/**
 * Changes a task. A new planned day or week keeps the two in step (see resolvePlacement);
 * throws PlacementError for a week that can't be planned for.
 */
export async function updateTask(
  userId: string,
  taskId: string,
  patch: Partial<Pick<TaskDTO, "title" | "description" | "minutes" | "plannedFor" | "plannedWeek" | "dueOn">>,
): Promise<TaskDTO | null> {
  const { plannedFor, plannedWeek, ...rest } = patch;
  let set: typeof patch = rest;
  if (touchesPlacement({ plannedFor, plannedWeek })) {
    const current = await getTask(userId, taskId);
    if (!current) return null;
    set = { ...rest, ...(await applyPlacement(userId, current, { plannedFor, plannedWeek })) };
  }
  const [task] = await db.update(goalTasks).set(set).where(mine(userId, taskId)).returning(columns);
  return task ?? null;
}

/**
 * Moves an open task: plans it for a day, a week or Later, and puts it just before `before`
 * among the goal's open tasks (or after all of them), in one go. "stale" when either task is
 * done or gone, or `before` is on another goal; throws PlacementError for a week that can't be
 * planned for.
 */
export async function placeTask(
  userId: string,
  taskId: string,
  patch: PlacementPatch,
  before?: string,
): Promise<TaskDTO | "not_found" | "stale"> {
  const current = await getTask(userId, taskId);
  if (!current) return "not_found";
  if (current.doneAt || before === taskId) return "stale";
  const placed = touchesPlacement(patch) ? await applyPlacement(userId, current, patch) : current;
  const open = await db
    .select({ id: goalTasks.id })
    .from(goalTasks)
    .where(and(eq(goalTasks.userId, userId), eq(goalTasks.goalId, current.goalId), isNull(goalTasks.doneAt)))
    .orderBy(asc(goalTasks.position), asc(goalTasks.createdAt));
  const ids = open.map((t) => t.id).filter((id) => id !== taskId);
  const at = before === undefined ? ids.length : ids.indexOf(before);
  if (at < 0) return "stale";
  ids.splice(at, 0, taskId);
  const cases = sql.join(
    ids.map((id, i) => sql`when ${goalTasks.id} = ${id} then ${i}::integer`),
    sql` `,
  );
  const [[task]] = await db.batch([
    db
      .update(goalTasks)
      .set({ plannedFor: placed.plannedFor, plannedWeek: placed.plannedWeek })
      .where(mine(userId, taskId))
      .returning(columns),
    db
      .update(goalTasks)
      .set({ position: sql`case ${cases} end` })
      .where(and(eq(goalTasks.userId, userId), eq(goalTasks.goalId, current.goalId), inArray(goalTasks.id, ids))),
  ]);
  return task ?? "not_found";
}

export async function setTaskDone(userId: string, taskId: string, done: boolean): Promise<TaskDTO | null> {
  const [task] = await db
    .update(goalTasks)
    .set({ doneAt: done ? new Date() : null })
    .where(mine(userId, taskId))
    .returning(columns);
  return task ?? null;
}

export async function deleteTask(userId: string, taskId: string): Promise<boolean> {
  const rows = await db.delete(goalTasks).where(mine(userId, taskId)).returning({ id: goalTasks.id });
  return rows.length > 0;
}

/**
 * A task given a time on the calendar is planned for that day: when its block is
 * made or moved, its planned day follows the block's start, in the person's own
 * time zone. Deleting the block leaves the planned day as it was.
 */
export async function planTaskForBlock(userId: string, block: { taskId: string | null; startsAt: Date }) {
  if (!block.taskId) return;
  const plannedFor = todayIn(await getTimeZone(userId), block.startsAt);
  await db.update(goalTasks).set({ plannedFor, plannedWeek: weekStartOf(plannedFor) }).where(mine(userId, block.taskId));
}
