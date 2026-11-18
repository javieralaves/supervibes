ALTER TABLE "goal_tasks" ADD COLUMN "planned_for" date;--> statement-breakpoint
ALTER TABLE "goal_tasks" ADD COLUMN "due_on" date;--> statement-breakpoint
ALTER TABLE "user_settings" ADD COLUMN "time_zone" text;