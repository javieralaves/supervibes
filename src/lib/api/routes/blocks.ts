import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { AgendaError, prepareAgenda } from "@/lib/agenda";
import { asAgenda, asCalendarBlock, asRecap, BlockAgendaSchema, BlockRecapSchema, CalendarBlockSchema } from "@/lib/api/routes/calendar";
import { requestRead } from "@/lib/background-read";
import { blockDescriptionSchema, blockDetailsSchema, blockTimesSchema, newBlockSchema } from "@/lib/block-schema";
import { createBlock, deleteBlock, getBlock, updateBlock } from "@/lib/blocks";
import { postBodySchema } from "@/lib/post-schema";
import { createRecapPost } from "@/lib/posts";
import { discardRecap, prepareRecap, RecapError } from "@/lib/recap";
import { postRecapSchema } from "@/lib/recap-schema";
import { taskDaySchema } from "@/lib/task-schema";
import { getTask, markTaskDone, planTaskForBlock, updateTask } from "@/lib/tasks";

/*
 * Changing the calendar, as app/(app)/calendar/actions.ts does: protected time drawn on a day,
 * blocks moved, resized, renamed or removed, intentions marked done, and tasks given a time or a
 * day; and the block panel's: a session's aim, its agenda, and its recap. Same rules and messages.
 */

const GONE = "That block doesn’t exist anymore.";
const TASK_GONE = "That task doesn’t exist anymore.";
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const blockParam = z.object({ blockId: z.uuid().openapi({ param: { name: "blockId", in: "path" } }) });
const taskParam = z.object({ taskId: z.uuid().openapi({ param: { name: "taskId", in: "path" } }) });
const blockResponse = { description: "OK", content: { "application/json": { schema: CalendarBlockSchema } } };

const TimesSchema = z.object({ startsAt: z.iso.datetime({ offset: true }), endsAt: z.iso.datetime({ offset: true }) }).openapi("BlockTimes");
const DetailsSchema = z.object({ goalId: z.string(), title: z.string().nullable() }).openapi("BlockDetails");
const NewBlockSchema = z
  .object({ goalId: z.string(), title: z.string().nullable(), startsAt: z.string(), endsAt: z.string() })
  .openapi("NewBlock");

const firstIssue = (error: z.ZodError) => error.issues[0]?.message ?? "Check the details.";

const createRoute_ = createRoute({
  method: "post",
  path: "/blocks",
  operationId: "createBlock",
  summary: "Protect time for a goal, drawn on the calendar",
  security: [{ bearerAuth: [] }],
  request: { body: { required: true, content: { "application/json": { schema: NewBlockSchema } } } },
  responses: { 201: { ...blockResponse, description: "Created" }, ...errorResponses, 404: notFound },
});

const detailsRoute = createRoute({
  method: "patch",
  path: "/blocks/{blockId}",
  operationId: "updateBlock",
  summary: "Rename a block or move it to another goal",
  security: [{ bearerAuth: [] }],
  request: { params: blockParam, body: { required: true, content: { "application/json": { schema: DetailsSchema } } } },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const timesRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/times",
  operationId: "moveBlock",
  summary: "Move or resize a block; an intention's task is planned for its new day",
  security: [{ bearerAuth: [] }],
  request: { params: blockParam, body: { required: true, content: { "application/json": { schema: TimesSchema } } } },
  responses: { 204: { description: "Moved" }, ...errorResponses, 404: notFound },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/blocks/{blockId}",
  operationId: "deleteBlock",
  summary: "Remove a block",
  security: [{ bearerAuth: [] }],
  request: { params: blockParam },
  responses: { 204: { description: "Removed" }, 401: errorResponses[401], 404: notFound },
});

const doneRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/task-done",
  operationId: "setBlockTaskDone",
  summary: "Mark an intention's task done (it posts to the goal's activity) or reopen it",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: { required: true, content: { "application/json": { schema: z.object({ done: z.boolean() }).openapi("BlockTaskDone") } } },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const scheduleRoute = createRoute({
  method: "post",
  path: "/tasks/{taskId}/schedule",
  operationId: "scheduleTask",
  summary: "Give a task a time on the calendar: a new intention",
  security: [{ bearerAuth: [] }],
  request: { params: taskParam, body: { required: true, content: { "application/json": { schema: TimesSchema } } } },
  responses: { 201: { ...blockResponse, description: "Scheduled" }, ...errorResponses, 404: notFound },
});

const planRoute = createRoute({
  method: "put",
  path: "/tasks/{taskId}/plan",
  operationId: "planTask",
  summary: "Plan a task for a day without a time, or take it off its day",
  description:
    "An empty `day` takes it off. With `unscheduleBlockId`, that block goes too, if it's the task's own and hasn't started.",
  security: [{ bearerAuth: [] }],
  request: {
    params: taskParam,
    body: {
      required: true,
      content: {
        "application/json": {
          schema: z.object({ day: z.string(), unscheduleBlockId: z.string().optional() }).openapi("PlanTask"),
        },
      },
    },
  },
  responses: { 204: { description: "Planned" }, ...errorResponses, 404: notFound },
});

const descriptionRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/description",
  operationId: "setBlockDescription",
  summary: "Say what you want out of a session of protected time; empty clears it",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: { "application/json": { schema: z.object({ description: z.string() }).openapi("BlockDescription") } },
    },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const agendaRoute = createRoute({
  method: "post",
  path: "/blocks/{blockId}/agenda",
  operationId: "prepareAgenda",
  summary: "Prepare an agenda for a session, from the goal's tasks, notes and latest read",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: {
        "application/json": {
          schema: z
            .object({ when: z.string().openapi({ description: "How the block reads in the viewer's time zone." }) })
            .openapi("PrepareAgenda"),
        },
      },
    },
  },
  responses: {
    200: { description: "Prepared", content: { "application/json": { schema: BlockAgendaSchema } } },
    ...errorResponses,
    404: notFound,
    502: { description: "Couldn't prepare it.", content: { "application/json": { schema: ErrorSchema } } },
  },
});

const recapRoute = createRoute({
  method: "post",
  path: "/blocks/{blockId}/recap",
  operationId: "prepareRecap",
  summary: "Draft a recap of a session that's ended, from the goal's connected apps",
  security: [{ bearerAuth: [] }],
  request: { params: blockParam },
  responses: {
    200: { description: "Drafted", content: { "application/json": { schema: BlockRecapSchema } } },
    ...errorResponses,
    404: notFound,
    502: { description: "Couldn't draft it.", content: { "application/json": { schema: ErrorSchema } } },
  },
});

const postRecapRoute = createRoute({
  method: "post",
  path: "/blocks/{blockId}/recap/post",
  operationId: "postRecap",
  summary: "Post a recap to the goal's activity, keeping the draft's links named in `keep`",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: {
        "application/json": {
          schema: z.object({ body: z.string(), keep: z.array(z.string()), markTaskDone: z.boolean() }).openapi("PostRecap"),
        },
      },
    },
  },
  responses: { 204: { description: "Posted" }, ...errorResponses, 404: notFound },
});

const discardRecapRoute = createRoute({
  method: "delete",
  path: "/blocks/{blockId}/recap",
  operationId: "discardRecap",
  summary: "Discard a draft recap",
  security: [{ bearerAuth: [] }],
  request: { params: blockParam },
  responses: { 204: { description: "Discarded" }, 401: errorResponses[401], 404: notFound },
});

export const blocks = new OpenAPIHono<ApiEnv>()
  .openapi(createRoute_, async (c) => {
    const parsed = newBlockSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) return c.json(apiError("invalid_request", firstIssue(parsed.error)), 400);
    const { startsAt, endsAt, ...details } = parsed.data;
    const block = await createBlock(c.var.user.id, { ...details, startsAt: new Date(startsAt), endsAt: new Date(endsAt) });
    if (!block) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    return c.json(asCalendarBlock(block, new Set()), 201);
  })
  .openapi(detailsRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    const parsed = blockDetailsSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) return c.json(apiError("invalid_request", firstIssue(parsed.error)), 400);
    const before = await getBlock(userId, blockId);
    if (!before) return c.json(apiError("not_found", GONE), 404);
    // An intention keeps its task; only its goal and title can change.
    const intention = Boolean(before.fromSuggestion || before.taskId);
    const block = await updateBlock(userId, blockId, {
      ...parsed.data,
      title: intention ? (parsed.data.title ?? before.title) : parsed.data.title,
      // An agenda or draft recap is about one goal; moving the block to another goal clears them.
      ...(parsed.data.goalId !== before.goalId ? { agenda: null, recap: null } : {}),
    });
    if (!block) return c.json(apiError("not_found", GONE), 404);
    return c.body(null, 204);
  })
  .openapi(timesRoute, async (c) => {
    const userId = c.var.user.id;
    const when = blockTimesSchema.safeParse(c.req.valid("json"));
    if (!when.success) return c.json(apiError("invalid_request", firstIssue(when.error)), 400);
    const block = await updateBlock(userId, c.req.valid("param").blockId, {
      startsAt: new Date(when.data.startsAt),
      endsAt: new Date(when.data.endsAt),
    });
    if (!block) return c.json(apiError("not_found", GONE), 404);
    await planTaskForBlock(userId, block);
    return c.body(null, 204);
  })
  .openapi(deleteRoute, async (c) => {
    if (!(await deleteBlock(c.var.user.id, c.req.valid("param").blockId))) return c.json(apiError("not_found", GONE), 404);
    return c.body(null, 204);
  })
  .openapi(doneRoute, async (c) => {
    const userId = c.var.user.id;
    const block = await getBlock(userId, c.req.valid("param").blockId);
    if (!block?.taskId) return c.json(apiError("not_found", TASK_GONE), 404);
    if (!(await markTaskDone(userId, block.taskId, c.req.valid("json").done))) return c.json(apiError("not_found", TASK_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(scheduleRoute, async (c) => {
    const userId = c.var.user.id;
    const when = blockTimesSchema.safeParse(c.req.valid("json"));
    if (!when.success) return c.json(apiError("invalid_request", firstIssue(when.error)), 400);
    const task = await getTask(userId, c.req.valid("param").taskId);
    if (!task) return c.json(apiError("not_found", TASK_GONE), 404);
    const block = await createBlock(userId, {
      goalId: task.goalId,
      title: task.title,
      taskId: task.id,
      startsAt: new Date(when.data.startsAt),
      endsAt: new Date(when.data.endsAt),
    });
    if (!block) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    await planTaskForBlock(userId, block);
    return c.json(asCalendarBlock(block, new Set()), 201);
  })
  .openapi(planRoute, async (c) => {
    const userId = c.var.user.id;
    const { taskId } = c.req.valid("param");
    const body = c.req.valid("json");
    const plannedFor = taskDaySchema.safeParse(body.day === "" ? null : body.day);
    if (!plannedFor.success) return c.json(apiError("invalid_request", firstIssue(plannedFor.error)), 400);
    if (body.unscheduleBlockId) {
      const blockId = z.uuid().safeParse(body.unscheduleBlockId);
      const block = blockId.success ? await getBlock(userId, blockId.data) : null;
      // Only its own block, and only one that hasn't started: a past session is a record.
      if (block && block.taskId === taskId && block.startsAt.getTime() > Date.now()) await deleteBlock(userId, block.id);
    }
    if (!(await updateTask(userId, taskId, { plannedFor: plannedFor.data }))) return c.json(apiError("not_found", TASK_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(descriptionRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    const parsed = blockDescriptionSchema.safeParse(c.req.valid("json").description);
    if (!parsed.success) return c.json(apiError("invalid_request", firstIssue(parsed.error)), 400);
    const before = await getBlock(userId, blockId);
    if (!before) return c.json(apiError("not_found", GONE), 404);
    // An intention's task already says what it's for.
    if (before.fromSuggestion || before.taskId) return c.json(apiError("invalid_request", "This block already schedules a task."), 400);
    if (before.description !== parsed.data && !(await updateBlock(userId, blockId, { description: parsed.data }))) {
      return c.json(apiError("not_found", GONE), 404);
    }
    return c.body(null, 204);
  })
  .openapi(agendaRoute, async (c) => {
    const label = z.string().trim().min(1).max(120).safeParse(c.req.valid("json").when);
    if (!label.success) return c.json(apiError("invalid_request", "Couldn't tell when this block is."), 400);
    try {
      const agenda = await prepareAgenda(c.var.user.id, c.req.valid("param").blockId, label.data);
      return c.json(asAgenda(agenda), 200);
    } catch (error) {
      if (error instanceof AgendaError) return c.json(apiError("unavailable", error.message), 502);
      console.error("[agenda] failed", error);
      return c.json(apiError("unavailable", "Couldn't prepare an agenda right now. Try again."), 502);
    }
  })
  .openapi(recapRoute, async (c) => {
    try {
      const recap = await prepareRecap(c.var.user.id, c.req.valid("param").blockId);
      return c.json(asRecap(recap), 200);
    } catch (error) {
      if (error instanceof RecapError) return c.json(apiError("unavailable", error.message), 502);
      console.error("[recap] failed", error);
      return c.json(apiError("unavailable", "Couldn't recap this session right now. Try again."), 502);
    }
  })
  .openapi(postRecapRoute, async (c) => {
    const userId = c.var.user.id;
    const parsed = postRecapSchema.safeParse(c.req.valid("json"));
    if (!parsed.success) return c.json(apiError("invalid_request", firstIssue(parsed.error)), 400);
    const body = postBodySchema.safeParse(parsed.data.body);
    if (!body.success) return c.json(apiError("invalid_request", firstIssue(body.error)), 400);
    const block = await getBlock(userId, c.req.valid("param").blockId);
    if (!block) return c.json(apiError("not_found", GONE), 404);
    if (block.endsAt.getTime() > Date.now()) return c.json(apiError("invalid_request", "This session hasn’t ended yet."), 400);

    const keep = new Set(parsed.data.keep);
    const post = await createRecapPost(userId, {
      goalId: block.goalId,
      blockId: block.id,
      body: body.data,
      session: {
        title: block.title ?? block.fromSuggestion ?? "Protected time",
        startsAt: block.startsAt.toISOString(),
        endsAt: block.endsAt.toISOString(),
        aim: block.description,
      },
      breadcrumbs: (block.recap?.breadcrumbs ?? []).filter((b) => keep.has(b.url)),
    });
    if (!post) return c.json(apiError("invalid_request", "This session already has a recap."), 400);

    if (parsed.data.markTaskDone && block.taskId) await markTaskDone(userId, block.taskId, true);
    await discardRecap(userId, block.id);
    // The recap should change the goal's read; it runs after this returns.
    await requestRead(userId, block.goalId, { trigger: "recap" });
    return c.body(null, 204);
  })
  .openapi(discardRecapRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    if (!(await getBlock(userId, blockId))) return c.json(apiError("not_found", GONE), 404);
    await discardRecap(userId, blockId);
    return c.body(null, 204);
  });
