import * as z from "zod";

import { GOAL_COLOR_KEYS } from "@/lib/goal-colors";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";

/** A goal is a project (it has a finish line) or a practice (kept up a number of times a week). */
export const GOAL_KINDS = ["project", "practice"] as const;

/**
 * There's no cap on projects or practices: some people carry more than a dozen, and the app helps them put things off
 * rather than refusing them. GET /goals still sends this as `max` so older app builds, which hide New past it, keep
 * offering it.
 */
export const MAX_GOALS = 10_000;
/** A practice is meant to happen at most this many times a week. */
export const MAX_PER_WEEK = 14;
/** A practice's minimum session length can't be more than this many minutes. */
export const MAX_MIN_MINUTES = 480;
export const MAX_GOAL_TITLE = 120;
export const MAX_GOAL_DESCRIPTION = 1000;

/** Shared by the dialog (client) and the server actions. */
export const goalInputSchema = z.object({
  title: z
    .string()
    .trim()
    .min(1, "Give it a name.")
    .max(MAX_GOAL_TITLE, `Keep it under ${MAX_GOAL_TITLE} characters.`),
  icon: z.enum(GOAL_ICON_NAMES),
  color: z.enum(GOAL_COLOR_KEYS),
  /** What done looks like. Blank is stored as null. */
  description: z
    .string()
    .trim()
    .max(MAX_GOAL_DESCRIPTION, `Keep the description under ${MAX_GOAL_DESCRIPTION} characters.`)
    .nullish()
    .transform((v) => v || null),
  /** A calendar day, "YYYY-MM-DD". Blank is stored as null. */
  targetDate: z
    .union([z.iso.date("Pick a valid date."), z.literal("")])
    .nullish()
    .transform((v) => v || null),
});

export type GoalInput = z.infer<typeof goalInputSchema>;

/**
 * A practice's own fields, on top of the goal's. Left out keeps what it has when editing; a minimum of 0 clears it
 * (the Mac app's client can't send an explicit null).
 */
export const practiceFieldsSchema = z.object({
  perWeek: z
    .int()
    .min(1, "Pick at least once a week.")
    .max(MAX_PER_WEEK, `Keep it to ${MAX_PER_WEEK} times a week or fewer.`)
    .optional(),
  minMinutes: z
    .int()
    .min(0)
    .max(MAX_MIN_MINUTES, `Keep the minimum under ${MAX_MIN_MINUTES / 60} hours.`)
    .optional(),
  autoRecaps: z.boolean().optional(),
});

export type PracticeFields = z.infer<typeof practiceFieldsSchema>;
