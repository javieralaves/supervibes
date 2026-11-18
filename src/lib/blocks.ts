import "server-only";

import { and, asc, eq, gt, lt } from "drizzle-orm";

import { db } from "@/db";
import { calendarBlocks, goalPosts, goals, goalTasks } from "@/db/schema";
import type { BlockAgenda } from "@/lib/block-schema";
import { AUTO_STALE_MS, autoRecapExpired, type BlockRecap, type PostedRecap } from "@/lib/recap-schema";

/*
 * Calendar blocks: intentions and protected time. Same rule as everything else:
 * every query filters on the owner, and writes check the goal belongs to them.
 */

export type BlockDTO = {
  id: string;
  goalId: string;
  title: string | null;
  /** For protected time: what the person wants out of the session. */
  description: string | null;
  startsAt: Date;
  endsAt: Date;
  fromSuggestion: string | null;
  /** The task this block schedules, making it an intention. */
  taskId: string | null;
  /** Whether that task is done; only filled when listing. */
  taskDone?: boolean;
  /** A plan for the session, if one has been prepared. */
  agenda: BlockAgenda | null;
  /** A draft recap of the session, until it's posted or discarded. */
  recap: BlockRecap | null;
  /** The recap posted to the goal's activity, if there is one; only filled when listing. */
  recapPost?: PostedRecap | null;
  /** Whether a recap is drafting itself in the background right now; only filled when listing. */
  recapDrafting?: boolean;
};

const columns = {
  id: calendarBlocks.id,
  goalId: calendarBlocks.goalId,
  title: calendarBlocks.title,
  description: calendarBlocks.description,
  startsAt: calendarBlocks.startsAt,
  endsAt: calendarBlocks.endsAt,
  fromSuggestion: calendarBlocks.fromSuggestion,
  taskId: calendarBlocks.taskId,
  agenda: calendarBlocks.agenda,
  recap: calendarBlocks.recap,
};

const mine = (userId: string, blockId: string) =>
  and(eq(calendarBlocks.id, blockId), eq(calendarBlocks.userId, userId));

async function ownsGoal(userId: string, goalId: string) {
  const [goal] = await db
    .select({ id: goals.id })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  return Boolean(goal);
}

/** Blocks overlapping [from, to), with whether each one's task is done. */
export async function listBlocks(userId: string, from: Date, to: Date): Promise<BlockDTO[]> {
  const rows = await db
    .select({
      ...columns,
      taskDoneAt: goalTasks.doneAt,
      recapPostId: goalPosts.id,
      recapBody: goalPosts.body,
      recapBreadcrumbs: goalPosts.breadcrumbs,
      autoRecap: calendarBlocks.autoRecap,
      updatedAt: calendarBlocks.updatedAt,
    })
    .from(calendarBlocks)
    .leftJoin(goalTasks, eq(goalTasks.id, calendarBlocks.taskId))
    .leftJoin(goalPosts, eq(goalPosts.blockId, calendarBlocks.id))
    .where(and(eq(calendarBlocks.userId, userId), gt(calendarBlocks.endsAt, from), lt(calendarBlocks.startsAt, to)))
    .orderBy(asc(calendarBlocks.startsAt));
  const now = Date.now();
  return rows.map(({ taskDoneAt, recapPostId, recapBody, recapBreadcrumbs, autoRecap, updatedAt, ...block }) => ({
    ...block,
    // A draft that wrote itself and sat unposted too long is on its way out; don't show it meanwhile.
    recap: autoRecapExpired(block.recap, block.endsAt) ? null : block.recap,
    taskDone: taskDoneAt !== null,
    recapPost: recapPostId !== null ? { body: recapBody ?? "", breadcrumbs: recapBreadcrumbs ?? [] } : null,
    recapDrafting: autoRecap === "drafting" && now - updatedAt.getTime() < AUTO_STALE_MS,
  }));
}

/** How far back and ahead the calendar can step with what it has loaded, in days. */
export const CALENDAR_DAYS_BACK = 36;
export const CALENDAR_DAYS_AHEAD = 42;

/** Blocks from about five weeks back to six ahead; the browser works out which day each is on. */
export function listBlocksAroundNow(userId: string) {
  const day = 24 * 60 * 60 * 1000;
  const now = Date.now();
  return listBlocks(userId, new Date(now - CALENDAR_DAYS_BACK * day), new Date(now + CALENDAR_DAYS_AHEAD * day));
}

/** A goal's blocks that haven't ended yet, soonest first. */
export async function listUpcomingBlocks(userId: string, goalId: string, limit = 30): Promise<BlockDTO[]> {
  return db
    .select(columns)
    .from(calendarBlocks)
    .where(
      and(eq(calendarBlocks.userId, userId), eq(calendarBlocks.goalId, goalId), gt(calendarBlocks.endsAt, new Date())),
    )
    .orderBy(asc(calendarBlocks.startsAt))
    .limit(limit);
}

export async function createBlock(
  userId: string,
  input: {
    goalId: string;
    title: string | null;
    startsAt: Date;
    endsAt: Date;
    fromSuggestion?: string | null;
    taskId?: string | null;
  },
): Promise<BlockDTO | null> {
  if (!(await ownsGoal(userId, input.goalId))) return null;
  const [block] = await db
    .insert(calendarBlocks)
    .values({ userId, ...input, fromSuggestion: input.fromSuggestion ?? null, taskId: input.taskId ?? null })
    .returning(columns);
  return block;
}

export async function getBlock(userId: string, blockId: string): Promise<BlockDTO | null> {
  const [block] = await db.select(columns).from(calendarBlocks).where(mine(userId, blockId));
  return block ?? null;
}

export async function updateBlock(
  userId: string,
  blockId: string,
  patch: Partial<Pick<BlockDTO, "goalId" | "title" | "description" | "startsAt" | "endsAt" | "agenda" | "recap">>,
): Promise<BlockDTO | null> {
  if (patch.goalId && !(await ownsGoal(userId, patch.goalId))) return null;
  const [block] = await db.update(calendarBlocks).set(patch).where(mine(userId, blockId)).returning(columns);
  return block ?? null;
}

export async function deleteBlock(userId: string, blockId: string): Promise<boolean> {
  const rows = await db.delete(calendarBlocks).where(mine(userId, blockId)).returning({ id: calendarBlocks.id });
  return rows.length > 0;
}
