"use server";

import { refresh } from "next/cache";
import * as z from "zod";

import { postBodySchema } from "@/lib/post-schema";
import { createPost, deletePost, updatePost } from "@/lib/posts";
import { sourceInputSchema } from "@/lib/source-schema";
import { createSource, deleteSource, updateSource } from "@/lib/sources";
import { tryMatchBlockFits } from "@/lib/blocks";
import { assessGoal, completeSuggestion, passOnSuggestion, ProgressError } from "@/lib/progress";
import { requireUser } from "@/lib/session";
import { taskPatchSchema, taskTitleSchema } from "@/lib/task-schema";
import { createTask, deleteTask, setTaskDone, updateTask } from "@/lib/tasks";

export type ActionResult = { ok: true; message?: string } | { ok: false; error: string };

const idSchema = z.uuid();

export async function saveSourceAction(
  goalId: unknown,
  sourceId: unknown,
  input: unknown,
): Promise<ActionResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const parsed = sourceInputSchema.safeParse(input);
  if (!goal.success) return { ok: false, error: "That goal doesn't exist." };
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the form." };

  const existing = sourceId === null ? null : idSchema.safeParse(sourceId);
  if (existing && !existing.success) return { ok: false, error: "That source doesn't exist." };

  const saved = existing
    ? await updateSource(user.id, existing.data, parsed.data)
    : await createSource(user.id, goal.data, parsed.data);
  if (!saved) return { ok: false, error: "Couldn't save that source. Is the app still connected?" };

  refresh();
  return { ok: true };
}

export async function deleteSourceAction(sourceId: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(sourceId);
  if (!id.success || !(await deleteSource(user.id, id.data))) {
    return { ok: false, error: "That source doesn't exist anymore." };
  }
  refresh();
  return { ok: true };
}

export async function refreshProgressAction(goalId: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(goalId);
  if (!id.success) return { ok: false, error: "That goal doesn't exist." };

  try {
    await assessGoal(user.id, id.data);
    // New suggestions: re-judge which fit the goal's titled blocks of time.
    await tryMatchBlockFits(user.id, id.data);
    refresh();
    return { ok: true };
  } catch (error) {
    if (!(error instanceof ProgressError)) console.error("[progress] read failed", error);
    refresh();
    return { ok: false, error: error instanceof ProgressError ? error.message : "Couldn't read progress. Try again." };
  }
}

export async function addPostAction(goalId: unknown, body: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const parsed = postBodySchema.safeParse(body);
  if (!goal.success) return { ok: false, error: "That goal doesn't exist." };
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the note." };

  const post = await createPost(user.id, goal.data, parsed.data);
  if (!post) return { ok: false, error: "That goal doesn't exist anymore." };
  refresh();
  return { ok: true };
}

export async function editPostAction(postId: unknown, body: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(postId);
  const parsed = postBodySchema.safeParse(body);
  if (!id.success) return { ok: false, error: "That note doesn't exist." };
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the note." };

  const post = await updatePost(user.id, id.data, parsed.data);
  if (!post) return { ok: false, error: "That note doesn't exist anymore." };
  refresh();
  return { ok: true };
}

export async function deletePostAction(postId: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(postId);
  if (!id.success || !(await deletePost(user.id, id.data))) {
    return { ok: false, error: "That note doesn't exist anymore." };
  }
  refresh();
  return { ok: true };
}

const suggestionTitleSchema = z.string().trim().min(1).max(140);

/** "Done" on a suggestion: post the note the person wrote (prefilled "Done: …") and remove it. */
export async function completeSuggestionAction(
  goalId: unknown,
  title: unknown,
  note: unknown,
): Promise<ActionResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const parsed = suggestionTitleSchema.safeParse(title);
  if (!goal.success || !parsed.success) return { ok: false, error: "That suggestion doesn't exist anymore." };
  const body = postBodySchema.safeParse(note ?? `Done: ${parsed.data}`);
  if (!body.success) return { ok: false, error: body.error.issues[0]?.message ?? "Check the note." };

  const post = await createPost(user.id, goal.data, body.data, parsed.data);
  if (!post) return { ok: false, error: "That goal doesn't exist anymore." };
  await completeSuggestion(user.id, goal.data, parsed.data);
  refresh();
  return { ok: true };
}

/** "Not now" on a next move: hide it and keep later reads from suggesting it again. */
export async function passOnSuggestionAction(goalId: unknown, title: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const parsed = suggestionTitleSchema.safeParse(title);
  if (!goal.success || !parsed.success) return { ok: false, error: "That suggestion doesn't exist anymore." };

  if (!(await passOnSuggestion(user.id, goal.data, parsed.data))) {
    return { ok: false, error: "That suggestion doesn't exist anymore." };
  }
  refresh();
  return { ok: true };
}

const TASK_GONE = "That task doesn't exist anymore.";

export async function addTaskAction(goalId: unknown, title: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const parsed = taskTitleSchema.safeParse(title);
  if (!goal.success) return { ok: false, error: "That goal doesn't exist anymore." };
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the task." };
  if (!(await createTask(user.id, goal.data, parsed.data))) return { ok: false, error: "That goal doesn't exist anymore." };
  refresh();
  return { ok: true };
}

export async function editTaskAction(taskId: unknown, patch: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(taskId);
  const parsed = taskPatchSchema.safeParse(patch);
  if (!id.success) return { ok: false, error: TASK_GONE };
  if (!parsed.success) return { ok: false, error: parsed.error.issues[0]?.message ?? "Check the task." };
  if (!(await updateTask(user.id, id.data, parsed.data))) return { ok: false, error: TASK_GONE };
  refresh();
  return { ok: true };
}

export async function setTaskDoneAction(taskId: unknown, done: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(taskId);
  if (!id.success || typeof done !== "boolean") return { ok: false, error: TASK_GONE };
  if (!(await setTaskDone(user.id, id.data, done))) return { ok: false, error: TASK_GONE };
  refresh();
  return { ok: true };
}

export async function deleteTaskAction(taskId: unknown): Promise<ActionResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(taskId);
  if (!id.success || !(await deleteTask(user.id, id.data))) return { ok: false, error: TASK_GONE };
  refresh();
  return { ok: true };
}
