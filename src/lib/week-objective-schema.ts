import * as z from "zod";

/* Client-safe shape for a goal's weekly objective. Storage lives in week-objectives.ts. */

export const MAX_WEEK_OBJECTIVE = 500;

/** Empty clears it. */
export const weekObjectiveSchema = z
  .string()
  .trim()
  .max(MAX_WEEK_OBJECTIVE, `Keep it under ${MAX_WEEK_OBJECTIVE} characters.`)
  .transform((o) => o || null);

/** A week, by the Monday it starts on. */
export const weekStartSchema = z.iso
  .date("Pick a valid week.")
  .refine((d) => new Date(`${d}T00:00:00Z`).getUTCDay() === 1, "A week starts on a Monday.");
