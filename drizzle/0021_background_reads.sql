ALTER TABLE "goals" ADD COLUMN "read_requested_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "goals" ADD COLUMN "read_error" text;