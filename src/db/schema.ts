import {
  type AnyPgColumn,
  boolean,
  date,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

import type { BlockAgenda } from "../lib/block-schema";
import type { BlockRecap, Breadcrumb, RecapSession } from "../lib/recap-schema";
import type { GoalStatus, Outlook, StatusBasis } from "../lib/status-schema";

import { user } from "./auth-schema";

// Better Auth tables (user, session, account, verification).
// Regenerate with: npx auth@latest generate --config src/lib/auth.ts --output src/db/auth-schema.ts
export * from "./auth-schema";

// Every table holding personal data references the owning user, and every
// query filters on it (see src/lib/goals.ts for the pattern).

export const goals = pgTable(
  "goals",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    title: text().notNull(),
    /** Optional, in the person's words: what done looks like. Shapes progress reads and agendas. */
    description: text(),
    /** Optional calendar day the person wants this done by, as "YYYY-MM-DD" (no time zone). */
    targetDate: date({ mode: "string" }),
    /** Name of a Hugeicons icon from src/lib/goal-icons.ts, e.g. "Rocket01Icon". */
    icon: text().notNull(),
    /** Palette key from src/lib/goal-colors.ts, e.g. "violet". Not a hex value. */
    color: text().notNull(),
    /** Manual sort order within a user's goals, ascending. */
    position: integer().notNull().default(0),
    /**
     * When a progress read was last asked for and hasn't finished; null when none is pending.
     * Reads run in the background after a post, so the goal page can show one is underway.
     */
    readRequestedAt: timestamp({ withTimezone: true }),
    /** Why the last background read failed, until the next one is asked for. */
    readError: text(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("goals_user_id_position_idx").on(t.userId, t.position)],
);

export type Goal = typeof goals.$inferSelect;

/**
 * A user's link to another app's remote MCP server (Linear, GitHub, Granola).
 * OAuth client details and tokens are encrypted at rest (src/lib/crypto.ts)
 * and never sent to the browser.
 */
export const connections = pgTable(
  "connections",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    /** Provider key from src/lib/providers.ts, e.g. "linear". */
    provider: text().notNull(),
    serverUrl: text().notNull(),
    /** Encrypted JSON: OAuth client information (from dynamic registration or app config). */
    clientInfo: text().notNull(),
    /** Encrypted JSON: OAuth tokens plus an absolute expiry. */
    tokens: text().notNull(),
    /** Names of the server's read-only tools; the only ones a sync may call. */
    readTools: jsonb().$type<string[]>().notNull().default([]),
    status: text().notNull().default("connected"), // connected | error
    lastError: text(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [uniqueIndex("connections_user_provider_idx").on(t.userId, t.provider)],
);

/**
 * Where context for a goal lives in a connected app, and — in the user's own
 * words — how that context relates to the goal.
 */
export const goalSources = pgTable(
  "goal_sources",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    connectionId: uuid()
      .notNull()
      .references(() => connections.id, { onDelete: "cascade" }),
    /**
     * In the user's own words: where in the app to look, and how that activity
     * relates to the goal (what counts, what to ignore). Drives what a sync picks up.
     */
    relation: text().notNull(),
    enabled: boolean().notNull().default(true),
    /** Why this source couldn't be read last time (e.g. the app needs reconnecting). */
    lastError: text(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("goal_sources_goal_idx").on(t.goalId)],
);

/**
 * The latest high-level read of whether the user is making progress on a goal,
 * drawn from all of the goal's sources at once. One row per goal, replaced on each read.
 */
export const goalReads = pgTable(
  "goal_reads",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    headline: text().notNull(),
    summary: text().notNull(),
    /** Provider keys of the apps this read drew on, e.g. ["linear"]. */
    basedOn: jsonb().$type<string[]>().notNull().default([]),
    /** 2–3 concrete next moves (30 min to 2 hr), replaced on every read. */
    suggestions: jsonb().$type<{ title: string; why: string; minutes: number }[]>().notNull().default([]),
    /** Titles of suggestions the person passed on, so later reads don't repeat them. Kept across reads. */
    dismissed: jsonb().$type<string[]>().notNull().default([]),
    /** When this read was made. */
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex("goal_reads_goal_idx").on(t.goalId)],
);

/**
 * A note the user posts on a goal: context no connected app can show
 * (offline work, decisions, corrections). Progress reads take these into account.
 */
export const goalPosts = pgTable(
  "goal_posts",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    body: text().notNull(),
    /** Title of the suggestion this note marks as done, if it came from "Done" on a suggestion. */
    completedSuggestion: text(),
    /** Title of the task this note records as done; posted when the task is checked off. */
    completedTask: text(),
    /** The task it records, while that task exists. */
    taskId: uuid().references(() => goalTasks.id, { onDelete: "set null" }),
    /** The calendar block this post recaps, while that block exists. One recap per block. */
    blockId: uuid().references((): AnyPgColumn => calendarBlocks.id, { onDelete: "set null" }),
    /** The recapped session's title and times; set only on recaps. */
    session: jsonb().$type<RecapSession>(),
    /** Links to specific things in connected apps the recap drew on. */
    breadcrumbs: jsonb().$type<Breadcrumb[]>(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index("goal_posts_goal_created_idx").on(t.goalId, t.createdAt),
    uniqueIndex("goal_posts_block_idx").on(t.blockId),
  ],
);

export type Connection = typeof connections.$inferSelect;
export type GoalSource = typeof goalSources.$inferSelect;
export type GoalRead = typeof goalReads.$inferSelect;
export type GoalPost = typeof goalPosts.$inferSelect;

/**
 * Per-user preferences. One row per user, created on first save; until then
 * the defaults in src/lib/settings-schema.ts apply.
 */
export const userSettings = pgTable("user_settings", {
  userId: text()
    .primaryKey()
    .references(() => user.id, { onDelete: "cascade" }),
  /** Bedtime, in minutes after local midnight (0–1439). */
  sleepStart: integer().notNull().default(23 * 60),
  /** Wake-up time, in minutes after local midnight (0–1439). */
  wakeTime: integer().notNull().default(7 * 60),
  /** "12h" or "24h"; null follows the device. */
  clock: text(),
  /** IANA time zone from their browser, e.g. "Europe/Madrid", so "today" is their day on the server too. */
  timeZone: text(),
  updatedAt: timestamp({ withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date()),
});

/**
 * Time on the calendar held for a goal. One table for both kinds:
 * - an intention: a task (or, earlier, a suggestion) committed to a time (`taskId` or `fromSuggestion` set);
 * - protected time: made by dragging on the calendar, with an optional title. It's a session (time to
 *   work on the goal, with an aim, agenda and recap) unless it's `reserved`: kept for its own sake
 *   (lunch, family, an event), with nothing planned into it.
 */
export const calendarBlocks = pgTable(
  "calendar_blocks",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    title: text(),
    /** For protected time: what the person wants out of the session, in their words. Steers its agenda and recap. */
    description: text(),
    startsAt: timestamp({ withTimezone: true }).notNull(),
    endsAt: timestamp({ withTimezone: true }).notNull(),
    /** Title of the suggestion this block commits to, making it an intention. Kept for history. */
    fromSuggestion: text(),
    /** The task this block schedules, making it an intention. */
    taskId: uuid().references(() => goalTasks.id, { onDelete: "set null" }),
    /**
     * Protected time kept for its own sake rather than to work in: no aim, agenda or recap, and it
     * doesn't count as room for the goal's tasks. Never set on an intention.
     */
    reserved: boolean().notNull().default(false),
    /** A plan for the session, prepared on request from the goal's tasks and latest read. */
    agenda: jsonb().$type<BlockAgenda>(),
    /** A draft recap of the session, until it's posted to the goal's activity or discarded. */
    recap: jsonb().$type<BlockRecap>(),
    /**
     * Drafting a recap on its own, after the session ended: "drafting" while it runs,
     * "done" once it has (whether or not there was anything worth a draft). Set once,
     * so a session is drafted or passed over at most once. Null: not tried.
     */
    autoRecap: text().$type<"drafting" | "done">(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("calendar_blocks_user_starts_idx").on(t.userId, t.startsAt)],
);

/**
 * A goal's status as each progress read judged it, kept read by read so its
 * trajectory can be drawn and later reads stay consistent. goal_reads keeps only
 * the latest read; this keeps every status.
 */
export const goalStatuses = pgTable(
  "goal_statuses",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    /** "on_track" | "at_risk" | "off_track" | "unclear". */
    status: text().$type<GoalStatus>().notNull(),
    /** What it was measured against: "target" | "week" | "momentum". */
    basis: text().$type<StatusBasis>().notNull(),
    /** One line on why, from the read. */
    reason: text().notNull(),
    /** Where a goal with a target date is heading by then; null otherwise. */
    outlook: jsonb().$type<Outlook>(),
    /** What started the read: "manual" | "note" | "recap" | "cron". */
    trigger: text().notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("goal_statuses_goal_created_idx").on(t.goalId, t.createdAt)],
);

/**
 * What a week should move for a goal, in the person's words: optional, one row per
 * goal per week. Kept week by week, so later reads can see what was meant and whether
 * it happened. Weeks start on Monday in the person's own calendar.
 */
export const goalWeeks = pgTable(
  "goal_weeks",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    /** The Monday the week starts on, "YYYY-MM-DD". */
    weekStart: date({ mode: "string" }).notNull(),
    objective: text().notNull(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [uniqueIndex("goal_weeks_goal_week_idx").on(t.goalId, t.weekStart)],
);

/** Things the person has decided to do for a goal. Open until `doneAt` is set. */
export const goalTasks = pgTable(
  "goal_tasks",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    goalId: uuid()
      .notNull()
      .references(() => goals.id, { onDelete: "cascade" }),
    title: text().notNull(),
    /** Optional details, plain text. */
    description: text(),
    /** Estimate in minutes: 15, 30, 60 or 120. */
    minutes: integer().notNull().default(30),
    /** When it was checked off; null while open. */
    doneAt: timestamp({ withTimezone: true }),
    /**
     * The day the person means to do it ("YYYY-MM-DD", their own calendar day), without a time yet.
     * Giving it a time on the calendar keeps this in step with the block's day.
     */
    plannedFor: date({ mode: "string" }),
    /**
     * The week the person means to do it, as the Monday it starts on ("YYYY-MM-DD"). Set with a
     * planned day (the day's week), or on its own for "sometime this week" or next week. Null with
     * no planned day: not planned yet (Later). See src/lib/task-horizon.ts for how it's read.
     */
    plannedWeek: date({ mode: "string" }),
    /** The day it has to be done by ("YYYY-MM-DD", their own calendar day). */
    dueOn: date({ mode: "string" }),
    /** Manual order among the goal's tasks, ascending. */
    position: integer().notNull().default(0),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("goal_tasks_goal_idx").on(t.goalId, t.position)],
);

/**
 * One call to the Claude API: what it was for, what started it, and the tokens
 * and cost it took. Raw token counts are kept so cost can be recomputed if prices change.
 */
export const aiCalls = pgTable(
  "ai_calls",
  {
    id: uuid().primaryKey().defaultRandom(),
    userId: text()
      .notNull()
      .references(() => user.id, { onDelete: "cascade" }),
    /** The goal it was about, while that goal exists. */
    goalId: uuid().references(() => goals.id, { onDelete: "set null" }),
    /** "progress_read" | "recap" | "agenda". */
    feature: text().notNull(),
    /** What started it: "manual" | "note" | "recap" | "cron" | "draft" | "redraft" | "auto". */
    trigger: text().notNull(),
    /** The model that answered (a refusal can be answered by a fallback model). */
    model: text().notNull(),
    /** Uncached input tokens. */
    inputTokens: integer().notNull().default(0),
    cacheReadTokens: integer().notNull().default(0),
    cacheWriteTokens: integer().notNull().default(0),
    /** Output tokens, thinking included. */
    outputTokens: integer().notNull().default(0),
    /** Calls to connected apps' tools during it. */
    toolCalls: integer().notNull().default(0),
    /** API requests it took: more than one when a long tool loop was paused and resumed. */
    requests: integer().notNull().default(1),
    durationMs: integer().notNull().default(0),
    /** How it ended: the API's stop reason, or "error". */
    outcome: text().notNull(),
    /** Cost in millionths of a dollar, from src/lib/ai-pricing.ts at the time; null for an unpriced model. */
    costMicros: integer(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index("ai_calls_user_created_idx").on(t.userId, t.createdAt)],
);

export type AiCall = typeof aiCalls.$inferSelect;
