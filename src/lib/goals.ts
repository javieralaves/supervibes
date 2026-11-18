import "server-only";

import { and, asc, count, eq, max } from "drizzle-orm";

import { db } from "@/db";
import { goals, type Goal } from "@/db/schema";
import { MAX_GOALS, type GoalInput } from "@/lib/goal-schema";

/*
 * Data access for goals. Every function takes the owner's id and filters on it,
 * including updates and deletes, so one user can never read or change another's
 * goals even with a guessed id. Callers get userId from requireUser(), never
 * from the client.
 */

export type GoalDTO = Pick<Goal, "id" | "title" | "description" | "targetDate" | "icon" | "color" | "position">;

export const goalColumns = {
  id: goals.id,
  title: goals.title,
  description: goals.description,
  targetDate: goals.targetDate,
  icon: goals.icon,
  color: goals.color,
  position: goals.position,
};

export async function listGoals(userId: string): Promise<GoalDTO[]> {
  return db
    .select(goalColumns)
    .from(goals)
    .where(eq(goals.userId, userId))
    .orderBy(asc(goals.position), asc(goals.createdAt));
}

export class GoalLimitError extends Error {}

export async function createGoal(userId: string, input: GoalInput): Promise<GoalDTO> {
  const [{ total, last }] = await db
    .select({ total: count(), last: max(goals.position) })
    .from(goals)
    .where(eq(goals.userId, userId));

  if (total >= MAX_GOALS) throw new GoalLimitError();

  const [goal] = await db
    .insert(goals)
    .values({ ...input, userId, position: (last ?? -1) + 1 })
    .returning(goalColumns);
  return goal;
}

/** Returns the updated goal, or null if it doesn't exist or isn't this user's. */
export async function updateGoal(
  userId: string,
  goalId: string,
  input: GoalInput,
): Promise<GoalDTO | null> {
  const [goal] = await db
    .update(goals)
    .set(input)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)))
    .returning(goalColumns);
  return goal ?? null;
}

/** Returns whether a goal was deleted. */
export async function deleteGoal(userId: string, goalId: string): Promise<boolean> {
  const deleted = await db
    .delete(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)))
    .returning({ id: goals.id });
  return deleted.length > 0;
}
