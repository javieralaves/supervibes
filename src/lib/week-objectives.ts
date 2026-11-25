import "server-only";

import { and, desc, eq, gte, inArray, lte } from "drizzle-orm";

import { db } from "@/db";
import { goals, goalWeeks } from "@/db/schema";
import { PracticeError } from "@/lib/goals";

/*
 * Weekly objectives: what a week should move for a goal. Optional; one per goal
 * per week. Same rule as everything else: every query filters on the owner.
 */

export type WeekObjective = { weekStart: string; objective: string };

/** The goal's objectives for the given weeks, by week start. */
export async function getWeekObjectives(userId: string, goalId: string, weekStarts: string[]): Promise<Map<string, string>> {
  if (weekStarts.length === 0) return new Map();
  const rows = await db
    .select({ weekStart: goalWeeks.weekStart, objective: goalWeeks.objective })
    .from(goalWeeks)
    .where(and(eq(goalWeeks.userId, userId), eq(goalWeeks.goalId, goalId), inArray(goalWeeks.weekStart, weekStarts)));
  return new Map(rows.map((r) => [r.weekStart, r.objective]));
}

/** The goal's objectives for weeks up to and including `weekStart`, newest first. */
export async function listWeekObjectives(
  userId: string,
  goalId: string,
  weekStart: string,
  limit: number,
): Promise<WeekObjective[]> {
  return db
    .select({ weekStart: goalWeeks.weekStart, objective: goalWeeks.objective })
    .from(goalWeeks)
    .where(and(eq(goalWeeks.userId, userId), eq(goalWeeks.goalId, goalId), lte(goalWeeks.weekStart, weekStart)))
    .orderBy(desc(goalWeeks.weekStart))
    .limit(limit);
}

/** Every goal's objectives for weeks starting between `from` and `to`, inclusive. For the week view. */
export async function listObjectivesBetween(
  userId: string,
  from: string,
  to: string,
): Promise<(WeekObjective & { goalId: string })[]> {
  return db
    .select({ goalId: goalWeeks.goalId, weekStart: goalWeeks.weekStart, objective: goalWeeks.objective })
    .from(goalWeeks)
    .where(and(eq(goalWeeks.userId, userId), gte(goalWeeks.weekStart, from), lte(goalWeeks.weekStart, to)));
}

/**
 * Sets a week's objective for a goal, or clears it with null. False if the goal isn't theirs. Throws PracticeError for
 * a practice: its week is a count, not an objective.
 */
export async function setWeekObjective(
  userId: string,
  goalId: string,
  weekStart: string,
  objective: string | null,
): Promise<boolean> {
  const [goal] = await db
    .select({ id: goals.id, kind: goals.kind })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return false;
  if (goal.kind === "practice") throw new PracticeError("A practice’s week is how many times, not an objective.");
  const week = and(eq(goalWeeks.userId, userId), eq(goalWeeks.goalId, goalId), eq(goalWeeks.weekStart, weekStart));
  if (objective === null) {
    await db.delete(goalWeeks).where(week);
    return true;
  }
  await db
    .insert(goalWeeks)
    .values({ userId, goalId, weekStart, objective })
    .onConflictDoUpdate({ target: [goalWeeks.goalId, goalWeeks.weekStart], set: { objective } });
  return true;
}
