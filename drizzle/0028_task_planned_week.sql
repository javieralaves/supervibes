ALTER TABLE "goal_tasks" ADD COLUMN "planned_week" date;--> statement-breakpoint
-- A task already planned for a day is planned for that day's week (weeks start on Monday, as in Postgres).
UPDATE "goal_tasks" SET "planned_week" = date_trunc('week', "planned_for")::date WHERE "planned_for" IS NOT NULL;
