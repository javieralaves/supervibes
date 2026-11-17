import * as z from "zod";

export const MAX_RELATION = 1500;

/** Shared by the source dialog (client) and the server actions. */
export const sourceInputSchema = z.object({
  connectionId: z.uuid("Pick a connected app."),
  /** Where to look and how it relates to the goal, in the user's own words. */
  relation: z
    .string()
    .trim()
    .min(10, "Say where to look and how it relates to this goal.")
    .max(MAX_RELATION, "Keep it under 1,500 characters."),
});

export type SourceInput = z.infer<typeof sourceInputSchema>;
