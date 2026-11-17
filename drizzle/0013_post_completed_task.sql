ALTER TABLE "goal_posts" ADD COLUMN "completed_task" text;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD COLUMN "task_id" uuid;--> statement-breakpoint
ALTER TABLE "goal_posts" ADD CONSTRAINT "goal_posts_task_id_goal_tasks_id_fk" FOREIGN KEY ("task_id") REFERENCES "public"."goal_tasks"("id") ON DELETE set null ON UPDATE no action;