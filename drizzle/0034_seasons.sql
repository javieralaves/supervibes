CREATE TABLE "quest_goals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"season_id" uuid NOT NULL,
	"quest_id" uuid NOT NULL,
	"goal_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "quest_reads" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"quest_id" uuid NOT NULL,
	"headline" text NOT NULL,
	"summary" text NOT NULL,
	"goal_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"used_calendar" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "quests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"season_id" uuid NOT NULL,
	"area_id" uuid NOT NULL,
	"title" text NOT NULL,
	"from_text" text NOT NULL,
	"reach" integer NOT NULL,
	"chosen" boolean DEFAULT false NOT NULL,
	"position" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "season_reads" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"season_id" uuid NOT NULL,
	"headline" text NOT NULL,
	"summary" text NOT NULL,
	"goal_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"used_calendar" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "seasons" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"name" text NOT NULL,
	"starts_on" date NOT NULL,
	"ends_on" date NOT NULL,
	"state" text DEFAULT 'draft' NOT NULL,
	"started_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "areas" ADD COLUMN "gap_title" text;--> statement-breakpoint
ALTER TABLE "areas" ADD COLUMN "gap_body" text;--> statement-breakpoint
ALTER TABLE "areas" ADD COLUMN "gap_by" text;--> statement-breakpoint
ALTER TABLE "areas" ADD COLUMN "gap_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "quest_goals" ADD CONSTRAINT "quest_goals_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_goals" ADD CONSTRAINT "quest_goals_season_id_seasons_id_fk" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_goals" ADD CONSTRAINT "quest_goals_quest_id_quests_id_fk" FOREIGN KEY ("quest_id") REFERENCES "public"."quests"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_goals" ADD CONSTRAINT "quest_goals_goal_id_goals_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."goals"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_reads" ADD CONSTRAINT "quest_reads_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_reads" ADD CONSTRAINT "quest_reads_quest_id_quests_id_fk" FOREIGN KEY ("quest_id") REFERENCES "public"."quests"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quests" ADD CONSTRAINT "quests_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quests" ADD CONSTRAINT "quests_season_id_seasons_id_fk" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quests" ADD CONSTRAINT "quests_area_id_areas_id_fk" FOREIGN KEY ("area_id") REFERENCES "public"."areas"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "season_reads" ADD CONSTRAINT "season_reads_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "season_reads" ADD CONSTRAINT "season_reads_season_id_seasons_id_fk" FOREIGN KEY ("season_id") REFERENCES "public"."seasons"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "seasons" ADD CONSTRAINT "seasons_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "quest_goals_season_goal_idx" ON "quest_goals" USING btree ("season_id","goal_id");--> statement-breakpoint
CREATE INDEX "quest_goals_quest_idx" ON "quest_goals" USING btree ("quest_id");--> statement-breakpoint
CREATE UNIQUE INDEX "quest_reads_quest_idx" ON "quest_reads" USING btree ("quest_id");--> statement-breakpoint
CREATE UNIQUE INDEX "quests_season_area_idx" ON "quests" USING btree ("season_id","area_id");--> statement-breakpoint
CREATE UNIQUE INDEX "season_reads_season_idx" ON "season_reads" USING btree ("season_id");--> statement-breakpoint
CREATE INDEX "seasons_user_starts_idx" ON "seasons" USING btree ("user_id","starts_on");--> statement-breakpoint
CREATE UNIQUE INDEX "seasons_one_draft_idx" ON "seasons" USING btree ("user_id") WHERE "seasons"."state" = 'draft';--> statement-breakpoint
CREATE UNIQUE INDEX "seasons_one_active_idx" ON "seasons" USING btree ("user_id") WHERE "seasons"."state" = 'active';