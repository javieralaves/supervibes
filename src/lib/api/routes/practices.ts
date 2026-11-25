import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import {
  addPracticeSession,
  deletePracticeSession,
  FutureSessionError,
  MissedError,
  pausePractice,
  resumePractice,
  setBlockMissed,
  updatePracticeSession,
  type OffCalendarDTO,
} from "@/lib/practice";
import { getTimeZone } from "@/lib/settings";
import { addDays, todayIn } from "@/lib/target-date";

/*
 * What only a practice has: sessions off the calendar (one logged, or one meant for a day with no time yet), pausing,
 * and saying a block didn't happen. The practice itself, its count and its status come with the goals
 * (src/lib/api/routes/goals.ts).
 */

const OffCalendarSessionSchema = z
  .object({
    id: z.string(),
    day: z.iso.date().openapi({ description: "The day it's for, in the person's own calendar." }),
    doneAt: z.iso.datetime().nullable().openapi({ description: "When it was done; null while it's only planned for its day." }),
  })
  .openapi("OffCalendarSession");

const NewSessionSchema = z
  .object({
    day: z.iso.date().optional().openapi({ description: "Left out: today, in the person's calendar." }),
    done: z.boolean().openapi({ description: "True logs one done; false plans one for the day, with no time." }),
  })
  .openapi("NewPracticeSession");

const SessionPatchSchema = z
  .object({
    day: z.iso.date().optional().openapi({ description: "Move it to another day. Left out keeps it." }),
    done: z.boolean().optional().openapi({ description: "Tick it off, or back. Left out keeps it." }),
  })
  .openapi("PracticeSessionPatch");

const PauseSchema = z
  .object({
    // An empty string, not null, for no end: the Mac app's generated client can't send an explicit null.
    resumesOn: z.string().openapi({
      description: "The day it picks up again (YYYY-MM-DD, after today), or an empty string to pause until it's resumed.",
    }),
  })
  .openapi("PracticePause");

const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const sessionParam = goalParam.extend({ sessionId: z.uuid().openapi({ param: { name: "sessionId", in: "path" } }) });
const blockParam = z.object({ blockId: z.uuid().openapi({ param: { name: "blockId", in: "path" } }) });
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const PRACTICE_GONE = "That practice doesn’t exist anymore.";
const SESSION_GONE = "That session doesn’t exist anymore.";
/** How far from today a session can be put, either way. */
const DAYS_EITHER_WAY = 60;

const sessionResponse = { description: "OK", content: { "application/json": { schema: OffCalendarSessionSchema } } };

const addRoute = createRoute({
  method: "post",
  path: "/goals/{id}/sessions",
  operationId: "addPracticeSession",
  summary: "Log a practice's session, or plan one for a day with no time",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: NewSessionSchema } } } },
  responses: { 201: { ...sessionResponse, description: "Added" }, ...errorResponses, 404: notFound },
});

const updateRoute = createRoute({
  method: "patch",
  path: "/goals/{id}/sessions/{sessionId}",
  operationId: "updatePracticeSession",
  summary: "Tick off a session planned for a day, or move it",
  security: [{ bearerAuth: [] }],
  request: { params: sessionParam, body: { required: true, content: { "application/json": { schema: SessionPatchSchema } } } },
  responses: { 200: sessionResponse, ...errorResponses, 404: notFound },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/goals/{id}/sessions/{sessionId}",
  operationId: "deletePracticeSession",
  summary: "Remove a session that isn't on the calendar",
  security: [{ bearerAuth: [] }],
  request: { params: sessionParam },
  responses: { 204: { description: "Removed" }, 401: errorResponses[401], 404: notFound },
});

const pauseRoute = createRoute({
  method: "put",
  path: "/goals/{id}/pause",
  operationId: "pausePractice",
  summary: "Pause a practice from today: its weeks stay out of its status and its area's",
  description: "Pausing one that's already paused changes when it picks up again.",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: PauseSchema } } } },
  responses: { 204: { description: "Paused" }, ...errorResponses, 404: notFound },
});

const resumeRoute = createRoute({
  method: "delete",
  path: "/goals/{id}/pause",
  operationId: "resumePractice",
  summary: "Pick a paused practice up again today",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam },
  responses: { 204: { description: "Resumed" }, 401: errorResponses[401], 404: notFound },
});

const missedRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/missed",
  operationId: "setBlockMissed",
  summary: "Say a practice's block didn't happen, so it doesn't count; or that it did after all",
  description: "Only for a practice's block, once it's over.",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: { required: true, content: { "application/json": { schema: z.object({ missed: z.boolean() }).openapi("BlockMissed") } } },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const asSession = (row: OffCalendarDTO) => ({ id: row.id, day: row.day, doneAt: row.doneAt?.toISOString() ?? null });

/** A day close enough to today to put a session on. */
function nearToday(day: string, today: string) {
  return day >= addDays(today, -DAYS_EITHER_WAY) && day <= addDays(today, DAYS_EITHER_WAY);
}

const TOO_FAR = `Pick a day within ${DAYS_EITHER_WAY} days of today.`;

export const practices = new OpenAPIHono<ApiEnv>()
  .openapi(addRoute, async (c) => {
    const userId = c.var.user.id;
    const { day, done } = c.req.valid("json");
    const today = todayIn(await getTimeZone(userId));
    const on = day ?? today;
    if (!nearToday(on, today)) return c.json(apiError("invalid_request", TOO_FAR), 400);
    if (done && on > today) return c.json(apiError("invalid_request", "It can’t be done on a day that hasn’t come yet."), 400);
    const row = await addPracticeSession(userId, c.req.valid("param").id, on, done);
    if (!row) return c.json(apiError("not_found", PRACTICE_GONE), 404);
    return c.json(asSession(row), 201);
  })
  .openapi(updateRoute, async (c) => {
    const userId = c.var.user.id;
    const { id, sessionId } = c.req.valid("param");
    const patch = c.req.valid("json");
    const today = todayIn(await getTimeZone(userId));
    if (patch.day !== undefined && !nearToday(patch.day, today)) return c.json(apiError("invalid_request", TOO_FAR), 400);
    if (patch.done && patch.day !== undefined && patch.day > today) {
      return c.json(apiError("invalid_request", "It can’t be done on a day that hasn’t come yet."), 400);
    }
    try {
      const row = await updatePracticeSession(userId, id, sessionId, patch, today);
      if (!row) return c.json(apiError("not_found", SESSION_GONE), 404);
      return c.json(asSession(row), 200);
    } catch (error) {
      if (error instanceof FutureSessionError) return c.json(apiError("invalid_request", error.message), 400);
      throw error;
    }
  })
  .openapi(deleteRoute, async (c) => {
    const { id, sessionId } = c.req.valid("param");
    if (!(await deletePracticeSession(c.var.user.id, id, sessionId))) return c.json(apiError("not_found", SESSION_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(pauseRoute, async (c) => {
    const userId = c.var.user.id;
    const { resumesOn } = c.req.valid("json");
    const today = todayIn(await getTimeZone(userId));
    if (resumesOn) {
      const parsed = z.iso.date().safeParse(resumesOn);
      if (!parsed.success || resumesOn <= today) return c.json(apiError("invalid_request", "Pick a day after today to pick it up again."), 400);
      if (resumesOn > addDays(today, 366)) return c.json(apiError("invalid_request", "Pause it for a year at most."), 400);
    }
    if (!(await pausePractice(userId, c.req.valid("param").id, today, resumesOn || null))) {
      return c.json(apiError("not_found", PRACTICE_GONE), 404);
    }
    return c.body(null, 204);
  })
  .openapi(resumeRoute, async (c) => {
    const userId = c.var.user.id;
    const today = todayIn(await getTimeZone(userId));
    if (!(await resumePractice(userId, c.req.valid("param").id, today))) return c.json(apiError("not_found", PRACTICE_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(missedRoute, async (c) => {
    try {
      const result = await setBlockMissed(c.var.user.id, c.req.valid("param").blockId, c.req.valid("json").missed);
      if (!result) return c.json(apiError("not_found", "That block doesn’t exist anymore."), 404);
      return c.body(null, 204);
    } catch (error) {
      if (error instanceof MissedError) return c.json(apiError("invalid_request", error.message), 400);
      throw error;
    }
  });
