import * as z from "zod";

import { GOAL_ICON_NAMES } from "@/lib/goal-icons";
import type { GoalStatus } from "@/lib/status-schema";

/** Soft cap: a handful of areas is the point. Setup suggests four to seven. */
export const MAX_AREAS = 12;
export const MAX_AREA_NAME = 40;
/** Where you are and where you're going: a few sentences each. */
export const MAX_AREA_WORDS = 600;

const words = (label: string) =>
  z
    .string()
    .trim()
    .max(MAX_AREA_WORDS, `Keep ${label} under ${MAX_AREA_WORDS} characters.`)
    .nullish()
    .transform((v) => v || null);

/**
 * An area as the person edits it, whole: a name and an icon, and optionally where they are and where they're going.
 * Left out or blank words are stored as null, as a goal's description is.
 */
export const areaInputSchema = z.object({
  name: z
    .string()
    .trim()
    .min(1, "Give the area a name.")
    .max(MAX_AREA_NAME, `Keep the name under ${MAX_AREA_NAME} characters.`),
  /** Areas share the goals' icons (src/lib/goal-icons.ts). */
  icon: z.enum(GOAL_ICON_NAMES),
  now: words("where you are"),
  want: words("where you're going"),
});

export type AreaInput = z.infer<typeof areaInputSchema>;

/*
 * An area's status is its goals' statuses rolled up, with no read of its own: the worst of them, so one goal at risk
 * makes the area at risk. "Unclear" (too little to go on) only shows when no goal has anything clearer. An area with
 * no goals, or whose goals have no status yet, has none.
 */
const RANK: Record<GoalStatus, number> = { unclear: 0, on_track: 1, at_risk: 2, off_track: 3 };

export function worstStatus(statuses: (GoalStatus | null | undefined)[]): GoalStatus | null {
  let worst: GoalStatus | null = null;
  for (const status of statuses) {
    if (status && (worst === null || RANK[status] > RANK[worst])) worst = status;
  }
  return worst;
}

/** One day of an area's last weeks: the worst of its goals' statuses that day. */
export type AreaTrajectoryDay = {
  /** "YYYY-MM-DD", in the person's own calendar. */
  day: string;
  status: GoalStatus | null;
  /** No goal in the area had a read that day: every status shown is carried from before. */
  carried: boolean;
};

/**
 * Lays an area's goals' trajectories over each other, day by day. Each trajectory covers the same days, oldest first
 * (see buildTrajectory); with no goals, every day is empty.
 */
export function combineTrajectories(
  trajectories: { day: string; status: GoalStatus | null; carried: boolean }[][],
  days: string[],
): AreaTrajectoryDay[] {
  return days.map((day, i) => {
    const onDay = trajectories.map((t) => t[i]).filter((d) => d && d.day === day && d.status !== null);
    return {
      day,
      status: worstStatus(onDay.map((d) => d.status)),
      carried: onDay.length > 0 && onDay.every((d) => d.carried),
    };
  });
}
