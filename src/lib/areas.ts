import "server-only";

import { and, asc, count, eq, inArray, max } from "drizzle-orm";

import { db } from "@/db";
import { areas, goals, type Area } from "@/db/schema";
import { MAX_AREAS, type AreaInput } from "@/lib/area-schema";

/*
 * Data access for areas. As with goals (src/lib/goals.ts), every function takes the owner's id and filters on it,
 * including updates and deletes, and a goal can only be placed in an area of its own owner's.
 */

export type AreaDTO = Pick<Area, "id" | "name" | "icon" | "now" | "want" | "position">;

const areaColumns = {
  id: areas.id,
  name: areas.name,
  icon: areas.icon,
  now: areas.now,
  want: areas.want,
  position: areas.position,
};

export async function listAreas(userId: string): Promise<AreaDTO[]> {
  return db
    .select(areaColumns)
    .from(areas)
    .where(eq(areas.userId, userId))
    .orderBy(asc(areas.position), asc(areas.createdAt));
}

/** The area, or null if it doesn't exist or isn't this user's. */
export async function getArea(userId: string, areaId: string): Promise<AreaDTO | null> {
  const [area] = await db
    .select(areaColumns)
    .from(areas)
    .where(and(eq(areas.id, areaId), eq(areas.userId, userId)));
  return area ?? null;
}

export class AreaLimitError extends Error {}

export async function createArea(userId: string, input: AreaInput): Promise<AreaDTO> {
  const [{ total, last }] = await db
    .select({ total: count(), last: max(areas.position) })
    .from(areas)
    .where(eq(areas.userId, userId));

  if (total >= MAX_AREAS) throw new AreaLimitError();

  const [area] = await db
    .insert(areas)
    .values({ ...input, userId, position: (last ?? -1) + 1 })
    .returning(areaColumns);
  return area;
}

/** Returns the updated area, or null if it doesn't exist or isn't this user's. */
export async function updateArea(userId: string, areaId: string, input: AreaInput): Promise<AreaDTO | null> {
  const [area] = await db
    .update(areas)
    .set(input)
    .where(and(eq(areas.id, areaId), eq(areas.userId, userId)))
    .returning(areaColumns);
  return area ?? null;
}

/** Returns whether an area was removed. Its goals stay, with no area (the foreign key sets theirs to null). */
export async function deleteArea(userId: string, areaId: string): Promise<boolean> {
  const deleted = await db
    .delete(areas)
    .where(and(eq(areas.id, areaId), eq(areas.userId, userId)))
    .returning({ id: areas.id });
  return deleted.length > 0;
}

/**
 * Puts the person's areas in the given order. The ids must be exactly their areas, each once; returns false
 * otherwise, changing nothing.
 */
export async function reorderAreas(userId: string, ids: string[]): Promise<boolean> {
  const mine = await db.select({ id: areas.id }).from(areas).where(eq(areas.userId, userId));
  const given = new Set(ids);
  if (given.size !== ids.length || ids.length !== mine.length || !mine.every((a) => given.has(a.id))) return false;
  await Promise.all(
    ids.map((id, position) =>
      db
        .update(areas)
        .set({ position })
        .where(and(eq(areas.id, id), eq(areas.userId, userId))),
    ),
  );
  return true;
}

export type SetGoalAreaResult = "ok" | "goal_not_found" | "area_not_found";

/** Places a goal in one of the person's areas, or takes it out of its area with null. */
export async function setGoalArea(userId: string, goalId: string, areaId: string | null): Promise<SetGoalAreaResult> {
  if (areaId && !(await getArea(userId, areaId))) return "area_not_found";
  const updated = await db
    .update(goals)
    .set({ areaId })
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)))
    .returning({ id: goals.id });
  return updated.length > 0 ? "ok" : "goal_not_found";
}

/** Whether every given area id is one of this person's: for creating a goal in an area. */
export async function ownsAreas(userId: string, areaIds: string[]): Promise<boolean> {
  if (areaIds.length === 0) return true;
  const found = await db
    .select({ id: areas.id })
    .from(areas)
    .where(and(eq(areas.userId, userId), inArray(areas.id, areaIds)));
  return found.length === new Set(areaIds).size;
}
