import "server-only";

import { and, asc, eq } from "drizzle-orm";

import { db } from "@/db";
import { connections, goals, goalSources } from "@/db/schema";
import { goalColumns } from "@/lib/goals";
import { isProvider, type ProviderKey } from "@/lib/providers";
import type { SourceInput } from "@/lib/source-schema";

/*
 * Goal sources. Same rule as goals: every query filters on the
 * owner, and writes check that the goal and connection belong to them too.
 */

export async function getGoal(userId: string, goalId: string) {
  const [goal] = await db
    .select(goalColumns)
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  return goal ?? null;
}

export type SourceDTO = {
  id: string;
  connectionId: string;
  provider: ProviderKey;
  relation: string;
  enabled: boolean;
  lastError: string | null;
};

export async function listSources(userId: string, goalId: string): Promise<SourceDTO[]> {
  const rows = await db
    .select({
      id: goalSources.id,
      connectionId: goalSources.connectionId,
      provider: connections.provider,
      relation: goalSources.relation,
      enabled: goalSources.enabled,
      lastError: goalSources.lastError,
    })
    .from(goalSources)
    .innerJoin(connections, eq(connections.id, goalSources.connectionId))
    .where(and(eq(goalSources.goalId, goalId), eq(goalSources.userId, userId)))
    .orderBy(asc(goalSources.createdAt));
  return rows.filter((r): r is SourceDTO => isProvider(r.provider));
}

async function ownsConnection(userId: string, connectionId: string) {
  const [row] = await db
    .select({ id: connections.id })
    .from(connections)
    .where(and(eq(connections.id, connectionId), eq(connections.userId, userId)));
  return Boolean(row);
}

export async function createSource(userId: string, goalId: string, input: SourceInput) {
  if (!(await getGoal(userId, goalId)) || !(await ownsConnection(userId, input.connectionId))) return null;
  const [row] = await db.insert(goalSources).values({ ...input, userId, goalId }).returning({ id: goalSources.id });
  return row;
}

export async function updateSource(userId: string, sourceId: string, input: SourceInput) {
  if (!(await ownsConnection(userId, input.connectionId))) return null;
  const [row] = await db
    .update(goalSources)
    .set(input)
    .where(and(eq(goalSources.id, sourceId), eq(goalSources.userId, userId)))
    .returning({ id: goalSources.id });
  return row ?? null;
}

export async function deleteSource(userId: string, sourceId: string) {
  const rows = await db
    .delete(goalSources)
    .where(and(eq(goalSources.id, sourceId), eq(goalSources.userId, userId)))
    .returning({ id: goalSources.id });
  return rows.length > 0;
}
