"use server";

import { refresh } from "next/cache";
import * as z from "zod";

import { createBlock, deleteBlock, getBlock, tryMatchBlockFits, updateBlock } from "@/lib/blocks";
import { blockDetailsSchema, blockTimesSchema, newBlockSchema } from "@/lib/block-schema";
import { requireUser } from "@/lib/session";

export type BlockResult = { ok: true } | { ok: false; error: string };

const idSchema = z.uuid();
const GONE = "That block doesn't exist anymore.";

const firstIssue = (error: z.ZodError) => error.issues[0]?.message ?? "Check the details.";

/** A titled protected block needs its fits judged; nothing else does. */
const needsMatching = (b: { title: string | null; keepOpen: boolean; fromSuggestion: string | null }) =>
  Boolean(b.title) && !b.keepOpen && !b.fromSuggestion;

/** Protected time, made by dragging on the calendar. */
export async function createBlockAction(input: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const parsed = newBlockSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: firstIssue(parsed.error) };
  const { startsAt, endsAt, ...details } = parsed.data;
  const block = await createBlock(user.id, { ...details, startsAt: new Date(startsAt), endsAt: new Date(endsAt) });
  if (!block) return { ok: false, error: "That goal doesn't exist anymore." };
  if (needsMatching(block)) await tryMatchBlockFits(user.id, block.goalId);
  refresh();
  return { ok: true };
}

/** An intention: commits a suggestion to the time it was shown at. */
export async function createIntentionAction(goalId: unknown, suggestion: unknown, times: unknown): Promise<BlockResult> {
  const user = await requireUser();
  const goal = idSchema.safeParse(goalId);
  const title = z.string().trim().min(1).max(200).safeParse(suggestion);
  const when = blockTimesSchema.safeParse(times);
  if (!goal.success || !title.success) return { ok: false, error: "That suggestion doesn't exist anymore." };
  if (!when.success) return { ok: false, error: firstIssue(when.error) };
  const block = await createBlock(user.id, {
    goalId: goal.data,
    title: title.data,
    fromSuggestion: title.data,
    keepOpen: false,
    startsAt: new Date(when.data.startsAt),
    endsAt: new Date(when.data.endsAt),
  });
  if (!block) return { ok: false, error: "That goal doesn't exist anymore." };
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
  const block = await updateBlock(user.id, id.data, {
    ...parsed.data,
    keepOpen: before.fromSuggestion ? false : parsed.data.keepOpen,
    title: before.fromSuggestion ? (parsed.data.title ?? before.title) : parsed.data.title,
  });
  if (!block) return { ok: false, error: GONE };
  if (needsMatching(block)) await tryMatchBlockFits(user.id, block.goalId);
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
