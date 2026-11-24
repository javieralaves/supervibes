ALTER TABLE "calendar_blocks" ADD COLUMN "source_key" text;--> statement-breakpoint
ALTER TABLE "calendar_blocks" ADD COLUMN "source_calendar" text;--> statement-breakpoint
ALTER TABLE "calendar_blocks" ADD COLUMN "source_snapshot" jsonb;--> statement-breakpoint
CREATE UNIQUE INDEX "calendar_blocks_user_source_idx" ON "calendar_blocks" USING btree ("user_id","source_key");