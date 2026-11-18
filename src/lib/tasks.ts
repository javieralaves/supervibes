import "server-only";

import { and, asc, desc, eq, gt, gte, inArray, isNotNull, isNull, max, min, sql } from "drizzle-orm";

import { db } from "@/db";
import { calendarBlocks, goals, goalTasks } from "@/db/schema";
import { createTaskDonePost, deleteTaskDonePosts } from "@/lib/posts";
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
  createdAt: Date;
};

const columns = {
  id: goalTasks.id,
  goalId: goalTasks.goalId,
  title: goalTasks.title,
  description: goalTasks.description,
  minutes: goalTasks.minutes,
  doneAt: goalTasks.doneAt,
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
      .limit(50),
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

/** Adds a task at the end of the goal's open tasks. */
export async function createTask(
  userId: string,
  goalId: string,
  title: string,
  extra: { minutes?: number; description?: string | null } = {},
): Promise<TaskDTO | null> {
  const [goal] = await db
    .select({ id: goals.id })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return null;
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

export async function updateTask(
  userId: string,
  taskId: string,
  patch: { title?: string; description?: string | null; minutes?: number },
): Promise<TaskDTO | null> {
  const [task] = await db.update(goalTasks).set(patch).where(mine(userId, taskId)).returning(columns);
  return task ?? null;
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
