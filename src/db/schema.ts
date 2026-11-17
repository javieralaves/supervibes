import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

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
    /** Name of a Hugeicons icon from src/lib/goal-icons.ts, e.g. "Rocket01Icon". */
    icon: text().notNull(),
    /** Palette key from src/lib/goal-colors.ts, e.g. "violet". Not a hex value. */
    color: text().notNull(),
    /** Manual sort order within a user's goals, ascending. */
    position: integer().notNull().default(0),
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
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp({ withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("goal_posts_goal_created_idx").on(t.goalId, t.createdAt)],
);

export type Connection = typeof connections.$inferSelect;
export type GoalSource = typeof goalSources.$inferSelect;
export type GoalRead = typeof goalReads.$inferSelect;
export type GoalPost = typeof goalPosts.$inferSelect;
