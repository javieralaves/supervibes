"use server";

import { refresh } from "next/cache";
import * as z from "zod";

import { AgendaError, prepareAgenda } from "@/lib/agenda";
import { createBlock, deleteBlock, getBlock, updateBlock } from "@/lib/blocks";
import { blockDetailsSchema, blockTimesSchema, newBlockSchema, type BlockAgenda } from "@/lib/block-schema";
import { requireUser } from "@/lib/session";
import { getTask, markTaskDone } from "@/lib/tasks";

export type BlockResult = { ok: true } | { ok: false; error: string };

const idSchema = z.uuid();
const GONE = "That block doesn't exist anymore.";

const firstIssue = (error: z.ZodError) => error.issues[0]?.message ?? "Check the details.";

/** Protected time, made by dragging on the calendar. */
export async function createBlockAction(input: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const parsed = newBlockSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: firstIssue(parsed.error) };
  const { startsAt, endsAt, ...details } = parsed.data;
  const block = await createBlock(user.id, { ...details, startsAt: new Date(startsAt), endsAt: new Date(endsAt) });
  if (!block) return { ok: false, error: "That goal doesn't exist anymore." };
  refresh();
  return { ok: true };
}

/** A task dragged from the task panel onto the day: schedule it at that time. */
export async function scheduleTaskAction(taskId: unknown, times: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(taskId);
  const when = blockTimesSchema.safeParse(times);
  if (!id.success) return { ok: false, error: "That task doesn't exist anymore." };
  if (!when.success) return { ok: false, error: firstIssue(when.error) };
  const task = await getTask(user.id, id.data);
  if (!task) return { ok: false, error: "That task doesn't exist anymore." };
  const block = await createBlock(user.id, {
    goalId: task.goalId,
    title: task.title,
    taskId: task.id,
    keepOpen: false,
    startsAt: new Date(when.data.startsAt),
    endsAt: new Date(when.data.endsAt),
  });
  if (!block) return { ok: false, error: "That goal doesn't exist anymore." };
  refresh();
  return { ok: true };
}

/** "Mark done" on an intention: checks its task off, posting it to the goal's activity. */
export async function setBlockTaskDoneAction(blockId: unknown, done: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  if (!id.success || typeof done !== "boolean") return { ok: false, error: GONE };
  const block = await getBlock(user.id, id.data);
  if (!block?.taskId) return { ok: false, error: "That task doesn't exist anymore." };
  if (!(await markTaskDone(user.id, block.taskId, done))) return { ok: false, error: "That task doesn't exist anymore." };
  refresh();
  return { ok: true };
}

export async function updateBlockAction(blockId: unknown, input: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  const parsed = blockDetailsSchema.safeParse(input);
  if (!id.success) return { ok: false, error: GONE };
  if (!parsed.success) return { ok: false, error: firstIssue(parsed.error) };
  const before = await getBlock(user.id, id.data);
  if (!before) return { ok: false, error: GONE };
  // An intention keeps its task; only its goal and title can change.
  const intention = Boolean(before.fromSuggestion || before.taskId);
  const block = await updateBlock(user.id, id.data, {
    ...parsed.data,
    keepOpen: intention ? false : parsed.data.keepOpen,
    title: intention ? (parsed.data.title ?? before.title) : parsed.data.title,
    // An agenda is about one goal; moving the block to another goal clears it.
    ...(parsed.data.goalId !== before.goalId ? { agenda: null } : {}),
  });
  if (!block) return { ok: false, error: GONE };
  refresh();
  return { ok: true };
}

export async function moveBlockAction(blockId: unknown, times: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  const when = blockTimesSchema.safeParse(times);
  if (!id.success) return { ok: false, error: GONE };
  if (!when.success) return { ok: false, error: firstIssue(when.error) };
  const block = await updateBlock(user.id, id.data, {
    startsAt: new Date(when.data.startsAt),
    endsAt: new Date(when.data.endsAt),
  });
  if (!block) return { ok: false, error: GONE };
  refresh();
  return { ok: true };
}

export async function deleteBlockAction(blockId: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  if (!id.success || !(await deleteBlock(user.id, id.data))) return { ok: false, error: GONE };
  refresh();
  return { ok: true };
}

/** "Prepare agenda" in the block panel: a short plan for this session, stored on the block. */
export async function prepareAgendaAction(
  blockId: unknown,
  when: unknown,
): Promise<{ ok: true; agenda: BlockAgenda } | { ok: false; error: string }> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  const label = z.string().trim().min(1).max(120).safeParse(when);
  if (!id.success) return { ok: false, error: GONE };
  if (!label.success) return { ok: false, error: "Couldn't tell when this block is." };
  try {
    const agenda = await prepareAgenda(user.id, id.data, label.data);
    refresh();
    return { ok: true, agenda };
  } catch (error) {
    if (error instanceof AgendaError) return { ok: false, error: error.message };
    console.error("[agenda] failed", error);
    return { ok: false, error: "Couldn't prepare an agenda right now. Try again." };
  }
}
