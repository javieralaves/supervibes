import "server-only";

import { and, asc, eq, gte, inArray, isNull, lt, or } from "drizzle-orm";

import { db } from "@/db";
import { calendarBlocks, goals, practicePauses, practiceSessions } from "@/db/schema";
import {
  blockState,
  offCalendarState,
  practiceState,
  practiceTrajectory,
  type Inputs,
  type PracticeState,
  type SessionState,
} from "@/lib/practice-count";
import type { TrajectoryDay } from "@/lib/status-schema";
import { addDays, todayIn, weekStartOf } from "@/lib/target-date";
import { startOfDayIn } from "@/lib/zoned-day";

/*
 * Practices: goals kept up a number of times a week (goals.kind = "practice"). This loads a practice's sessions and
 * pauses and hands them to practice-count.ts, which does the counting. Every query filters on the owner.
 */

/** What a practice is, as the counting needs it. */
export type PracticeGoal = { id: string; perWeek: number | null; minMinutes: number | null; createdAt: Date };

/** How far back to load: the 28-day trajectory's first week, then the 12 weeks its status can look back over. */
const LOAD_WEEKS_BACK = 18;

/** One session of a practice, on the calendar or off it, as its page lists them. */
export type PracticeSessionView = {
  id: string;
  /** "block": a block on the calendar; "day": one off the calendar, planned for its day or done. */
  source: "block" | "day";
  day: string;
  state: SessionState;
  /** For a block: its title (null: the practice's own), and its times. */
  title: string | null;
  startsAt: Date | null;
  endsAt: Date | null;
};

type Loaded = { inputs: Inputs; sessions: PracticeSessionView[] };

/** Loads each practice's blocks, sessions and pauses from `LOAD_WEEKS_BACK` weeks ago to the end of next week. */
async function load(userId: string, practices: PracticeGoal[], timeZone: string | null, now = new Date()): Promise<Map<string, Loaded>> {
  const out = new Map<string, Loaded>();
  if (practices.length === 0) return out;
  const zone = timeZone ?? "UTC";
  const today = todayIn(timeZone, now);
  const from = addDays(weekStartOf(today), -7 * LOAD_WEEKS_BACK);
  const to = addDays(weekStartOf(today), 14);
  const ids = practices.map((p) => p.id);

  const [blocks, sessions, pauses] = await Promise.all([
    db
      .select({
        id: calendarBlocks.id,
        goalId: calendarBlocks.goalId,
        title: calendarBlocks.title,
        startsAt: calendarBlocks.startsAt,
        endsAt: calendarBlocks.endsAt,
        missed: calendarBlocks.missed,
      })
      .from(calendarBlocks)
      .where(
        and(
          eq(calendarBlocks.userId, userId),
          inArray(calendarBlocks.goalId, ids),
          gte(calendarBlocks.startsAt, startOfDayIn(from, zone)),
          lt(calendarBlocks.startsAt, startOfDayIn(to, zone)),
        ),
      )
      .orderBy(asc(calendarBlocks.startsAt)),
    db
      .select({ id: practiceSessions.id, goalId: practiceSessions.goalId, day: practiceSessions.day, doneAt: practiceSessions.doneAt })
      .from(practiceSessions)
      .where(
        and(
          eq(practiceSessions.userId, userId),
          inArray(practiceSessions.goalId, ids),
          gte(practiceSessions.day, from),
          lt(practiceSessions.day, to),
        ),
      )
      .orderBy(asc(practiceSessions.day), asc(practiceSessions.createdAt)),
    db
      .select({ goalId: practicePauses.goalId, startsOn: practicePauses.startsOn, resumesOn: practicePauses.resumesOn })
      .from(practicePauses)
      .where(
        and(
          eq(practicePauses.userId, userId),
          inArray(practicePauses.goalId, ids),
          or(isNull(practicePauses.resumesOn), gte(practicePauses.resumesOn, from)),
        ),
      ),
  ]);

  for (const practice of practices) {
    const rhythm = {
      perWeek: practice.perWeek ?? 1,
      minMinutes: practice.minMinutes,
      createdOn: todayIn(timeZone, practice.createdAt),
    };
    const itsBlocks = blocks
      .filter((b) => b.goalId === practice.id)
      .map((b) => ({
        ...b,
        day: todayIn(timeZone, b.startsAt),
        minutes: Math.round((b.endsAt.getTime() - b.startsAt.getTime()) / 60_000),
        ended: b.endsAt <= now,
      }));
    const itsSessions = sessions.filter((s) => s.goalId === practice.id).map((s) => ({ id: s.id, day: s.day, done: s.doneAt !== null }));
    const inputs: Inputs = {
      rhythm,
      blocks: itsBlocks,
      sessions: itsSessions,
      pauses: pauses.filter((p) => p.goalId === practice.id).map(({ startsOn, resumesOn }) => ({ startsOn, resumesOn })),
      today,
    };
    const views: PracticeSessionView[] = [
      ...itsBlocks.map((b) => ({
        id: b.id,
        source: "block" as const,
        day: b.day,
        state: blockState(b, rhythm),
        title: b.title,
        startsAt: b.startsAt,
        endsAt: b.endsAt,
      })),
      ...itsSessions.map((s) => ({
        id: s.id,
        source: "day" as const,
        day: s.day,
        state: offCalendarState(s, today),
        title: null,
        startsAt: null,
        endsAt: null,
      })),
    ].toSorted((a, b) => a.day.localeCompare(b.day) || (a.startsAt?.getTime() ?? 0) - (b.startsAt?.getTime() ?? 0));
    out.set(practice.id, { inputs, sessions: views });
  }
  return out;
}

/** Each practice's trajectory: its counted status day by day, for the `days` ending today. */
export async function listPracticeTrajectories(
  userId: string,
  practices: PracticeGoal[],
  timeZone: string | null,
  days: number,
): Promise<Map<string, TrajectoryDay[]>> {
  const loaded = await load(userId, practices, timeZone);
  return new Map([...loaded].map(([id, { inputs }]) => [id, practiceTrajectory(inputs, days)]));
}

/** How each practice stands today: this week, its status, its last weeks and whether it's paused. */
export async function listPracticeStates(
  userId: string,
  practices: PracticeGoal[],
  timeZone: string | null,
): Promise<Map<string, PracticeState>> {
  const loaded = await load(userId, practices, timeZone);
  return new Map([...loaded].map(([id, { inputs }]) => [id, practiceState(inputs)]));
}

/** One practice's state, with its sessions from the first of its last weeks to the end of next week. */
export async function getPracticeDetail(userId: string, practice: PracticeGoal, timeZone: string | null) {
  const loaded = (await load(userId, [practice], timeZone)).get(practice.id);
  if (!loaded) return null;
  const state = practiceState(loaded.inputs);
  const since = state.weeks[0]?.start ?? weekStartOf(loaded.inputs.today);
  return { state, sessions: loaded.sessions.filter((s) => s.day >= since) };
}

/** The practice, if it's this person's and a practice. */
export async function getPractice(userId: string, goalId: string): Promise<PracticeGoal | null> {
  const [row] = await db
    .select({ id: goals.id, perWeek: goals.perWeek, minMinutes: goals.minMinutes, createdAt: goals.createdAt })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId), eq(goals.kind, "practice")));
  return row ?? null;
}

// MARK: - Sessions off the calendar

export type OffCalendarDTO = { id: string; day: string; doneAt: Date | null };

/** Every practice's sessions off the calendar from `from` to `to` (days, "YYYY-MM-DD", `to` not included). */
export async function listPracticeSessionsBetween(userId: string, from: string, to: string) {
  return db
    .select({ id: practiceSessions.id, goalId: practiceSessions.goalId, day: practiceSessions.day, doneAt: practiceSessions.doneAt })
    .from(practiceSessions)
    .where(and(eq(practiceSessions.userId, userId), gte(practiceSessions.day, from), lt(practiceSessions.day, to)))
    .orderBy(asc(practiceSessions.day), asc(practiceSessions.createdAt));
}

const sessionColumns = { id: practiceSessions.id, day: practiceSessions.day, doneAt: practiceSessions.doneAt };

/** Adds one: planned for `day`, or done (logged) when `done`. Null when the practice isn't theirs. */
export async function addPracticeSession(userId: string, goalId: string, day: string, done: boolean): Promise<OffCalendarDTO | null> {
  if (!(await getPractice(userId, goalId))) return null;
  const [row] = await db
    .insert(practiceSessions)
    .values({ userId, goalId, day, doneAt: done ? new Date() : null })
    .returning(sessionColumns);
  return row;
}

export class FutureSessionError extends Error {}

/**
 * Moves one to another day, or ticks it off or back. Null when it isn't theirs. Throws FutureSessionError for ticking
 * off one whose day hasn't come yet.
 */
export async function updatePracticeSession(
  userId: string,
  goalId: string,
  sessionId: string,
  patch: { day?: string; done?: boolean },
  today?: string,
): Promise<OffCalendarDTO | null> {
  const mine = and(eq(practiceSessions.id, sessionId), eq(practiceSessions.goalId, goalId), eq(practiceSessions.userId, userId));
  if (patch.done && today) {
    const [current] = await db.select({ day: practiceSessions.day }).from(practiceSessions).where(mine);
    if (!current) return null;
    if ((patch.day ?? current.day) > today) throw new FutureSessionError("It can’t be done on a day that hasn’t come yet.");
  }
  const [row] = await db
    .update(practiceSessions)
    .set({
      ...(patch.day !== undefined && { day: patch.day }),
      ...(patch.done !== undefined && { doneAt: patch.done ? new Date() : null }),
    })
    .where(and(eq(practiceSessions.id, sessionId), eq(practiceSessions.goalId, goalId), eq(practiceSessions.userId, userId)))
    .returning(sessionColumns);
  return row ?? null;
}

export async function deletePracticeSession(userId: string, goalId: string, sessionId: string): Promise<boolean> {
  const deleted = await db
    .delete(practiceSessions)
    .where(and(eq(practiceSessions.id, sessionId), eq(practiceSessions.goalId, goalId), eq(practiceSessions.userId, userId)))
    .returning({ id: practiceSessions.id });
  return deleted.length > 0;
}

// MARK: - Pausing

/**
 * Pauses a practice from today until `resumesOn` (the day it picks up again), or until it's resumed when null. If it's
 * already paused, that pause takes the new end instead. Returns false when the practice isn't theirs.
 */
export async function pausePractice(userId: string, goalId: string, today: string, resumesOn: string | null): Promise<boolean> {
  if (!(await getPractice(userId, goalId))) return false;
  const current = await currentPause(userId, goalId, today);
  if (current) {
    await db.update(practicePauses).set({ resumesOn }).where(eq(practicePauses.id, current.id));
  } else {
    await db.insert(practicePauses).values({ userId, goalId, startsOn: today, resumesOn });
  }
  return true;
}

/** Picks a paused practice up again today. A pause that started today is dropped. False when it isn't theirs. */
export async function resumePractice(userId: string, goalId: string, today: string): Promise<boolean> {
  if (!(await getPractice(userId, goalId))) return false;
  const current = await currentPause(userId, goalId, today);
  if (!current) return true;
  if (current.startsOn >= today) await db.delete(practicePauses).where(eq(practicePauses.id, current.id));
  else await db.update(practicePauses).set({ resumesOn: today }).where(eq(practicePauses.id, current.id));
  return true;
}

async function currentPause(userId: string, goalId: string, today: string) {
  const rows = await db
    .select({ id: practicePauses.id, startsOn: practicePauses.startsOn, resumesOn: practicePauses.resumesOn })
    .from(practicePauses)
    .where(and(eq(practicePauses.userId, userId), eq(practicePauses.goalId, goalId), or(isNull(practicePauses.resumesOn), gte(practicePauses.resumesOn, addDays(today, 1)))));
  // A pause set to start later is still the one to change.
  return rows.find((p) => p.startsOn <= today) ?? rows[0] ?? null;
}

// MARK: - Blocks that didn't happen

export class MissedError extends Error {}

/**
 * Says a practice's block did or didn't happen. Only for a practice's block that's over. Null when the block isn't
 * theirs; throws MissedError when it isn't a practice's or hasn't ended.
 */
export async function setBlockMissed(userId: string, blockId: string, missed: boolean, now = new Date()) {
  const [block] = await db
    .select({ id: calendarBlocks.id, endsAt: calendarBlocks.endsAt, kind: goals.kind })
    .from(calendarBlocks)
    .innerJoin(goals, eq(goals.id, calendarBlocks.goalId))
    .where(and(eq(calendarBlocks.id, blockId), eq(calendarBlocks.userId, userId)));
  if (!block) return null;
  if (block.kind !== "practice") throw new MissedError("Only a practice’s sessions can be marked as not having happened.");
  if (block.endsAt > now) throw new MissedError("It hasn’t happened yet.");
  await db.update(calendarBlocks).set({ missed }).where(eq(calendarBlocks.id, blockId));
  return { id: block.id, missed };
}
