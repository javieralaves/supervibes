import { addDays, daysUntil, weekStartOf } from "@/lib/target-date";

/*
 * Where an open task stands in the person's plan, worked out from its planned day and week
 * against today, so nothing has to roll over as days and weeks pass. Pure and client-safe.
 *
 * People plan at the precision they have: a day, a week (this one or next, never further),
 * or not yet (Later). A missed day falls back to its week; a week that's gone by carries
 * into this one, counting how many times it has.
 */

export type TaskGroup = "day" | "thisWeek" | "nextWeek" | "later";

export type TaskHorizon = {
  group: TaskGroup;
  /** Planned for a day that's gone by without it being done. */
  slipped: boolean;
  /** Weeks it has carried over from the week it was planned for; 0 when it hasn't. */
  carriedWeeks: number;
};

type Placed = { plannedFor: string | null; plannedWeek: string | null };

/** The Mondays starting this week and next, from today ("YYYY-MM-DD"). */
export function planningWeeks(today: string) {
  const thisWeek = weekStartOf(today);
  return { thisWeek, nextWeek: addDays(thisWeek, 7) };
}

export function taskHorizon(task: Placed, today: string): TaskHorizon {
  if (task.plannedFor && task.plannedFor >= today) return { group: "day", slipped: false, carriedWeeks: 0 };
  const { thisWeek, nextWeek } = planningWeeks(today);
  const week = task.plannedWeek ?? (task.plannedFor ? weekStartOf(task.plannedFor) : null);
  if (week && week <= thisWeek) {
    return { group: "thisWeek", slipped: task.plannedFor !== null, carriedWeeks: Math.round(daysUntil(thisWeek, week) / 7) };
  }
  if (week === nextWeek) return { group: "nextWeek", slipped: false, carriedWeeks: 0 };
  return { group: "later", slipped: false, carriedWeeks: 0 };
}

/**
 * A change to where a task is planned: `undefined` leaves a field as it is, `null` clears it.
 * `plannedWeek` may be any day of the week; it's kept as the week's Monday.
 */
export type PlacementPatch = { plannedFor?: string | null; plannedWeek?: string | null };

/**
 * Applies a placement change, keeping the day and week in step:
 * - Picking a day plans it for that day's week too.
 * - Clearing the day keeps the week, so it's still meant for that week (or Later, if it was further out than next week).
 * - Picking another week drops a day that isn't in it; clearing the week (with no day) moves it to Later.
 */
export function resolvePlacement(current: Placed, patch: PlacementPatch, today: string): Placed {
  if (patch.plannedFor) return { plannedFor: patch.plannedFor, plannedWeek: weekStartOf(patch.plannedFor) };
  const week = patch.plannedWeek === undefined ? undefined : patch.plannedWeek && weekStartOf(patch.plannedWeek);
  if (patch.plannedFor === null) {
    const kept = week !== undefined ? week : (current.plannedWeek ?? (current.plannedFor ? weekStartOf(current.plannedFor) : null));
    return { plannedFor: null, plannedWeek: kept && kept <= planningWeeks(today).nextWeek ? kept : null };
  }
  if (week === undefined) return current;
  if (week === null) return { plannedFor: null, plannedWeek: null };
  const day = current.plannedFor && weekStartOf(current.plannedFor) === week ? current.plannedFor : null;
  return { plannedFor: day, plannedWeek: week };
}

/** Why a week can't be planned for, or null when it can: only this week or next. */
export function weekProblem(week: string, today: string): string | null {
  const { thisWeek, nextWeek } = planningWeeks(today);
  const monday = weekStartOf(week);
  return monday === thisWeek || monday === nextWeek ? null : "Plan it for this week or next.";
}

/** The groups in plan order: days, then this week, next week and Later. */
export const TASK_GROUPS: readonly TaskGroup[] = ["day", "thisWeek", "nextWeek", "later"];

/**
 * Open tasks in plan order, each with where it stands: planned days soonest first, then this
 * week, next week and Later. Within a group they keep the order they came in (the person's).
 */
export function inPlanOrder<T extends Placed>(tasks: readonly T[], today: string): (T & { horizon: TaskHorizon })[] {
  // Array.prototype.sort is stable, so ties keep the person's order.
  return tasks
    .map((task) => ({ ...task, horizon: taskHorizon(task, today) }))
    .sort(
      (a, b) =>
        TASK_GROUPS.indexOf(a.horizon.group) - TASK_GROUPS.indexOf(b.horizon.group) ||
        (a.horizon.group === "day" ? a.plannedFor!.localeCompare(b.plannedFor!) : 0),
    );
}

/** For prompts: how many weeks a task has carried over, or "" when it hasn't. */
export function carriedForPrompt(horizon: TaskHorizon): string {
  const n = horizon.carriedWeeks;
  return n === 0 ? "" : `carried over from ${n === 1 ? "last week" : `${n} weeks ago`}, still not done`;
}
