import "server-only";

import { and, asc, desc, eq, gte, isNull, max, sql } from "drizzle-orm";

import { db } from "@/db";
import { goals, goalTasks } from "@/db/schema";
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
