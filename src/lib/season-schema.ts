import * as z from "zod";

import type { GoalStatus } from "./status-schema";
import { addDays, weekStartOf } from "./target-date";

/*
 * The rules of seasons and quests that need no database: a season's default days and name, its week, whether two
 * seasons overlap, and how quests and seasons get a status. Kept pure, so they're tested on their own
 * (season-schema.test.ts), as practice-count.ts is.
 */

/** A season's default length: three months, in whole weeks. */
export const SEASON_WEEKS = 13;
/** Most quests a season can focus on. */
export const MAX_QUESTS = 3;
/** Longest a season can run, so a typo can't make one last for years. */
export const MAX_SEASON_DAYS = 26 * 7;

const MAX_NAME = 40;
const MAX_QUEST_TITLE = 120;
const MAX_FROM = 160;
const MAX_GAP_TITLE = 160;
const MAX_GAP_BODY = 600;

const day = z.iso.date({ error: "Use a date like 2026-11-30." });

/** A season's name and days, as the person edits them. */
export const seasonInputSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(1, "Give the season a name.")
      .max(MAX_NAME, `Keep the name under ${MAX_NAME} characters.`),
    startsOn: day,
    endsOn: day,
  })
  .refine((s) => s.endsOn > s.startsOn, { message: "A season ends after it starts.", path: ["endsOn"] })
  .refine((s) => daysBetween(s.startsOn, s.endsOn) < MAX_SEASON_DAYS, {
    message: "Keep a season under six months.",
    path: ["endsOn"],
  });

export type SeasonInput = z.infer<typeof seasonInputSchema>;

/** A quest's words, as the person edits them: where it's headed and where it starts. */
export const questWordsSchema = z.object({
  title: z
    .string()
    .trim()
    .min(1, "Say where the quest is headed.")
    .max(MAX_QUEST_TITLE, `Keep it under ${MAX_QUEST_TITLE} characters.`),
  fromText: z
    .string()
    .trim()
    .min(1, "Say where it starts.")
    .max(MAX_FROM, `Keep it under ${MAX_FROM} characters.`),
});

/** An area's gap, as the person writes it or Supervibes names it. */
export const gapSchema = z.object({
  title: z
    .string()
    .trim()
    .min(1, "Name the gap in a few words.")
    .max(MAX_GAP_TITLE, `Keep it under ${MAX_GAP_TITLE} characters.`),
  body: z
    .string()
    .trim()
    .max(MAX_GAP_BODY, `Keep it under ${MAX_GAP_BODY} characters.`)
    .default(""),
});

export type GapInput = z.infer<typeof gapSchema>;

const MS_DAY = 24 * 60 * 60 * 1000;

/** Whole days from `from` to `to` ("YYYY-MM-DD"); negative when `to` is earlier. */
export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / MS_DAY);
}

/**
 * The season a new draft suggests: from the next Monday after `after` (today, or the day a running season ends) for
 * 13 weeks, named for the time of year at its middle.
 */
export function defaultSeason(after: string): SeasonInput {
  const monday = weekStartOf(after);
  const startsOn = monday > after ? monday : addDays(monday, 7);
  const endsOn = addDays(startsOn, SEASON_WEEKS * 7 - 1);
  return { name: seasonName(startsOn, endsOn), startsOn, endsOn };
}

/** "Winter", "Spring", "Summer" or "Autumn", by the month at the season's middle (northern hemisphere). */
export function seasonName(startsOn: string, endsOn: string): string {
  const middle = addDays(startsOn, Math.floor(daysBetween(startsOn, endsOn) / 2));
  const month = Number(middle.slice(5, 7));
  if (month === 12 || month <= 2) return "Winter";
  if (month <= 5) return "Spring";
  if (month <= 8) return "Summer";
  return "Autumn";
}

/** How many weeks a season runs, counting a part week as one. */
export function seasonWeeks(startsOn: string, endsOn: string): number {
  return Math.ceil((daysBetween(startsOn, endsOn) + 1) / 7);
}

/** The week of the season `today` falls in, 1 first; 0 before it starts; past the last week once it's over. */
export function seasonWeek(startsOn: string, endsOn: string, today: string): number {
  if (today < startsOn) return 0;
  const weeks = seasonWeeks(startsOn, endsOn);
  if (today > endsOn) return weeks + 1;
  return Math.floor(daysBetween(startsOn, today) / 7) + 1;
}

/** Whether two seasons share a day. Both ends are included. */
export function overlaps(a: { startsOn: string; endsOn: string }, b: { startsOn: string; endsOn: string }): boolean {
  return a.startsOn <= b.endsOn && b.startsOn <= a.endsOn;
}

/**
 * The worst of some statuses: the same rule as an area's (worstStatus in area-schema.ts), kept here so this file stays
 * importable by the tests without the icon set. "Unclear" only counts when nothing is clearer.
 */
const RANK: Record<GoalStatus, number> = { unclear: 0, on_track: 1, at_risk: 2, off_track: 3 };
function worstStatus(statuses: (GoalStatus | null | undefined)[]): GoalStatus | null {
  let worst: GoalStatus | null = null;
  for (const status of statuses) {
    if (status && (worst === null || RANK[status] > RANK[worst])) worst = status;
  }
  return worst;
}

/**
 * A quest's effort: the worst of its goals' statuses, as an area's status is. Null with no goals, or none with a
 * status yet.
 */
export function questEffort(goalStatuses: (GoalStatus | null | undefined)[]): GoalStatus | null {
  return worstStatus(goalStatuses);
}

/** A season's status: the worst of its quests' efforts. */
export function seasonStatus(questEfforts: (GoalStatus | null | undefined)[]): GoalStatus | null {
  return worstStatus(questEfforts);
}

export type StartProblem = "no_quests" | "too_many_quests" | "quest_without_goals";

/** Why a draft can't start yet, or null when it can: one to three chosen quests, each moved by at least one goal. */
export function startProblem(chosen: { goalCount: number }[]): StartProblem | null {
  if (chosen.length === 0) return "no_quests";
  if (chosen.length > MAX_QUESTS) return "too_many_quests";
  if (chosen.some((q) => q.goalCount === 0)) return "quest_without_goals";
  return null;
}

/** What each start problem says to the person. */
export const START_MESSAGES: Record<StartProblem, string> = {
  no_quests: "Choose at least one quest for the season.",
  too_many_quests: `Choose up to ${MAX_QUESTS} quests for the season.`,
  quest_without_goals: "Give each quest a project or practice to move it.",
};

/** The usual life areas, offered when choosing a season's areas. A fixed list, not AI. */
export const POPULAR_AREAS = [
  { name: "Health", icon: "FavouriteIcon", line: "Your body, energy and how you look after them." },
  { name: "Relationships", icon: "Agreement01Icon", line: "The people close to you, and time with them." },
  { name: "Work", icon: "Briefcase01Icon", line: "What you do, and where it’s going." },
  { name: "Money", icon: "Wallet01Icon", line: "Income, spending, saving, and what they make possible." },
  { name: "Home", icon: "Sofa01Icon", line: "Where you live, and how it feels to be there." },
  { name: "Growth", icon: "Mortarboard01Icon", line: "What you’re learning, and who you’re becoming." },
  { name: "Play", icon: "PartyIcon", line: "Rest, hobbies, and time that’s just for fun." },
  { name: "Mind", icon: "BrainIcon", line: "How you feel day to day: calm, stress, sleep." },
  { name: "Meaning", icon: "Leaf01Icon", line: "What matters to you, and what you give back." },
] as const;

/** The popular areas the person doesn't have yet, matched on name, ignoring case and spaces. */
export function popularAreasFor(yourNames: string[]) {
  const key = (name: string) => name.toLowerCase().replace(/\s+/g, "");
  const yours = new Set(yourNames.map(key));
  return POPULAR_AREAS.filter((area) => !yours.has(key(area.name)));
}
