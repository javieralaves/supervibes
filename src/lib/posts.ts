import "server-only";

import { and, desc, eq } from "drizzle-orm";

import { db } from "@/db";
import { goalPosts, goals } from "@/db/schema";

/*
 * Notes the user posts on a goal. Same rule as everything else: every query
 * filters on the owner, and writes check the goal belongs to them.
 */

export type PostDTO = { id: string; body: string; createdAt: Date; updatedAt: Date };

const columns = {
  id: goalPosts.id,
  body: goalPosts.body,
  createdAt: goalPosts.createdAt,
  updatedAt: goalPosts.updatedAt,
};

/** Newest first. */
export async function listPosts(userId: string, goalId: string, limit = 100): Promise<PostDTO[]> {
  return db
    .select(columns)
    .from(goalPosts)
    .where(and(eq(goalPosts.goalId, goalId), eq(goalPosts.userId, userId)))
    .orderBy(desc(goalPosts.createdAt))
    .limit(limit);
}

export async function createPost(userId: string, goalId: string, body: string): Promise<PostDTO | null> {
  const [goal] = await db
    .select({ id: goals.id })
    .from(goals)
    .where(and(eq(goals.id, goalId), eq(goals.userId, userId)));
  if (!goal) return null;
  const [post] = await db.insert(goalPosts).values({ userId, goalId, body }).returning(columns);
  return post;
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
