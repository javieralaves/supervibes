import type { GoalStatus, TrajectoryDay } from "./status-schema";
import { addDays, weekStartOf } from "./target-date";

/*
 * How a practice is going, counted from its sessions. Pure, so it can be tested on its own (practice-count.test.ts);
 * src/lib/practice.ts loads what it needs.
 *
 * The rules:
 * - A practice is meant to have `perWeek` sessions each week, Monday to Sunday in the person's own calendar.
 * - A session is a block for it on the calendar once its time has passed (unless the person said it didn't happen,
 *   or it's shorter than the practice's minimum), or one done off the calendar (logged, or ticked off on its day).
 *   Every one counts on its own, two in a day included.
 * - Its status looks back at the last 4 weeks it was meant to be kept: full weeks that started after it was made and
 *   weren't paused at any point. Each week counts up to `perWeek` sessions, so a busy week can't make up for a missed
 *   one. 75% of what was meant or more is on track, 50% or more at risk, less off track. With no such week yet
 *   there's no status.
 * - This week never counts against it until it's over, and a week that falls short just passes: nothing carries over.
 */

/** How many past weeks make a status. */
export const STATUS_WEEKS = 4;
/** How far back to look for those weeks, past paused ones. */
const LOOKBACK_WEEKS = 12;
const ON_TRACK = 0.75;
const AT_RISK = 0.5;

export type Rhythm = {
  perWeek: number;
  /** Blocks shorter than this don't count; null: any length. */
  minMinutes: number | null;
  /** The day it was made, in the person's calendar: weeks that started before it don't count. */
  createdOn: string;
};

/** A block for the practice, with its day (where it starts) in the person's calendar. */
export type PracticeBlock = { id: string; day: string; minutes: number; ended: boolean; missed: boolean };

/** A session off the calendar: planned for its day, or done. */
export type OffCalendarSession = { id: string; day: string; done: boolean };

export type Pause = { startsOn: string; resumesOn: string | null };

export type Inputs = {
  rhythm: Rhythm;
  blocks: PracticeBlock[];
  sessions: OffCalendarSession[];
  pauses: Pause[];
  /** Today, in the person's calendar. */
  today: string;
};

/**
 * A session's state: "done" counts; "planned" is still to come (a block not over yet, or one meant for today or
 * later); "missed" is a block the person said didn't happen; "short" is a block under the minimum; "lapsed" is one
 * meant for a day that's gone without being ticked off.
 */
export type SessionState = "done" | "planned" | "missed" | "short" | "lapsed";

export function blockState(block: PracticeBlock, rhythm: Pick<Rhythm, "minMinutes">): SessionState {
  if (!block.ended) return "planned";
  if (block.missed) return "missed";
  if (rhythm.minMinutes && block.minutes < rhythm.minMinutes) return "short";
  return "done";
}

export function offCalendarState(session: OffCalendarSession, today: string): SessionState {
  if (session.done) return "done";
  return session.day >= today ? "planned" : "lapsed";
}

/** Whether the practice is paused on `day`. */
export function pausedOn(pauses: Pause[], day: string): boolean {
  return pauses.some((p) => p.startsOn <= day && (p.resumesOn === null || day < p.resumesOn));
}

/** The pause covering `day`, if any. */
export function pauseOn(pauses: Pause[], day: string): Pause | null {
  return pauses.find((p) => p.startsOn <= day && (p.resumesOn === null || day < p.resumesOn)) ?? null;
}

/** Whether the practice was paused on any day of the week starting `weekStart`. */
export function weekPaused(pauses: Pause[], weekStart: string): boolean {
  const end = addDays(weekStart, 7);
  return pauses.some((p) => p.startsOn < end && (p.resumesOn === null || p.resumesOn > weekStart));
}

export type Week = {
  /** The Monday it starts on. */
  start: string;
  done: number;
  /** Still to come: only this week and later have any. */
  planned: number;
  /** Paused at any point, so it's left out of the status. */
  paused: boolean;
  /** It started before the practice was made, so it's left out of the status too. */
  beforeStart: boolean;
};

/** Sessions done and planned in the week starting `weekStart`. */
export function countWeek(inputs: Inputs, weekStart: string): Week {
  const end = addDays(weekStart, 7);
  const inWeek = (day: string) => day >= weekStart && day < end;
  let done = 0;
  let planned = 0;
  for (const block of inputs.blocks) {
    if (!inWeek(block.day)) continue;
    const state = blockState(block, inputs.rhythm);
    if (state === "done") done++;
    else if (state === "planned") planned++;
  }
  for (const session of inputs.sessions) {
    if (!inWeek(session.day)) continue;
    const state = offCalendarState(session, inputs.today);
    if (state === "done") done++;
    else if (state === "planned") planned++;
  }
  return {
    start: weekStart,
    done,
    planned,
    paused: weekPaused(inputs.pauses, weekStart),
    beforeStart: inputs.rhythm.createdOn > weekStart,
  };
}

export type PracticeStatus = {
  status: Exclude<GoalStatus, "unclear">;
  /** Sessions done in the weeks it looked at, each week counted up to perWeek. */
  done: number;
  /** What was meant in those weeks: perWeek × weeks. */
  expected: number;
  /** How many weeks it looked at, up to 4. */
  weeks: number;
};

/** The status as it stood during the week starting `weekStart`: from the weeks before it. Null with none to go on. */
export function statusBefore(inputs: Inputs, weekStart: string): PracticeStatus | null {
  const { perWeek } = inputs.rhythm;
  let done = 0;
  let weeks = 0;
  for (let back = 1; back <= LOOKBACK_WEEKS && weeks < STATUS_WEEKS; back++) {
    const week = countWeek(inputs, addDays(weekStart, -7 * back));
    if (week.beforeStart) break;
    if (week.paused) continue;
    done += Math.min(week.done, perWeek);
    weeks++;
  }
  if (weeks === 0) return null;
  const expected = perWeek * weeks;
  const share = done / expected;
  return { status: share >= ON_TRACK ? "on_track" : share >= AT_RISK ? "at_risk" : "off_track", done, expected, weeks };
}

/** "8 of the last 12": the status's reason, in a few words. */
export function statusReason(status: PracticeStatus): string {
  return `${status.done} of the last ${status.expected}`;
}

export type PracticeState = {
  week: Week & { left: number };
  /** Its status now; null with no full week to go on, or while it's paused. */
  status: PracticeStatus | null;
  /** The pause it's in today, if any. */
  paused: Pause | null;
  /** The last `history` full weeks, oldest first. */
  weeks: Week[];
};

/** How the practice stands today: this week, its status, and its recent weeks. */
export function practiceState(inputs: Inputs, history = 8): PracticeState {
  const thisWeek = weekStartOf(inputs.today);
  const week = countWeek(inputs, thisWeek);
  const paused = pauseOn(inputs.pauses, inputs.today);
  const weeks = Array.from({ length: history }, (_, i) => countWeek(inputs, addDays(thisWeek, -7 * (history - i))));
  return {
    week: { ...week, left: Math.max(0, inputs.rhythm.perWeek - week.done) },
    status: paused ? null : statusBefore(inputs, thisWeek),
    paused,
    weeks,
  };
}

/**
 * Its status day by day for the `days` ending today, as a goal's trajectory: each day the status as it stood that
 * week, none while paused or before there was a week to go on. Never carried: it's counted, not read.
 */
export function practiceTrajectory(inputs: Inputs, days: number): TrajectoryDay[] {
  const byWeek = new Map<string, PracticeStatus | null>();
  const out: TrajectoryDay[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = addDays(inputs.today, -i);
    const weekStart = weekStartOf(day);
    if (!byWeek.has(weekStart)) byWeek.set(weekStart, statusBefore(inputs, weekStart));
    const status = pausedOn(inputs.pauses, day) ? null : byWeek.get(weekStart)!;
    out.push({
      day,
      status: status?.status ?? null,
      basis: status ? "week" : null,
      reason: status ? statusReason(status) : null,
      carried: false,
    });
  }
  return out;
}
