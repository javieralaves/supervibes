import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { requestRead } from "@/lib/background-read";
import { postBodySchema } from "@/lib/post-schema";
import { createPost, deletePost, updatePost, type PostDTO } from "@/lib/posts";
import { PROVIDER_KEYS } from "@/lib/providers";

/*
 * A goal's activity: notes, recaps, and entries for checked-off tasks and suggestions, for the
 * goal page's Activity section (app/(app)/goals/[id]/notes-section.tsx and its actions).
 * Reopening a task from its entry is PUT /tasks/{taskId}/done with done: false.
 */

export const NoteSchema = z
  .object({
    id: z.string(),
    body: z.string(),
    completedSuggestion: z.string().nullable().openapi({ description: "Set when posted by finishing a suggestion." }),
    completedTask: z.string().nullable().openapi({ description: "Set when posted by checking a task off." }),
    taskId: z.string().nullable().openapi({ description: "That task, while it still exists, so it can be reopened." }),
    taskDescription: z.string().nullable(),
    session: z
      .object({
        title: z.string(),
        startsAt: z.iso.datetime(),
        endsAt: z.iso.datetime(),
        aim: z.string().nullable(),
      })
      .nullable()
      .openapi({ description: "The calendar session this recaps, on recaps." }),
    breadcrumbs: z
      .array(z.object({ provider: z.enum(PROVIDER_KEYS), title: z.string(), url: z.string() }).openapi("Breadcrumb"))
      .openapi({ description: "Things in connected apps a recap drew on; empty when none." }),
    createdAt: z.iso.datetime(),
    updatedAt: z.iso.datetime(),
  })
  .openapi("Note");

export function asNote(post: PostDTO): z.infer<typeof NoteSchema> {
  return {
    id: post.id,
    body: post.body,
    completedSuggestion: post.completedSuggestion,
    completedTask: post.completedTask,
    taskId: post.taskId,
    taskDescription: post.taskDescription ?? null,
    session: post.session && {
      title: post.session.title,
      startsAt: new Date(post.session.startsAt).toISOString(),
      endsAt: new Date(post.session.endsAt).toISOString(),
      aim: post.session.aim ?? null,
    },
    breadcrumbs: post.breadcrumbs ?? [],
    createdAt: post.createdAt.toISOString(),
    updatedAt: post.updatedAt.toISOString(),
  };
}

const NOTE_GONE = "That note doesn’t exist anymore.";
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const noteParam = z.object({ noteId: z.uuid().openapi({ param: { name: "noteId", in: "path" } }) });
const NoteBodySchema = z.object({ body: z.string() }).openapi("NoteBody");
const noteResponse = { description: "OK", content: { "application/json": { schema: NoteSchema } } };

const postRoute = createRoute({
  method: "post",
  path: "/goals/{id}/notes",
  operationId: "postNote",
  summary: "Post a note; a progress read follows in the background",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: NoteBodySchema } } } },
  responses: { 201: { ...noteResponse, description: "Posted" }, ...errorResponses, 404: notFound },
});

const editRoute = createRoute({
  method: "patch",
  path: "/notes/{noteId}",
  operationId: "editNote",
  summary: "Change a note's text",
  security: [{ bearerAuth: [] }],
  request: { params: noteParam, body: { required: true, content: { "application/json": { schema: NoteBodySchema } } } },
  responses: { 200: noteResponse, ...errorResponses, 404: notFound },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/notes/{noteId}",
  operationId: "deleteNote",
  summary: "Delete a note or activity entry",
  security: [{ bearerAuth: [] }],
  request: { params: noteParam },
  responses: { 204: { description: "Deleted" }, 401: errorResponses[401], 404: notFound },
});

export const notes = new OpenAPIHono<ApiEnv>()
  .openapi(postRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const body = postBodySchema.safeParse(c.req.valid("json").body);
    if (!body.success) return c.json(apiError("invalid_request", body.error.issues[0]?.message ?? "Check the note."), 400);
    const post = await createPost(userId, id, body.data);
    if (!post) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    // A new note should change the read; it runs after this returns, as on the web.
    await requestRead(userId, id, { trigger: "note" });
    return c.json(asNote(post), 201);
  })
  .openapi(editRoute, async (c) => {
    const body = postBodySchema.safeParse(c.req.valid("json").body);
    if (!body.success) return c.json(apiError("invalid_request", body.error.issues[0]?.message ?? "Check the note."), 400);
    const post = await updatePost(c.var.user.id, c.req.valid("param").noteId, body.data);
    if (!post) return c.json(apiError("not_found", NOTE_GONE), 404);
    return c.json(asNote(post), 200);
  })
  .openapi(deleteRoute, async (c) => {
    if (!(await deletePost(c.var.user.id, c.req.valid("param").noteId))) return c.json(apiError("not_found", NOTE_GONE), 404);
    return c.body(null, 204);
  });
