"use server";

import { refresh } from "next/cache";

import { goalIdSchema, goalInputSchema, MAX_GOALS } from "@/lib/goal-schema";
import { createGoal, deleteGoal, GoalLimitError, updateGoal } from "@/lib/goals";
import { requireUser } from "@/lib/session";

export type GoalActionResult = { ok: true } | { ok: false; error: string };

function invalid(error: { issues: { message: string }[] }): GoalActionResult {
  return { ok: false, error: error.issues[0]?.message ?? "Check the form." };
}

export async function createGoalAction(input: unknown): Promise<GoalActionResult> {
  const user = await requireUser();
  const parsed = goalInputSchema.safeParse(input);
  if (!parsed.success) return invalid(parsed.error);

  try {
    await createGoal(user.id, parsed.data);
  } catch (error) {
    if (error instanceof GoalLimitError) {
      return { ok: false, error: `You can have up to ${MAX_GOALS} goals.` };
    }
    throw error;
  }

  refresh();
  return { ok: true };
}

export async function updateGoalAction(id: unknown, input: unknown): Promise<GoalActionResult> {
  const user = await requireUser();
  const goalId = goalIdSchema.safeParse(id);
  const parsed = goalInputSchema.safeParse(input);
  if (!goalId.success) return { ok: false, error: "That goal doesn't exist." };
  if (!parsed.success) return invalid(parsed.error);

  const goal = await updateGoal(user.id, goalId.data, parsed.data);
  if (!goal) return { ok: false, error: "That goal doesn't exist anymore." };

  refresh();
  return { ok: true };
}

export async function deleteGoalAction(id: unknown): Promise<GoalActionResult> {
  const user = await requireUser();
  const goalId = goalIdSchema.safeParse(id);
  if (!goalId.success) return { ok: false, error: "That goal doesn't exist." };

  const deleted = await deleteGoal(user.id, goalId.data);
  if (!deleted) return { ok: false, error: "That goal doesn't exist anymore." };

  refresh();
  return { ok: true };
}
