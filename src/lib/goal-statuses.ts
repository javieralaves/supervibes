import "server-only";

import { and, asc, desc, eq, gte, inArray, lt } from "drizzle-orm";

import { db } from "@/db";
import { goalStatuses } from "@/db/schema";
import type { AiTrigger } from "@/lib/ai-usage";
import {
  buildTrajectory,
  TRAJECTORY_DAYS,
  type GoalStatus,
  type Outlook,
  type StatusBasis,
  type StatusView,
  type TrajectoryDay,
} from "@/lib/status-schema";
import { addDays, todayIn } from "@/lib/target-date";

/* A goal's statuses over time, one per progress read. Every query filters on the owner. */

const columns = {
  status: goalStatuses.status,
  basis: goalStatuses.basis,
  reason: goalStatuses.reason,
  outlook: goalStatuses.outlook,
  createdAt: goalStatuses.createdAt,
};

type Row = { status: GoalStatus; basis: StatusBasis; reason: string; outlook: Outlook | null; createdAt: Date };
const toView = (r: Row): StatusView => ({ ...r, at: r.createdAt.toISOString() });

/** The goal's most recent statuses, newest first. */
export async function listStatuses(userId: string, goalId: string, limit: number): Promise<StatusView[]> {
  const rows = await db
    .select(columns)
    .from(goalStatuses)
    .where(and(eq(goalStatuses.goalId, goalId), eq(goalStatuses.userId, userId)))
    .orderBy(desc(goalStatuses.createdAt))
    .limit(limit);
  return rows.map(toView);
}

/** The goal's latest status, or null before its first read with one. */
export async function getLatestStatus(userId: string, goalId: string): Promise<StatusView | null> {
  const [latest] = await listStatuses(userId, goalId, 1);
  return latest ?? null;
}

/** Records the status a read came to. */
export async function recordStatus(
  userId: string,
  goalId: string,
  status: { status: GoalStatus; basis: StatusBasis; reason: string; outlook: Outlook | null },
  trigger: AiTrigger,
) {
  await db.insert(goalStatuses).values({ userId, goalId, ...status, trigger });
}

/**
 * Each goal's trajectory over the last few weeks, day by day in the person's own
 * calendar (see buildTrajectory), with how many reads it rests on.
 */
export async function listTrajectories(
  userId: string,
  goalIds: string[],
  timeZone: string | null,
  days = TRAJECTORY_DAYS,
): Promise<Map<string, { days: TrajectoryDay[]; reads: number }>> {
  const out = new Map<string, { days: TrajectoryDay[]; reads: number }>();
  if (goalIds.length === 0) return out;
  const today = todayIn(timeZone);
  // A day early, so the window's first day in any time zone is covered; days outside it are dropped.
  const since = new Date(`${addDays(today, -days)}T00:00:00Z`);
  const mine = and(eq(goalStatuses.userId, userId), inArray(goalStatuses.goalId, goalIds));

  const [inWindow, before] = await Promise.all([
    db
      .select({ goalId: goalStatuses.goalId, ...columns })
      .from(goalStatuses)
      .where(and(mine, gte(goalStatuses.createdAt, since)))
      .orderBy(asc(goalStatuses.createdAt)),
    // Each goal's last status before the window, to carry into it.
    db
      .selectDistinctOn([goalStatuses.goalId], { goalId: goalStatuses.goalId, ...columns })
      .from(goalStatuses)
      .where(and(mine, lt(goalStatuses.createdAt, since)))
      .orderBy(goalStatuses.goalId, desc(goalStatuses.createdAt)),
  ]);

  for (const goalId of goalIds) {
    const rows = inWindow
      .filter((r) => r.goalId === goalId)
      .map((r) => ({ ...r, day: todayIn(timeZone, r.createdAt), at: r.createdAt.toISOString() }));
    const prior = before.find((r) => r.goalId === goalId) ?? null;
    out.set(goalId, { days: buildTrajectory(rows, prior, today, days), reads: rows.length });
  }
  return out;
}
