import { index, integer, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

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
