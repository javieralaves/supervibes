import * as z from "zod";

import { GOAL_COLOR_KEYS } from "@/lib/goal-colors";
import { GOAL_ICON_NAMES } from "@/lib/goal-icons";

/** Soft cap so goals stay "a handful". */
export const MAX_GOALS = 12;
export const MAX_GOAL_TITLE = 120;

/** Shared by the dialog (client) and the server actions. */
export const goalInputSchema = z.object({
  title: z
    .string()
    .trim()
    .min(1, "Give your goal a name.")
    .max(MAX_GOAL_TITLE, `Keep it under ${MAX_GOAL_TITLE} characters.`),
  icon: z.enum(GOAL_ICON_NAMES),
  color: z.enum(GOAL_COLOR_KEYS),
});

export type GoalInput = z.infer<typeof goalInputSchema>;

export const goalIdSchema = z.uuid();
