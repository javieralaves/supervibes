import { z } from "@hono/zod-openapi";

/*
 * Every API error has the same shape. `message` is written for people (the app shows it as is);
 * `code` is for code to branch on.
 */

export const ErrorSchema = z
  .object({
    error: z.object({
      code: z.string().openapi({ example: "not_found" }),
      message: z.string().openapi({ example: "That block doesn't exist anymore." }),
    }),
  })
  .openapi("Error");

export type ApiError = z.infer<typeof ErrorSchema>;

export function apiError(code: string, message: string): ApiError {
  return { error: { code, message } };
}

/** OpenAPI response entries for the errors most routes can return. */
export const errorResponses = {
  400: { description: "The request didn't make sense.", content: { "application/json": { schema: ErrorSchema } } },
  401: { description: "Not signed in, or the session ended.", content: { "application/json": { schema: ErrorSchema } } },
} as const;
