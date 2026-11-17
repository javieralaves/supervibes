-- Keep only each goal's latest read before making goal_id unique.
DELETE FROM "goal_reads" r
USING "goal_reads" newer
WHERE newer."goal_id" = r."goal_id" AND newer."created_at" > r."created_at";--> statement-breakpoint
DROP INDEX "goal_reads_goal_created_idx";--> statement-breakpoint
CREATE UNIQUE INDEX "goal_reads_goal_idx" ON "goal_reads" USING btree ("goal_id");--> statement-breakpoint
ALTER TABLE "goal_reads" DROP COLUMN "status";--> statement-breakpoint
ALTER TABLE "goal_reads" DROP COLUMN "trend";
