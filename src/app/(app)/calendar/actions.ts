"use server";

import { refresh } from "next/cache";
import * as z from "zod";

import { AgendaError, prepareAgenda } from "@/lib/agenda";
import { requestRead } from "@/lib/background-read";
import { createBlock, deleteBlock, getBlock, updateBlock } from "@/lib/blocks";
import {
  blockDescriptionSchema,
  blockDetailsSchema,
  blockTimesSchema,
  newBlockSchema,
  type BlockAgenda,
} from "@/lib/block-schema";
import { createRecapPost } from "@/lib/posts";
import { postBodySchema } from "@/lib/post-schema";
import { discardRecap, prepareRecap, RecapError } from "@/lib/recap";
import { postRecapSchema, type BlockRecap } from "@/lib/recap-schema";
import { requireUser } from "@/lib/session";
import { taskDaySchema } from "@/lib/task-schema";
import { getTask, markTaskDone, planTaskForBlock, updateTask } from "@/lib/tasks";

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
    startsAt: new Date(when.data.startsAt),
    endsAt: new Date(when.data.endsAt),
  });
  if (!block) return { ok: false, error: "That goal doesn't exist anymore." };
  await planTaskForBlock(user.id, block);
  refresh();
  return { ok: true };
}

/**
 * A task dropped on a day's strip: planned for that day, without a time. If it had
 * a time on the calendar that hasn't started yet, that block goes, since the day
 * is now the plan. `day` null takes it off the day.
 */
export async function planTaskAction(taskId: unknown, day: unknown, unscheduleBlockId?: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(taskId);
  const plannedFor = taskDaySchema.safeParse(day);
  if (!id.success) return { ok: false, error: "That task doesn't exist anymore." };
  if (!plannedFor.success) return { ok: false, error: firstIssue(plannedFor.error) };
  if (unscheduleBlockId !== undefined) {
    const blockId = idSchema.safeParse(unscheduleBlockId);
    const block = blockId.success ? await getBlock(user.id, blockId.data) : null;
    // Only its own block, and only one that hasn't started: a past session is a record.
    if (block && block.taskId === id.data && block.startsAt.getTime() > Date.now()) {
      await deleteBlock(user.id, block.id);
    }
  }
  if (!(await updateTask(user.id, id.data, { plannedFor: plannedFor.data }))) {
    return { ok: false, error: "That task doesn't exist anymore." };
  }
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
    title: intention ? (parsed.data.title ?? before.title) : parsed.data.title,
    // An agenda or draft recap is about one goal; moving the block to another goal clears them.
    ...(parsed.data.goalId !== before.goalId ? { agenda: null, recap: null } : {}),
  });
  if (!block) return { ok: false, error: GONE };
  refresh();
  return { ok: true };
}

/** What the person wants out of a block of protected time, written in the block panel. */
export async function setBlockDescriptionAction(blockId: unknown, description: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  const parsed = blockDescriptionSchema.safeParse(description);
  if (!id.success) return { ok: false, error: GONE };
  if (!parsed.success) return { ok: false, error: firstIssue(parsed.error) };
  const before = await getBlock(user.id, id.data);
  if (!before) return { ok: false, error: GONE };
  // An intention's task already says what it's for.
  if (before.fromSuggestion || before.taskId) return { ok: false, error: "This block already schedules a task." };
  if (before.description === parsed.data) return { ok: true };
  if (!(await updateBlock(user.id, id.data, { description: parsed.data }))) return { ok: false, error: GONE };
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
  await planTaskForBlock(user.id, block);
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

/** "Recap session" in the block panel: a draft of what happened, stored on the block. */
export async function prepareRecapAction(
  blockId: unknown,
): Promise<{ ok: true; recap: BlockRecap } | { ok: false; error: string }> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  if (!id.success) return { ok: false, error: GONE };
  try {
    const recap = await prepareRecap(user.id, id.data);
    refresh();
    return { ok: true, recap };
  } catch (error) {
    if (error instanceof RecapError) return { ok: false, error: error.message };
    console.error("[recap] failed", error);
    return { ok: false, error: "Couldn't recap this session right now. Try again." };
  }
}

/**
 * Posts a recap to the goal's activity, as written or edited by the person.
 * Only breadcrumbs from the stored draft can be kept, picked by their links.
 */
export async function postRecapAction(blockId: unknown, input: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  const parsed = postRecapSchema.safeParse(input);
  if (!id.success) return { ok: false, error: GONE };
  if (!parsed.success) return { ok: false, error: firstIssue(parsed.error) };
  const body = postBodySchema.safeParse(parsed.data.body);
  if (!body.success) return { ok: false, error: firstIssue(body.error) };

  const block = await getBlock(user.id, id.data);
  if (!block) return { ok: false, error: GONE };
  if (block.endsAt.getTime() > Date.now()) return { ok: false, error: "This session hasn't ended yet." };

  const keep = new Set(parsed.data.keep);
  const post = await createRecapPost(user.id, {
    goalId: block.goalId,
    blockId: block.id,
    body: body.data,
    session: {
      title: block.title ?? block.fromSuggestion ?? "Protected time",
      startsAt: block.startsAt.toISOString(),
      endsAt: block.endsAt.toISOString(),
      aim: block.description,
    },
    breadcrumbs: (block.recap?.breadcrumbs ?? []).filter((b) => keep.has(b.url)),
  });
  if (!post) return { ok: false, error: "This session already has a recap." };

  if (parsed.data.markTaskDone && block.taskId) await markTaskDone(user.id, block.taskId, true);
  await discardRecap(user.id, block.id);
  // The recap should change the goal's read; it runs after this returns.
  await requestRead(user.id, block.goalId, { trigger: "recap" });
  refresh();
  return { ok: true };
}

/** "Discard" on a draft recap. */
export async function discardRecapAction(blockId: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const id = idSchema.safeParse(blockId);
  if (!id.success || !(await getBlock(user.id, id.data))) return { ok: false, error: GONE };
  await discardRecap(user.id, id.data);
  refresh();
  return { ok: true };
}
