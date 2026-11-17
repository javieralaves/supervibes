import * as z from "zod";

/* Client-safe task shapes. Storage lives in tasks.ts. */

export const TASK_MINUTES = [15, 30, 60, 120] as const;
export const DEFAULT_TASK_MINUTES = 30;
export const MAX_TASK_TITLE = 200;

export const taskTitleSchema = z
  .string()
  .trim()
  .min(1, "Write the task first.")
  .max(MAX_TASK_TITLE, `Keep it under ${MAX_TASK_TITLE} characters.`);

export const taskMinutesSchema = z.union(TASK_MINUTES.map((m) => z.literal(m)) as [
  z.ZodLiteral<15>,
  z.ZodLiteral<30>,
  z.ZodLiteral<60>,
  z.ZodLiteral<120>,
]);

export const taskPatchSchema = z
  .object({ title: taskTitleSchema, minutes: taskMinutesSchema })
  .partial()
  .refine((p) => p.title !== undefined || p.minutes !== undefined, "Nothing to change.");

export function minutesLabel(minutes: number) {
  return minutes >= 60 ? `${minutes / 60} hr` : `${minutes} min`;
}
