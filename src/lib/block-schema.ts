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

/**
 * What drawing a block makes: a session (the default), reserved time, or a task's time. A task is
 * the one `taskId` names, or, without one, a new task in the goal titled with the block's title.
 */
export const BLOCK_KINDS = ["session", "reserved", "task"] as const;
export type BlockKind = (typeof BLOCK_KINDS)[number];

const newBlockKindSchema = z.object({
  kind: z.enum(BLOCK_KINDS).nullish().transform((k) => k ?? "session"),
  taskId: z.uuid().nullish().transform((t) => t ?? null),
});

export const newBlockSchema = z.intersection(z.intersection(blockDetailsSchema, timesSchema), newBlockKindSchema);
export const blockTimesSchema = timesSchema;

/** Longest event key and calendar name kept for an imported block. */
export const MAX_SOURCE_KEY = 512;
export const MAX_SOURCE_CALENDAR = 200;
/** Event titles can be longer than a block's; the snapshot keeps the event's own, up to this. */
export const MAX_SOURCE_TITLE = 1000;

/** An ISO time, stored as UTC so snapshots compare as strings. */
const instantSchema = z.iso.datetime({ offset: true }).transform((t) => new Date(t).toISOString());

/** An event as it was when the person last agreed with it: what the Mac app compares the event now with. */
export const blockSourceSnapshotSchema = z
  .object({
    title: z.string().max(MAX_SOURCE_TITLE, "That event’s title is too long."),
    startsAt: instantSchema,
    endsAt: instantSchema,
  })
  .refine(({ startsAt, endsAt }) => Date.parse(endsAt) > Date.parse(startsAt), "The event has to end after it starts.");

export type BlockSourceSnapshot = z.infer<typeof blockSourceSnapshotSchema>;

/**
 * Where an imported block came from: an event in one of the person's own calendars, read on their
 * Mac. `key` is the event's stable key (unique per person); `calendar` is its calendar's name.
 */
export const blockSourceSchema = z.object({
  key: z.string().min(1, "That event has no key.").max(MAX_SOURCE_KEY, "That event’s key is too long."),
  calendar: z
    .string()
    .trim()
    .min(1, "Say which calendar the event is in.")
    .max(MAX_SOURCE_CALENDAR, "That calendar’s name is too long."),
  snapshot: blockSourceSnapshotSchema,
});

export type BlockSource = z.infer<typeof blockSourceSchema>;

/**
 * Answering a change to an imported block's event: the event as it is now becomes the baseline,
 * and whatever of it the person takes (its title, its times) is applied to the block. Neither
 * taken is "Keep mine".
 */
export const blockSourceSyncSchema = z
  .object({
    snapshot: blockSourceSnapshotSchema,
    title: titleSchema.optional(),
    startsAt: z.iso.datetime({ offset: true }).optional(),
    endsAt: z.iso.datetime({ offset: true }).optional(),
  })
  .refine(({ startsAt, endsAt }) => (startsAt === undefined) === (endsAt === undefined), "Send both times, or neither.")
  .refine(
    ({ startsAt, endsAt }) => startsAt === undefined || endsAt === undefined || timesSchema.safeParse({ startsAt, endsAt }).success,
    "Make it at least 15 minutes, and keep it within a day.",
  );

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
  /** Protected time kept for its own sake: not a session, and no room for tasks. */
  reserved: boolean;
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
