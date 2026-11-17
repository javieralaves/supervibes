import * as z from "zod";

export const MAX_POST = 2000;

/** Shared by the notes composer (client) and the server actions. */
export const postBodySchema = z
  .string()
  .trim()
  .min(1, "Write something first.")
  .max(MAX_POST, "Keep notes under 2,000 characters.");
