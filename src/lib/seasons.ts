import "server-only";

import { and, asc, count, desc, eq, inArray, lt, ne } from "drizzle-orm";

import { db } from "@/db";
import { areas, goals, questGoals, quests, seasons, type GapAuthor, type Season, type SeasonState } from "@/db/schema";
import {
  defaultSeason,
  MAX_QUESTS,
  overlaps,
  START_MESSAGES,
  startProblem,
  type GapInput,
  type SeasonInput,
} from "@/lib/season-schema";
import { addDays } from "@/lib/target-date";

/*
 * Data access for seasons, their quests and the goals that move them, and for an area's gap. As everywhere else,
 * every function takes the owner's id and filters on it. The rules that need no database live in season-schema.ts.
 *
 * A season's state is stored, but "ended" is reached by date: an active season whose last day has gone by is settled
 * to ended on the next read (settleEnded), so nothing runs on a timer.
 */

export type SeasonDTO = Pick<Season, "id" | "name" | "startsOn" | "endsOn" | "state" | "startedAt">;

export type QuestDTO = {
  id: string;
  seasonId: string;
  areaId: string;
  title: string;
  fromText: string;
  reach: number;
  chosen: boolean;
  position: number;
  /** The goals that move it, oldest link first. */
  goalIds: string[];
};

/** A problem with a season or quest change, with a message for the person and a code for the app. */
export class SeasonError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

const SEASON_GONE = "That season doesn’t exist anymore.";
const QUEST_GONE = "That quest doesn’t exist anymore.";

const seasonColumns = {
  id: seasons.id,
  name: seasons.name,
  startsOn: seasons.startsOn,
  endsOn: seasons.endsOn,
  state: seasons.state,
  startedAt: seasons.startedAt,
};

const questColumns = {
  id: quests.id,
  seasonId: quests.seasonId,
  areaId: quests.areaId,
  title: quests.title,
  fromText: quests.fromText,
  reach: quests.reach,
  chosen: quests.chosen,
  position: quests.position,
};

/** Turns active seasons whose last day is before `today` into ended ones. */
export async function settleEnded(userId: string, today: string): Promise<void> {
  await db
    .update(seasons)
    .set({ state: "ended" })
    .where(and(eq(seasons.userId, userId), eq(seasons.state, "active"), lt(seasons.endsOn, today)));
}

/** How long Life keeps saying a season ended, before it's just the past. */
const ENDED_SHOWN_DAYS = 28;

/** The person's running season, the one they're setting up, and one that ended in the last four weeks. */
export async function getSeasons(
  userId: string,
  today: string,
): Promise<{ active: SeasonDTO | null; draft: SeasonDTO | null; ended: SeasonDTO | null }> {
  await settleEnded(userId, today);
  const rows = await db.select(seasonColumns).from(seasons).where(eq(seasons.userId, userId)).orderBy(desc(seasons.endsOn));
  const since = addDays(today, -ENDED_SHOWN_DAYS);
  return {
    active: rows.find((s) => s.state === "active") ?? null,
    draft: rows.find((s) => s.state === "draft") ?? null,
    ended: rows.find((s) => s.state === "ended" && s.endsOn >= since) ?? null,
  };
}

/** One of the person's seasons, or null. */
export async function getSeason(userId: string, seasonId: string): Promise<SeasonDTO | null> {
  const [row] = await db
    .select(seasonColumns)
    .from(seasons)
    .where(and(eq(seasons.id, seasonId), eq(seasons.userId, userId)));
  return row ?? null;
}

/** Throws when `days` would share a day with another of the person's seasons. */
async function assertNoOverlap(userId: string, days: { startsOn: string; endsOn: string }, except?: string) {
  const others = await db
    .select({ name: seasons.name, startsOn: seasons.startsOn, endsOn: seasons.endsOn })
    .from(seasons)
    .where(except ? and(eq(seasons.userId, userId), ne(seasons.id, except)) : eq(seasons.userId, userId));
  const clash = others.find((other) => overlaps(days, other));
  if (clash) throw new SeasonError("season_overlap", `Those days overlap ${clash.name}. Pick days after it ends.`);
}

/**
 * Makes the person's draft: by default from the Monday after today (or after a running season ends) for 13 weeks.
 * There's at most one draft at a time.
 */
export async function createDraft(userId: string, today: string, input?: SeasonInput): Promise<SeasonDTO> {
  const { active, draft } = await getSeasons(userId, today);
  if (draft) throw new SeasonError("draft_exists", "You’re already setting up a season. Pick up where you left off.");
  const days = input ?? defaultSeason(active && active.endsOn > today ? active.endsOn : today);
  await assertNoOverlap(userId, days);
  const [row] = await db
    .insert(seasons)
    .values({ userId, ...days, state: "draft" })
    .returning(seasonColumns);
  return row;
}

/**
 * Renames a season or moves its days. A draft can change anything; a running season keeps its first day; an ended one
 * stays as it was.
 */
export async function updateSeason(userId: string, seasonId: string, input: SeasonInput): Promise<SeasonDTO> {
  const season = await getSeason(userId, seasonId);
  if (!season) throw new SeasonError("not_found", SEASON_GONE);
  if (season.state === "ended") throw new SeasonError("season_ended", "That season has ended, so it stays as it was.");
  if (season.state === "active" && input.startsOn !== season.startsOn) {
    throw new SeasonError("season_started", "A season that’s running keeps its first day. You can still move its last.");
  }
  await assertNoOverlap(userId, input, seasonId);
  const [row] = await db
    .update(seasons)
    .set(input)
    .where(and(eq(seasons.id, seasonId), eq(seasons.userId, userId)))
    .returning(seasonColumns);
  return row;
}

/** Drops a draft and everything set up in it. Returns whether one was dropped; a started season can't be. */
export async function deleteDraft(userId: string, seasonId: string): Promise<boolean> {
  const deleted = await db
    .delete(seasons)
    .where(and(eq(seasons.id, seasonId), eq(seasons.userId, userId), eq(seasons.state, "draft")))
    .returning({ id: seasons.id });
  return deleted.length > 0;
}

/** A season's quests, chosen first in their order, then the rest in their areas' order, each with its goals. */
export async function listQuests(userId: string, seasonId: string): Promise<QuestDTO[]> {
  const [rows, links] = await Promise.all([
    db
      .select({ ...questColumns, areaPosition: areas.position })
      .from(quests)
      .innerJoin(areas, eq(areas.id, quests.areaId))
      .where(and(eq(quests.seasonId, seasonId), eq(quests.userId, userId))),
    db
      .select({ questId: questGoals.questId, goalId: questGoals.goalId })
      .from(questGoals)
      .where(and(eq(questGoals.seasonId, seasonId), eq(questGoals.userId, userId)))
      .orderBy(asc(questGoals.createdAt)),
  ]);
  const goalsOf = new Map<string, string[]>();
  for (const link of links) goalsOf.set(link.questId, [...(goalsOf.get(link.questId) ?? []), link.goalId]);
  return rows
    .sort((a, b) => Number(b.chosen) - Number(a.chosen) || (a.chosen ? a.position - b.position : a.areaPosition - b.areaPosition))
    .map((row) => ({
      id: row.id,
      seasonId: row.seasonId,
      areaId: row.areaId,
      title: row.title,
      fromText: row.fromText,
      reach: row.reach,
      chosen: row.chosen,
      position: row.position,
      goalIds: goalsOf.get(row.id) ?? [],
    }));
}

/** One of the person's quests with its season, or null. */
export async function getQuest(userId: string, questId: string): Promise<{ quest: QuestDTO; season: SeasonDTO } | null> {
  const [row] = await db
    .select({ seasonId: quests.seasonId })
    .from(quests)
    .where(and(eq(quests.id, questId), eq(quests.userId, userId)));
  if (!row) return null;
  const season = await getSeason(userId, row.seasonId);
  const quest = (await listQuests(userId, row.seasonId)).find((q) => q.id === questId);
  return season && quest ? { quest, season } : null;
}

/**
 * Writes or replaces the draft's candidate quest for an area, as the stand read names it: the area's first quest in
 * the season if it has one, keeping whether it's chosen, or a new one. (An area can hold several quests; the stand read
 * only ever writes one.)
 */
export async function upsertCandidate(
  userId: string,
  seasonId: string,
  areaId: string,
  words: { title: string; fromText: string; reach: number },
): Promise<string> {
  const [existing] = await db
    .select({ id: quests.id })
    .from(quests)
    .where(and(eq(quests.seasonId, seasonId), eq(quests.areaId, areaId), eq(quests.userId, userId)))
    .orderBy(asc(quests.createdAt))
    .limit(1);
  if (existing) {
    await db.update(quests).set(words).where(eq(quests.id, existing.id));
    return existing.id;
  }
  return createQuest(userId, seasonId, areaId, words);
}

/** A new quest in an area, however many it has already. */
export async function createQuest(
  userId: string,
  seasonId: string,
  areaId: string,
  words: { title: string; fromText: string; reach: number },
): Promise<string> {
  const [row] = await db.insert(quests).values({ userId, seasonId, areaId, ...words }).returning({ id: quests.id });
  return row.id;
}

/**
 * Edits a quest's words, or chooses it for the season (in a draft only): up to three, numbered in the order chosen.
 */
export async function updateQuest(
  userId: string,
  questId: string,
  change: { title?: string; fromText?: string; chosen?: boolean },
): Promise<void> {
  const found = await getQuest(userId, questId);
  if (!found) throw new SeasonError("not_found", QUEST_GONE);
  const { quest, season } = found;
  if (season.state === "ended") throw new SeasonError("season_ended", "That season has ended, so its quests stay as they were.");

  const set: Partial<typeof quests.$inferInsert> = {};
  if (change.title !== undefined) set.title = change.title;
  if (change.fromText !== undefined) set.fromText = change.fromText;
  if (change.chosen !== undefined && change.chosen !== quest.chosen) {
    if (season.state !== "draft") throw new SeasonError("season_started", "A running season keeps its quests.");
    if (change.chosen) {
      const [{ chosen }] = await db
        .select({ chosen: count() })
        .from(quests)
        .where(and(eq(quests.seasonId, season.id), eq(quests.chosen, true)));
      if (chosen >= MAX_QUESTS) throw new SeasonError("too_many_quests", START_MESSAGES.too_many_quests);
      set.chosen = true;
      set.position = chosen + 1;
    } else {
      set.chosen = false;
      set.position = 0;
    }
  }
  if (Object.keys(set).length === 0) return;
  await db
    .update(quests)
    .set(set)
    .where(and(eq(quests.id, questId), eq(quests.userId, userId)));
  // Close the gap a quest left in the order, so the chosen stay numbered 1, 2, 3.
  if (set.chosen === false) await renumber(userId, season.id);
}

async function renumber(userId: string, seasonId: string) {
  const chosen = await db
    .select({ id: quests.id })
    .from(quests)
    .where(and(eq(quests.seasonId, seasonId), eq(quests.userId, userId), eq(quests.chosen, true)))
    .orderBy(asc(quests.position));
  await Promise.all(chosen.map((q, i) => db.update(quests).set({ position: i + 1 }).where(eq(quests.id, q.id))));
}

/**
 * Sets the goals that move a quest. A goal moves one quest a season, so one linked here leaves any other quest of the
 * same season.
 */
export async function setQuestGoals(userId: string, questId: string, goalIds: string[]): Promise<void> {
  const found = await getQuest(userId, questId);
  if (!found) throw new SeasonError("not_found", QUEST_GONE);
  const { season } = found;
  if (season.state === "ended") throw new SeasonError("season_ended", "That season has ended, so its quests stay as they were.");

  const ids = [...new Set(goalIds)];
  if (ids.length > 0) {
    const mine = await db
      .select({ id: goals.id })
      .from(goals)
      .where(and(eq(goals.userId, userId), inArray(goals.id, ids)));
    if (mine.length !== ids.length) throw new SeasonError("invalid_request", "One of those projects or practices doesn’t exist anymore.");
  }

  await db.delete(questGoals).where(and(eq(questGoals.questId, questId), eq(questGoals.userId, userId)));
  if (ids.length === 0) return;
  await db
    .delete(questGoals)
    .where(and(eq(questGoals.seasonId, season.id), eq(questGoals.userId, userId), inArray(questGoals.goalId, ids)));
  await db.insert(questGoals).values(ids.map((goalId) => ({ userId, seasonId: season.id, questId, goalId })));
}

/**
 * Starts a draft: one to three chosen quests, each with a goal, on days that overlap no other season, and no other
 * season running. The quests that weren't chosen are dropped.
 */
export async function startSeason(userId: string, seasonId: string, today: string): Promise<SeasonDTO> {
  const season = await getSeason(userId, seasonId);
  if (!season) throw new SeasonError("not_found", SEASON_GONE);
  if (season.state !== "draft") throw new SeasonError("season_started", "That season has already started.");
  const { active } = await getSeasons(userId, today);
  if (active) throw new SeasonError("season_running", `${active.name} is still running. Start this one once it ends.`);
  if (season.endsOn < today) throw new SeasonError("season_past", "Those days have gone by. Move the season to days ahead.");
  await assertNoOverlap(userId, season, seasonId);

  const chosen = (await listQuests(userId, seasonId)).filter((q) => q.chosen);
  const problem = startProblem(chosen.map((q) => ({ goalCount: q.goalIds.length })));
  if (problem) throw new SeasonError(problem, START_MESSAGES[problem]);

  await db.delete(quests).where(and(eq(quests.seasonId, seasonId), eq(quests.userId, userId), eq(quests.chosen, false)));
  const [row] = await db
    .update(seasons)
    .set({ state: "active" satisfies SeasonState, startedAt: new Date() })
    .where(and(eq(seasons.id, seasonId), eq(seasons.userId, userId)))
    .returning(seasonColumns);
  return row;
}

/**
 * For each of the person's goals, the quest it moves in the running season, if any. A goal with no entry moves none,
 * or there's no season running.
 */
export async function questOfGoals(userId: string, seasonId: string | null): Promise<Map<string, string>> {
  if (!seasonId) return new Map();
  const links = await db
    .select({ goalId: questGoals.goalId, questId: questGoals.questId })
    .from(questGoals)
    .where(and(eq(questGoals.seasonId, seasonId), eq(questGoals.userId, userId)));
  return new Map(links.map((l) => [l.goalId, l.questId]));
}

export type GapDTO = { title: string; body: string; by: GapAuthor; at: Date };

/** An area's gap, or null until it's named. */
export async function getGap(userId: string, areaId: string): Promise<GapDTO | null> {
  const [row] = await db
    .select({ title: areas.gapTitle, body: areas.gapBody, by: areas.gapBy, at: areas.gapAt })
    .from(areas)
    .where(and(eq(areas.id, areaId), eq(areas.userId, userId)));
  return asGap(row);
}

/** The gaps of all the person's areas that have one, by area. */
export async function listGaps(userId: string): Promise<Map<string, GapDTO>> {
  const rows = await db
    .select({ id: areas.id, title: areas.gapTitle, body: areas.gapBody, by: areas.gapBy, at: areas.gapAt })
    .from(areas)
    .where(eq(areas.userId, userId));
  const out = new Map<string, GapDTO>();
  for (const row of rows) {
    const gap = asGap(row);
    if (gap) out.set(row.id, gap);
  }
  return out;
}

function asGap(row: { title: string | null; body: string | null; by: GapAuthor | null; at: Date | null } | undefined): GapDTO | null {
  if (!row?.title || !row.by || !row.at) return null;
  return { title: row.title, body: row.body ?? "", by: row.by, at: row.at };
}

/** Names or rewrites an area's gap. Returns it, or null if the area isn't the person's. */
export async function setGap(userId: string, areaId: string, gap: GapInput, by: GapAuthor): Promise<GapDTO | null> {
  const [row] = await db
    .update(areas)
    .set({ gapTitle: gap.title, gapBody: gap.body, gapBy: by, gapAt: new Date() })
    .where(and(eq(areas.id, areaId), eq(areas.userId, userId)))
    .returning({ title: areas.gapTitle, body: areas.gapBody, by: areas.gapBy, at: areas.gapAt });
  return asGap(row);
}
