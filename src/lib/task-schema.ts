import * as z from "zod";

/* Client-safe task shapes. Storage lives in tasks.ts. */

export const TASK_MINUTES = [15, 30, 60, 120] as const;
export const DEFAULT_TASK_MINUTES = 30;
export const MAX_TASK_TITLE = 200;
export const MAX_TASK_DESCRIPTION = 2000;

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

/** Empty means no description. */
export const taskDescriptionSchema = z
  .string()
  .trim()
  .max(MAX_TASK_DESCRIPTION, `Keep the description under ${MAX_TASK_DESCRIPTION} characters.`)
  .nullable()
  .transform((d) => d || null);

export const taskPatchSchema = z
  .object({ title: taskTitleSchema, description: taskDescriptionSchema, minutes: taskMinutesSchema })
  .partial()
  .refine((p) => Object.values(p).some((v) => v !== undefined), "Nothing to change.");

export function minutesLabel(minutes: number) {
  return minutes >= 60 ? `${minutes / 60} hr` : `${minutes} min`;
}
