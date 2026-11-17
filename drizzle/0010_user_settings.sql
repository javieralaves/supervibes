CREATE TABLE "user_settings" (
	"user_id" text PRIMARY KEY NOT NULL,
	"sleep_start" integer DEFAULT 1380 NOT NULL,
	"wake_time" integer DEFAULT 420 NOT NULL,
	"clock" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "user_settings" ADD CONSTRAINT "user_settings_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;