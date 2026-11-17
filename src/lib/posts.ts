import "server-only";

import { and, desc, eq, isNotNull } from "drizzle-orm";

import { db } from "@/db";
import { goalPosts, goals, goalTasks } from "@/db/schema";

/*
 * Notes the user posts on a goal. Same rule as everything else: every query
 * filters on the owner, and writes check the goal belongs to them.
 */

export type PostDTO = {
  id: string;
  body: string;
  /** Title of the suggestion this note marks as done, if any. */
  completedSuggestion: string | null;
  /** Title of the task this note records as done, if it was posted by checking one off. */
  completedTask: string | null;
  /** The task it records, while that task still exists. */
  taskId: string | null;
  /** That task's description, when listing. */
  taskDescription?: string | null;
  createdAt: Date;
  updatedAt: Date;
};

const columns = {
  id: goalPosts.id,
  body: goalPosts.body,
  completedSuggestion: goalPosts.completedSuggestion,
  completedTask: goalPosts.completedTask,
  taskId: goalPosts.taskId,
  createdAt: goalPosts.createdAt,
  updatedAt: goalPosts.updatedAt,
};

/** Newest first. */
export async function listPosts(userId: string, goalId: string, limit = 100): Promise<PostDTO[]> {
  return db
    .select({ ...columns, taskDescription: goalTasks.description })
    .from(goalPosts)
    .leftJoin(goalTasks, eq(goalTasks.id, goalPosts.taskId))
    .where(and(eq(goalPosts.goalId, goalId), eq(goalPosts.userId, userId)))
    .orderBy(desc(goalPosts.createdAt))
    .limit(limit);
}

export async function createPost(
  userId: string,
  goalId: string,
  body: string,
  completedSuggestion: string | null = null,
): Promise<PostDTO | null> {
  const [goal] = await db
    .select({ id: goals.id })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return null;
  const [post] = await db
    .insert(goalPosts)
    .values({ userId, goalId, body, completedSuggestion })
    .returning(columns);
  return post;
}

/** Records a task being checked off, as a note with no text of its own. */
export async function createTaskDonePost(userId: string, goalId: string, taskId: string, title: string) {
  await db.insert(goalPosts).values({ userId, goalId, body: "", completedTask: title, taskId });
}

/** Removes the note that recorded a task as done, when it's reopened. */
export async function deleteTaskDonePosts(userId: string, taskId: string) {
  await db
    .delete(goalPosts)
    .where(and(eq(goalPosts.taskId, taskId), eq(goalPosts.userId, userId), isNotNull(goalPosts.completedTask)));
}

export async function updatePost(userId: string, postId: string, body: string): Promise<PostDTO | null> {
  const [post] = await db
    .update(goalPosts)
    .set({ body })
    .where(and(eq(goalPosts.id, postId), eq(goalPosts.userId, userId)))
    .returning(columns);
  return post ?? null;
}

export async function deletePost(userId: string, postId: string): Promise<boolean> {
  const rows = await db
    .delete(goalPosts)
    .where(and(eq(goalPosts.id, postId), eq(goalPosts.userId, userId)))
    .returning({ id: goalPosts.id });
  return rows.length > 0;
}
