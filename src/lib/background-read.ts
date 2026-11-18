import "server-only";

import { and, eq } from "drizzle-orm";
import { after } from "next/server";

import { db } from "@/db";
import { goals } from "@/db/schema";
import { assessGoal, ProgressError } from "@/lib/progress";

/*
 * Progress reads that run after the response, so posting (or "Update status")
 * returns straight away and the page isn't held up: Next sends a page's server
 * actions one at a time, so a read awaited from the page would block every
 * action behind it for its 10–20 seconds.
 *
 * Each request stamps the goal. The read waits a moment and only runs if no
 * newer request has come in since, so a burst of posts makes one read, and the
 * last one covers everything before it. The stamp stays on the goal while the
 * read runs, which is how the goal page knows to show "Updating…".
 */

/** How long to wait for more posts before reading. */
const SETTLE_MS = 4_000;
/** A request older than this is taken to have died without finishing (reads cap at 300s). */
export const STALE_MS = 6 * 60_000;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Asks for a progress read of a goal in the background. Call it from a server
 * action that has already checked the goal belongs to the user. `settle: false`
 * starts straight away, for when the person asked for the read themselves.
 */
export async function requestRead(userId: string, goalId: string, { settle = true } = {}) {
  // Made here, not with now() in SQL, so it compares exactly once stored (milliseconds both ways).
  const stamp = new Date();
  const mine = and(eq(goals.id, goalId), eq(goals.userId, userId));
  await db.update(goals).set({ readRequestedAt: stamp, readError: null }).where(mine);

  after(async () => {
    if (settle) await sleep(SETTLE_MS);
    const [goal] = await db.select({ requestedAt: goals.readRequestedAt }).from(goals).where(mine);
    // A newer request will do the read, or the goal is gone.
    if (goal?.requestedAt?.getTime() !== stamp.getTime()) return;

    // Only clear the stamp if it's still ours; a request that came in mid-read gets its own read.
    const stillMine = and(mine, eq(goals.readRequestedAt, stamp));
    try {
      await assessGoal(userId, goalId);
      await db.update(goals).set({ readRequestedAt: null }).where(stillMine);
    } catch (error) {
      if (!(error instanceof ProgressError)) console.error("[progress] background read failed", error);
      const message = error instanceof ProgressError ? error.message : "Couldn't read progress. Try again.";
      await db.update(goals).set({ readRequestedAt: null, readError: message }).where(stillMine);
    }
  });
}

/** Where a goal's background read stands, for the goal page. */
export async function getReadStatus(
  userId: string,
  goalId: string,
): Promise<{ pending: boolean; error: string | null }> {
  const [goal] = await db
    .select({ requestedAt: goals.readRequestedAt, error: goals.readError })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return { pending: false, error: null };
  if (goal.requestedAt && Date.now() - goal.requestedAt.getTime() > STALE_MS) {
    return { pending: false, error: "The last update didn't finish. Try again." };
  }
  return { pending: goal.requestedAt !== null, error: goal.error };
}
