CREATE TABLE "practice_pauses" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"goal_id" uuid NOT NULL,
	"starts_on" date NOT NULL,
	"resumes_on" date,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "practice_sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"goal_id" uuid NOT NULL,
	"day" date NOT NULL,
	"done_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "calendar_blocks" ADD COLUMN "missed" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "goals" ADD COLUMN "kind" text DEFAULT 'project' NOT NULL;--> statement-breakpoint
ALTER TABLE "goals" ADD COLUMN "per_week" integer;--> statement-breakpoint
ALTER TABLE "goals" ADD COLUMN "min_minutes" integer;--> statement-breakpoint
ALTER TABLE "goals" ADD COLUMN "auto_recaps" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "practice_pauses" ADD CONSTRAINT "practice_pauses_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "practice_pauses" ADD CONSTRAINT "practice_pauses_goal_id_goals_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."goals"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "practice_sessions" ADD CONSTRAINT "practice_sessions_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "practice_sessions" ADD CONSTRAINT "practice_sessions_goal_id_goals_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."goals"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "practice_pauses_goal_idx" ON "practice_pauses" USING btree ("goal_id","starts_on");--> statement-breakpoint
CREATE INDEX "practice_sessions_goal_day_idx" ON "practice_sessions" USING btree ("goal_id","day");