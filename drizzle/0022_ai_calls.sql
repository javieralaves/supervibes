CREATE TABLE "ai_calls" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"goal_id" uuid,
	"feature" text NOT NULL,
	"trigger" text NOT NULL,
	"model" text NOT NULL,
	"input_tokens" integer DEFAULT 0 NOT NULL,
	"cache_read_tokens" integer DEFAULT 0 NOT NULL,
	"cache_write_tokens" integer DEFAULT 0 NOT NULL,
	"output_tokens" integer DEFAULT 0 NOT NULL,
	"tool_calls" integer DEFAULT 0 NOT NULL,
	"requests" integer DEFAULT 1 NOT NULL,
	"duration_ms" integer DEFAULT 0 NOT NULL,
	"outcome" text NOT NULL,
	"cost_micros" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "ai_calls" ADD CONSTRAINT "ai_calls_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ai_calls" ADD CONSTRAINT "ai_calls_goal_id_goals_id_fk" FOREIGN KEY ("goal_id") REFERENCES "public"."goals"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ai_calls_user_created_idx" ON "ai_calls" USING btree ("user_id","created_at");