import "server-only";

import { and, asc, eq, gt, lt } from "drizzle-orm";

import { db } from "@/db";
import { calendarBlocks, goals, goalTasks } from "@/db/schema";
import type { BlockAgenda } from "@/lib/block-schema";

/*
 * Calendar blocks: intentions and protected time. Same rule as everything else:
 * every query filters on the owner, and writes check the goal belongs to them.
 */

export type BlockDTO = {
  id: string;
  goalId: string;
  title: string | null;
  startsAt: Date;
  endsAt: Date;
  keepOpen: boolean;
  fromSuggestion: string | null;
  /** The task this block schedules, making it an intention. */
  taskId: string | null;
  /** Whether that task is done; only filled when listing. */
  taskDone?: boolean;
  /** A plan for the session, if one has been prepared. */
  agenda: BlockAgenda | null;
};

const columns = {
  id: calendarBlocks.id,
  goalId: calendarBlocks.goalId,
  title: calendarBlocks.title,
  startsAt: calendarBlocks.startsAt,
  endsAt: calendarBlocks.endsAt,
  keepOpen: calendarBlocks.keepOpen,
  fromSuggestion: calendarBlocks.fromSuggestion,
  taskId: calendarBlocks.taskId,
  agenda: calendarBlocks.agenda,
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
    .select({ ...columns, taskDoneAt: goalTasks.doneAt })
    .from(calendarBlocks)
    .leftJoin(goalTasks, eq(goalTasks.id, calendarBlocks.taskId))
    .where(and(eq(calendarBlocks.userId, userId), gt(calendarBlocks.endsAt, from), lt(calendarBlocks.startsAt, to)))
    .orderBy(asc(calendarBlocks.startsAt));
  return rows.map(({ taskDoneAt, ...block }) => ({ ...block, taskDone: taskDoneAt !== null }));
}

/** Blocks from a week back to a few weeks ahead; the browser works out which day each is on. */
export function listBlocksAroundNow(userId: string) {
  const day = 24 * 60 * 60 * 1000;
  const now = Date.now();
  return listBlocks(userId, new Date(now - 8 * day), new Date(now + 40 * day));
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
    keepOpen: boolean;
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
  patch: Partial<Pick<BlockDTO, "goalId" | "title" | "keepOpen" | "startsAt" | "endsAt" | "agenda">>,
): Promise<BlockDTO | null> {
  if (patch.goalId && !(await ownsGoal(userId, patch.goalId))) return null;
  const [block] = await db.update(calendarBlocks).set(patch).where(mine(userId, blockId)).returning(columns);
  return block ?? null;
}

export async function deleteBlock(userId: string, blockId: string): Promise<boolean> {
  const rows = await db.delete(calendarBlocks).where(mine(userId, blockId)).returning({ id: calendarBlocks.id });
  return rows.length > 0;
}
