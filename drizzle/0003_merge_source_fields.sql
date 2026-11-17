-- Fold "where to look" into the single description before dropping it.
UPDATE "goal_sources" SET "relation" = "scope" || '. ' || "relation" WHERE "scope" <> '';--> statement-breakpoint
ALTER TABLE "goal_sources" DROP COLUMN "scope";--> statement-breakpoint
ALTER TABLE "goal_sources" DROP COLUMN "signal";
