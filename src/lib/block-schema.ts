import * as z from "zod";

/* Client-safe shapes for calendar blocks. Storage lives in blocks.ts. */

export const MAX_BLOCK_TITLE = 120;
/** Shortest block, and the drag-snapping step. */
export const BLOCK_STEP = 15;

const MINUTE = 60_000;

const timesSchema = z
  .object({ startsAt: z.iso.datetime({ offset: true }), endsAt: z.iso.datetime({ offset: true }) })
  .refine(({ startsAt, endsAt }) => Date.parse(endsAt) - Date.parse(startsAt) >= BLOCK_STEP * MINUTE, "Make it at least 15 minutes.")
  .refine(({ startsAt, endsAt }) => Date.parse(endsAt) - Date.parse(startsAt) <= 24 * 60 * MINUTE, "Keep it within a day.");

const titleSchema = z
  .string()
  .trim()
  .max(MAX_BLOCK_TITLE, `Keep the title under ${MAX_BLOCK_TITLE} characters.`)
  .nullable()
  .transform((t) => t || null);

/** What the popover sends when making or editing protected time. */
export const blockDetailsSchema = z.object({
  goalId: z.uuid(),
  title: titleSchema,
  keepOpen: z.boolean(),
});

export const newBlockSchema = z.intersection(blockDetailsSchema, timesSchema);
export const blockTimesSchema = timesSchema;

export type BlockDetails = z.infer<typeof blockDetailsSchema>;

/** A block as the calendar sees it; dates are ISO strings. */
export type BlockView = {
  id: string;
  goalId: string;
  title: string | null;
  startsAt: string;
  endsAt: string;
  keepOpen: boolean;
  /** The suggestion it was made from, if any. Kept for history. */
  fromSuggestion: string | null;
  /** The task it schedules: an intention. */
  taskId: string | null;
  /** Whether that task is done. */
  taskDone: boolean;
  /** What fits this titled block: "t:<task id>" or "s:<suggestion title>". */
  fits: string[];
  /** A plan for the session, if one has been prepared. */
  agenda: BlockAgenda | null;
};

/** A block's prepared plan: a paragraph, the tasks it draws on (a snapshot), and when it was made. */
export type BlockAgenda = {
  text: string;
  tasks: { id: string; title: string; minutes: number }[];
  /** ISO time. */
  preparedAt: string;
};
