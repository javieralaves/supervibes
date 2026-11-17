import { eq } from "drizzle-orm";

import { db } from "@/db";
import { goalSources } from "@/db/schema";
import { tryMatchBlockFits } from "@/lib/blocks";
import { assessGoal } from "@/lib/progress";

export const maxDuration = 300;

/** Stop starting new reads after this long, so the function finishes cleanly. */
const BUDGET_MS = 220_000;

/**
 * Daily progress read for every goal that has at least one enabled source.
 * Called by Vercel Cron, which sends `Authorization: Bearer $CRON_SECRET`.
 */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const started = Date.now();
  const goals = await db
    .selectDistinct({ goalId: goalSources.goalId, userId: goalSources.userId })
    .from(goalSources)
    .where(eq(goalSources.enabled, true));

  let read = 0;
  let failed = 0;
  let skipped = 0;
  for (const goal of goals) {
    if (Date.now() - started > BUDGET_MS) {
      skipped++;
      continue;
    }
    try {
      await assessGoal(goal.userId, goal.goalId);
      await tryMatchBlockFits(goal.userId, goal.goalId);
      read++;
    } catch (error) {
      failed++;
      console.error(`[cron] progress read for goal ${goal.goalId} failed`, error);
    }
  }

  return Response.json({ read, failed, skipped });
}
