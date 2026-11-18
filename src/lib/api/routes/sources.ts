import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";
import { and, eq } from "drizzle-orm";

import { db } from "@/db";
import { goalSources } from "@/db/schema";
import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { PROVIDER_KEYS } from "@/lib/providers";
import { sourceInputSchema } from "@/lib/source-schema";
import { createSource, deleteSource, getGoal, listSources, updateSource, type SourceDTO } from "@/lib/sources";

/*
 * A goal's sources: which connected apps its progress reads look at, and how each relates, in
 * the person's words. For the goal page's Sources section (sources-section.tsx, source-dialog.tsx).
 */

export const SourceSchema = z
  .object({
    id: z.string(),
    connectionId: z.string(),
    provider: z.enum(PROVIDER_KEYS),
    relation: z.string().openapi({ description: "Where to look, what counts and what to ignore." }),
    enabled: z.boolean(),
    lastError: z.string().nullable().openapi({ description: "Set when the last read couldn't use it." }),
  })
  .openapi("Source");

export function asSource(source: SourceDTO): z.infer<typeof SourceSchema> {
  return { ...source };
}

const SOURCE_GONE = "That source doesn’t exist anymore.";
const NOT_SAVED = "Couldn’t save that source. Is the app still connected?";
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const sourceParam = z.object({ sourceId: z.uuid().openapi({ param: { name: "sourceId", in: "path" } }) });
const SourceInputSchema = z.object({ connectionId: z.string(), relation: z.string() }).openapi("SourceInput");
const sourceResponse = { description: "OK", content: { "application/json": { schema: SourceSchema } } };

const addRoute = createRoute({
  method: "post",
  path: "/goals/{id}/sources",
  operationId: "addSource",
  summary: "Add a connected app as a source for the goal",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: SourceInputSchema } } } },
  responses: { 201: { ...sourceResponse, description: "Added" }, ...errorResponses, 404: notFound },
});

const editRoute = createRoute({
  method: "patch",
  path: "/sources/{sourceId}",
  operationId: "editSource",
  summary: "Change how a source relates to its goal",
  security: [{ bearerAuth: [] }],
  request: { params: sourceParam, body: { required: true, content: { "application/json": { schema: SourceInputSchema } } } },
  responses: { 200: sourceResponse, ...errorResponses, 404: notFound },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/sources/{sourceId}",
  operationId: "deleteSource",
  summary: "Remove a source; the app itself stays connected",
  security: [{ bearerAuth: [] }],
  request: { params: sourceParam },
  responses: { 204: { description: "Removed" }, 401: errorResponses[401], 404: notFound },
});

/** The saved source, as the goal lists it (with its provider). */
async function findSource(userId: string, goalId: string, sourceId: string) {
  return (await listSources(userId, goalId)).find((s) => s.id === sourceId) ?? null;
}

export const sources = new OpenAPIHono<ApiEnv>()
  .openapi(addRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const input = sourceInputSchema.safeParse(c.req.valid("json"));
    if (!input.success) return c.json(apiError("invalid_request", input.error.issues[0]?.message ?? "Check the form."), 400);
    if (!(await getGoal(userId, id))) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    const saved = await createSource(userId, id, input.data);
    const source = saved && (await findSource(userId, id, saved.id));
    if (!source) return c.json(apiError("not_saved", NOT_SAVED), 400);
    return c.json(asSource(source), 201);
  })
  .openapi(editRoute, async (c) => {
    const userId = c.var.user.id;
    const { sourceId } = c.req.valid("param");
    const input = sourceInputSchema.safeParse(c.req.valid("json"));
    if (!input.success) return c.json(apiError("invalid_request", input.error.issues[0]?.message ?? "Check the form."), 400);
    const saved = await updateSource(userId, sourceId, input.data);
    if (!saved) return c.json(apiError("not_found", NOT_SAVED), 404);
    // Look it up across the person's goals, since the route only has the source's id.
    const source = await findSourceAnywhere(userId, sourceId);
    if (!source) return c.json(apiError("not_found", SOURCE_GONE), 404);
    return c.json(asSource(source), 200);
  })
  .openapi(deleteRoute, async (c) => {
    if (!(await deleteSource(c.var.user.id, c.req.valid("param").sourceId))) {
      return c.json(apiError("not_found", SOURCE_GONE), 404);
    }
    return c.body(null, 204);
  });

/** A source by its id alone, looked up through the goal it belongs to. */
async function findSourceAnywhere(userId: string, sourceId: string) {
  const [row] = await db
    .select({ goalId: goalSources.goalId })
    .from(goalSources)
    .where(and(eq(goalSources.id, sourceId), eq(goalSources.userId, userId)));
  return row ? findSource(userId, row.goalId, sourceId) : null;
}
