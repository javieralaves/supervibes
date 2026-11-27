DROP INDEX "quests_season_area_idx";--> statement-breakpoint
CREATE INDEX "quests_season_area_idx" ON "quests" USING btree ("season_id","area_id");