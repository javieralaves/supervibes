import "server-only";

import { and, asc, count, eq, inArray, max, sql } from "drizzle-orm";

import { db } from "@/db";
import { goals, type Goal, type GoalKind } from "@/db/schema";
import { MAX_GOALS, type GoalInput, type PracticeFields } from "@/lib/goal-schema";

/*
 * Data access for goals. Every function takes the owner's id and filters on it,
 * including updates and deletes, so one user can never read or change another's
 * goals even with a guessed id. Callers get userId from requireUser(), never
 * from the client.
 */

export type GoalDTO = Pick<
  Goal,
  "id" | "title" | "description" | "targetDate" | "icon" | "color" | "position" | "areaId" | "kind" | "perWeek" | "minMinutes" | "autoRecaps" | "createdAt"
>;

export const goalColumns = {
  id: goals.id,
  title: goals.title,
  description: goals.description,
  targetDate: goals.targetDate,
  icon: goals.icon,
  color: goals.color,
  position: goals.position,
  areaId: goals.areaId,
  kind: goals.kind,
  perWeek: goals.perWeek,
  minMinutes: goals.minMinutes,
  autoRecaps: goals.autoRecaps,
  createdAt: goals.createdAt,
};

export async function listGoals(userId: string): Promise<GoalDTO[]> {
  return db
    .select(goalColumns)
    .from(goals)
    .where(eq(goals.userId, userId))
    .orderBy(asc(goals.position), asc(goals.createdAt));
}

/** For what only a project has (tasks, week objectives, progress reads), asked of a practice. */
export class PracticeError extends Error {}

export const NO_TASKS = "A practice doesn’t have tasks: it’s how often, not what’s left.";

export class GoalLimitError extends Error {
  constructor(readonly kind: GoalKind) {
    super(`You can have up to ${MAX_GOALS} ${kind === "practice" ? "practices" : "projects"}.`);
  }
}

/**
 * Adds a goal, in an area when one is given: a project, or a practice when `practice` gives how often it's meant to
 * happen. A practice has no target date. The caller checks the area is the person's own (ownsAreas in
 * src/lib/areas.ts).
 */
export async function createGoal(
  userId: string,
  input: GoalInput,
  areaId: string | null = null,
  practice: (PracticeFields & { perWeek: number }) | null = null,
): Promise<GoalDTO> {
  const kind: GoalKind = practice ? "practice" : "project";
  const [[{ total }], [{ last }]] = await Promise.all([
    db.select({ total: count() }).from(goals).where(and(eq(goals.userId, userId), eq(goals.kind, kind))),
    db.select({ last: max(goals.position) }).from(goals).where(eq(goals.userId, userId)),
  ]);

  // No limit in practice (MAX_GOALS is far out of reach); kept as a backstop against runaway loops.
  if (total >= MAX_GOALS) throw new GoalLimitError(kind);

  const [goal] = await db
    .insert(goals)
    .values({
      ...input,
      userId,
      areaId,
      position: (last ?? -1) + 1,
      kind,
      ...(practice && {
        targetDate: null,
        perWeek: practice.perWeek,
        minMinutes: practice.minMinutes || null,
        autoRecaps: practice.autoRecaps ?? true,
      }),
    })
    .returning(goalColumns);
  return goal;
}

/**
 * Returns the updated goal, or null if it doesn't exist or isn't this user's. A practice keeps no target date, and
 * takes its own fields from `practice`: what's left out stays as it is. A project ignores them, but for autoRecaps.
 */
export async function updateGoal(
  userId: string,
  goalId: string,
  input: GoalInput,
  practice: PracticeFields = {},
): Promise<GoalDTO | null> {
  const mine = and(eq(goals.id, goalId), eq(goals.userId, userId));
  const [current] = await db.select({ kind: goals.kind }).from(goals).where(mine);
  if (!current) return null;
  const isPractice = current.kind === "practice";
  const [goal] = await db
    .update(goals)
    .set({
      ...input,
      ...(practice.autoRecaps !== undefined && { autoRecaps: practice.autoRecaps }),
      ...(isPractice && {
        targetDate: null,
        ...(practice.perWeek !== undefined && { perWeek: practice.perWeek }),
        ...(practice.minMinutes !== undefined && { minMinutes: practice.minMinutes || null }),
      }),
    })
    .where(mine)
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

/**
 * When each goal last moved, as the goal cards say "7h ago": the later of its latest progress read and its newest
 * note (a recap or a checked-off task posts one too), or when it was made if it has neither. Not goals.updatedAt,
 * which also changes when a read is asked for or fails. Goals not found are left out.
 */
export async function listGoalUpdatedAt(userId: string, goalIds: string[]): Promise<Map<string, Date>> {
  if (goalIds.length === 0) return new Map();
  const rows = await db
    .select({
      id: goals.id,
      // Spelled out with aliases: inside a raw snippet Drizzle leaves columns unqualified, so the subqueries'
      // "goals.id" would read as their own table's id and never match.
      updatedAt: sql<Date>`coalesce(
        greatest(
          (select max(p.created_at) from goal_posts p where p.goal_id = "goals"."id"),
          (select r.created_at from goal_reads r where r.goal_id = "goals"."id")
        ),
        "goals"."created_at"
      )`.mapWith(goals.createdAt),
    })
    .from(goals)
    .where(and(eq(goals.userId, userId), inArray(goals.id, goalIds)));
  return new Map(rows.map((row) => [row.id, row.updatedAt]));
}
