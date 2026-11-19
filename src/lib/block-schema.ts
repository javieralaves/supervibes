import * as z from "zod";

import type { BlockRecap, PostedRecap } from "@/lib/recap-schema";

/* Client-safe shapes for calendar blocks. Storage lives in blocks.ts. */

export const MAX_BLOCK_TITLE = 120;
export const MAX_BLOCK_DESCRIPTION = 1000;
/** Shortest block, and the drag-snapping step. */
export const BLOCK_STEP = 15;

const MINUTE = 60_000;

const timesSchema = z
  .object({ startsAt: z.iso.datetime({ offset: true }), endsAt: z.iso.datetime({ offset: true }) })
  .refine(({ startsAt, endsAt }) => Date.parse(endsAt) - Date.parse(startsAt) >= BLOCK_STEP * MINUTE, "Make it at least 15 minutes.")
  .refine(({ startsAt, endsAt }) => Date.parse(endsAt) - Date.parse(startsAt) <= 24 * 60 * MINUTE, "Keep it within a day.");

/** Empty, null or left out (as the Mac app's client leaves out a nil title) all mean no title. */
const titleSchema = z
  .string()
  .trim()
  .max(MAX_BLOCK_TITLE, `Keep the title under ${MAX_BLOCK_TITLE} characters.`)
  .nullish()
  .transform((t) => t || null);

/** What the popover sends when making or editing protected time. */
export const blockDetailsSchema = z.object({
  goalId: z.uuid(),
  title: titleSchema,
});

/** What the block panel sends when the person writes what they want out of a session. Empty means none. */
export const blockDescriptionSchema = z
  .string()
  .trim()
  .max(MAX_BLOCK_DESCRIPTION, `Keep it under ${MAX_BLOCK_DESCRIPTION} characters.`)
  .transform((d) => d || null);

export const newBlockSchema = z.intersection(blockDetailsSchema, timesSchema);
export const blockTimesSchema = timesSchema;

export type BlockDetails = z.infer<typeof blockDetailsSchema>;

/** A block as the calendar sees it; dates are ISO strings. */
export type BlockView = {
  id: string;
  goalId: string;
  title: string | null;
  /** For protected time: what the person wants out of the session, in their words. */
  description: string | null;
  startsAt: string;
  endsAt: string;
  /** The suggestion it was made from, if any. Kept for history. */
  fromSuggestion: string | null;
  /** The task it schedules: an intention. */
  taskId: string | null;
  /** Whether that task is done. */
  taskDone: boolean;
  /** A plan for the session, if one has been prepared. */
  agenda: BlockAgenda | null;
  /** A draft recap, once the session has ended and one has been prepared. */
  recap: BlockRecap | null;
  /** The recap posted to the goal's activity, once there is one. */
  recapPost: PostedRecap | null;
  /** A recap is drafting itself in the background; it shows up on a later refresh. */
  recapDrafting: boolean;
};

/** A block's prepared plan: a paragraph, the tasks it draws on (a snapshot), and when it was made. */
export type BlockAgenda = {
  text: string;
  tasks: { id: string; title: string; minutes: number }[];
  /** ISO time. */
  preparedAt: string;
  /**
   * The block's title and description when this was prepared, so the panel can tell when they've
   * changed since. Missing on agendas prepared before they were kept.
   */
  title?: string | null;
  description?: string | null;
};
