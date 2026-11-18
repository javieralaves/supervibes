ALTER TABLE "calendar_blocks" ADD COLUMN "recap" jsonb;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD COLUMN "block_id" uuid;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD COLUMN "session" jsonb;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD COLUMN "breadcrumbs" jsonb;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD CONSTRAINT "goal_posts_block_id_calendar_blocks_id_fk" FOREIGN KEY ("block_id") REFERENCES "public"."calendar_blocks"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "goal_posts_block_idx" ON "goal_posts" USING btree ("block_id");