import "server-only";

import { and, desc, eq } from "drizzle-orm";

import { db } from "@/db";
import { goalStatuses } from "@/db/schema";
import type { AiTrigger } from "@/lib/ai-usage";
import type { GoalStatus, Outlook, StatusBasis, StatusView } from "@/lib/status-schema";

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
