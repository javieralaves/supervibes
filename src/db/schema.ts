// Better Auth tables (user, session, account, verification).
// Regenerate with: npx auth@latest generate --config src/lib/auth.ts --output src/db/auth-schema.ts
export * from "./auth-schema";

// Your tables go below. Every table holding personal data should reference
// the owning user, and every query should filter on it (see src/lib/session.ts).
//
// Example:
//
// import { index, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
// import { user } from "./auth-schema";
//
// export const notes = pgTable(
//   "notes",
//   {
//     id: uuid().primaryKey().defaultRandom(),
//     userId: text()
//       .notNull()
//       .references(() => user.id, { onDelete: "cascade" }),
//     body: text().notNull(),
//     createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
//   },
//   (t) => [index("notes_user_id_idx").on(t.userId)],
// );
