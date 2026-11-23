import { taskHorizon } from "@/lib/task-horizon";
import { addDays, weekStartOf } from "@/lib/target-date";

/*
 * A goal's week as Goals home shows it on its card: its session time this week, its reserved time,
 * and what's planned against the sessions. The same totals as the planning board's This week ring
 * (Capacity.week in the Mac app): planned is the open estimates meant for this week plus the
 * session time that has already gone by, counted as spent on the goal. Reserved time is kept for
 * its own sake, so it's never room for tasks. Pure and client-safe.
 */

type Task = { goalId: string; minutes: number; plannedFor: string | null; plannedWeek: string | null };
type Block = { goalId: string; startsAt: Date; endsAt: Date; reserved: boolean };

export type GoalWeekLoad = {
  /** Session time this week, gone by or not: room for tasks. */
  sessionMinutes: number;
  /** Reserved time this week. */
  reservedMinutes: number;
  /** Open estimates meant for this week, plus the session time already gone by. */
  plannedMinutes: number;
};

/**
 * The Monday of the week an open task is meant for, if any: the week of a day it's planned for
 * (today or later), or its week, with a week gone by carried into this one. Mirrors
 * BoardColumn.week(of:) in the Mac app.
 */
export function taskWeek(task: Pick<Task, "plannedFor" | "plannedWeek">, today: string): string | null {
  if (task.plannedFor && task.plannedFor >= today) return weekStartOf(task.plannedFor);
  const { group } = taskHorizon(task, today);
  if (group === "thisWeek") return weekStartOf(today);
  if (group === "nextWeek") return addDays(weekStartOf(today), 7);
  return null;
}

const minutesBetween = (from: number, to: number) => Math.max(0, Math.round((to - from) / 60_000));

/**
 * Each goal's load this week. `tasks` are open tasks; `blocks` any that overlap the week (they're
 * clipped to it, so one running over Sunday midnight counts only its part). `week` is the week's
 * bounds in the person's time zone.
 */
export function goalWeekLoads(
  goalIds: readonly string[],
  tasks: readonly Task[],
  blocks: readonly Block[],
  week: { start: Date; end: Date },
  today: string,
  now: Date,
): Map<string, GoalWeekLoad> {
  const thisWeek = weekStartOf(today);
  const loads = new Map<string, GoalWeekLoad>(goalIds.map((id) => [id, { sessionMinutes: 0, reservedMinutes: 0, plannedMinutes: 0 }]));

  for (const block of blocks) {
    const load = loads.get(block.goalId);
    if (!load) continue;
    const start = Math.max(block.startsAt.getTime(), week.start.getTime());
    const end = Math.min(block.endsAt.getTime(), week.end.getTime());
    if (start >= end) continue;
    if (block.reserved) {
      load.reservedMinutes += minutesBetween(start, end);
    } else {
      load.sessionMinutes += minutesBetween(start, end);
      // Under way, a session counts as spent up to now.
      load.plannedMinutes += minutesBetween(start, Math.min(end, now.getTime()));
    }
  }

  for (const task of tasks) {
    const load = loads.get(task.goalId);
    if (load && taskWeek(task, today) === thisWeek) load.plannedMinutes += task.minutes;
  }

  return loads;
}
