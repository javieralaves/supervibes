ALTER TABLE "goal_reads" ADD COLUMN "suggestions" jsonb DEFAULT '[]'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "goal_reads" ADD COLUMN "dismissed" jsonb DEFAULT '[]'::jsonb NOT NULL;