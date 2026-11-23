import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { AgendaError, prepareAgenda, suggestFocus } from "@/lib/agenda";
import { asAgenda, asCalendarBlock, asRecap, BlockAgendaSchema, BlockRecapSchema, CalendarBlockSchema } from "@/lib/api/routes/calendar";
import { requestRead } from "@/lib/background-read";
import { BLOCK_KINDS, blockDescriptionSchema, blockDetailsSchema, blockTimesSchema, newBlockSchema } from "@/lib/block-schema";
import { createBlock, deleteBlock, getBlock, updateBlock } from "@/lib/blocks";
import { postBodySchema } from "@/lib/post-schema";
import { createRecapPost } from "@/lib/posts";
import { discardRecap, prepareRecap, RecapError } from "@/lib/recap";
import { postRecapSchema } from "@/lib/recap-schema";
import { taskDaySchema, taskDescriptionSchema, taskMinutesSchema, taskTitleSchema } from "@/lib/task-schema";
import { createTask, getTask, markTaskDone, planTaskForBlock, updateTask } from "@/lib/tasks";

/*
 * Changing the calendar, as app/(app)/calendar/actions.ts does: protected time drawn on a day,
 * blocks moved, resized, renamed or removed, intentions marked done, and tasks given a time or a
 * day; and the block panel's: whether protected time is a session or reserved, a session's aim,
 * its agenda, and its recap. Same rules and messages.
 */

const GONE = "That block doesn’t exist anymore.";
/** Reserved time is kept for its own sake: it has no aim, agenda or recap. */
const RESERVED = "This time is reserved, not a session. Make it a session first.";
const TASK_GONE = "That task doesn’t exist anymore.";
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const blockParam = z.object({ blockId: z.uuid().openapi({ param: { name: "blockId", in: "path" } }) });
const taskParam = z.object({ taskId: z.uuid().openapi({ param: { name: "taskId", in: "path" } }) });
const blockResponse = { description: "OK", content: { "application/json": { schema: CalendarBlockSchema } } };

const TimesSchema = z.object({ startsAt: z.iso.datetime({ offset: true }), endsAt: z.iso.datetime({ offset: true }) }).openapi("BlockTimes");
/** A title left out means none, like null: the Mac app's client leaves out a nil one. */
const blockTitle = z.string().nullable().optional().openapi({ description: "Left out or null: no title." });
const DetailsSchema = z.object({ goalId: z.string(), title: blockTitle }).openapi("BlockDetails");
const NewBlockSchema = z
  .object({
    goalId: z.string(),
    title: blockTitle,
    startsAt: z.string(),
    endsAt: z.string(),
    kind: z.enum(BLOCK_KINDS).optional().openapi({
      description:
        "Left out: a session. `reserved`: time kept for its own sake. `task`: time for the task `taskId` names (its goal and title win), or, without one, a new task in the goal titled with `title`.",
    }),
    taskId: z.string().optional().openapi({ description: "With `kind: task`, the open task to give this time." }),
  })
  .openapi("NewBlock");

const firstIssue = (error: z.ZodError) => error.issues[0]?.message ?? "Check the details.";

const createRoute_ = createRoute({
  method: "post",
  path: "/blocks",
  operationId: "createBlock",
  summary: "Protect time for a goal, drawn on the calendar: a session, reserved time, or time for a task",
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

const reservedRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/reserved",
  operationId: "setBlockReserved",
  summary: "Make protected time reserved (kept for its own sake, no room for tasks) or a session again",
  description: "Reserving it clears a session's agenda and draft recap. An intention can't be reserved.",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: { "application/json": { schema: z.object({ reserved: z.boolean() }).openapi("BlockReserved") } },
    },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const kindRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/kind",
  operationId: "setBlockKind",
  summary: "Make a block a session, reserved time or a task's time",
  description:
    "A session or reserved time becomes a task's time by making a new task in its goal from its title and description. A task's time becomes protected time by letting go of the task, which stays open; the block keeps its title. Reserving clears a session's agenda and draft recap.",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: { "application/json": { schema: z.object({ kind: z.enum(BLOCK_KINDS) }).openapi("BlockKind") } },
    },
  },
  responses: { 200: blockResponse, ...errorResponses, 404: notFound },
});

const descriptionRoute = createRoute({
  method: "put",
  path: "/blocks/{blockId}/description",
  operationId: "setBlockDescription",
  summary: "Describe a block; empty clears it",
  description: "A block that schedules a task is described by its task: this sets the task's description.",
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
  summary: "Prepare an agenda for a session (protected time or a task's), from the goal's tasks, notes and latest read",
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

const focusRoute = createRoute({
  method: "post",
  path: "/blocks/{blockId}/focus",
  operationId: "suggestFocus",
  summary: "Suggest an aim for a session that doesn't say what it's for yet; nothing is saved",
  security: [{ bearerAuth: [] }],
  request: {
    params: blockParam,
    body: {
      required: true,
      content: {
        "application/json": {
          schema: z
            .object({
              when: z.string().openapi({ description: "How the block reads in the viewer's time zone." }),
              instead: z
                .array(z.string())
                .optional()
                .openapi({ description: "Aims already suggested for this block and passed over, so the next one differs." }),
            })
            .openapi("SuggestFocus"),
        },
      },
    },
  },
  responses: {
    200: {
      description: "Suggested",
      content: {
        "application/json": {
          schema: z
            .object({
              aim: z.string().openapi({ description: "In the person's own voice, ready to be the session's aim." }),
              why: z.string(),
            })
            .openapi("FocusSuggestion"),
        },
      },
    },
    ...errorResponses,
    404: notFound,
    502: { description: "Couldn't suggest one.", content: { "application/json": { schema: ErrorSchema } } },
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
    const userId = c.var.user.id;
    const { startsAt, endsAt, kind, taskId, ...details } = parsed.data;
    const times = { startsAt: new Date(startsAt), endsAt: new Date(endsAt) };
    if (kind !== "task") {
      const block = await createBlock(userId, { ...details, ...times, reserved: kind === "reserved" });
      if (!block) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
      return c.json(asCalendarBlock(block, new Set()), 201);
    }
    // Time for a task: the one named, or a new one in the goal, sized to the block when it can be.
    let task = taskId ? await getTask(userId, taskId) : null;
    if (taskId && (!task || task.doneAt)) return c.json(apiError("not_found", TASK_GONE), 404);
    if (!task) {
      const title = taskTitleSchema.safeParse(details.title ?? "");
      if (!title.success) return c.json(apiError("invalid_request", firstIssue(title.error)), 400);
      const minutes = taskMinutesSchema.safeParse(Math.round((times.endsAt.getTime() - times.startsAt.getTime()) / 60_000));
      task = await createTask(userId, details.goalId, title.data, minutes.success ? { minutes: minutes.data } : {});
      if (!task) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    }
    const block = await createBlock(userId, { goalId: task.goalId, title: task.title, taskId: task.id, ...times });
    if (!block) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
    await planTaskForBlock(userId, block);
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
  .openapi(reservedRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    const { reserved } = c.req.valid("json");
    const before = await getBlock(userId, blockId);
    if (!before) return c.json(apiError("not_found", GONE), 404);
    if (before.fromSuggestion || before.taskId) return c.json(apiError("invalid_request", "This block schedules a task, so it’s a session."), 400);
    if (before.reserved === reserved) return c.body(null, 204);
    // A session's plan and draft recap don't belong to time kept for its own sake.
    const block = await updateBlock(userId, blockId, reserved ? { reserved, agenda: null, recap: null } : { reserved });
    if (!block) return c.json(apiError("not_found", GONE), 404);
    return c.body(null, 204);
  })
  .openapi(kindRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    const { kind } = c.req.valid("json");
    const before = await getBlock(userId, blockId);
    if (!before) return c.json(apiError("not_found", GONE), 404);
    const intention = Boolean(before.fromSuggestion || before.taskId);
    let block: typeof before | null = before;
    if (kind === "task") {
      if (intention) return c.json(asCalendarBlock(before, new Set()), 200);
      const title = taskTitleSchema.safeParse(before.title ?? "");
      if (!title.success) return c.json(apiError("invalid_request", "Give this block a title first: it becomes the task."), 400);
      const minutes = taskMinutesSchema.safeParse(Math.round((before.endsAt.getTime() - before.startsAt.getTime()) / 60_000));
      const task = await createTask(userId, before.goalId, title.data, {
        description: before.description,
        ...(minutes.success ? { minutes: minutes.data } : {}),
      });
      if (!task) return c.json(apiError("not_found", "That goal doesn’t exist anymore."), 404);
      // The description moves to the task, which describes its time from now on.
      block = await updateBlock(userId, blockId, { taskId: task.id, reserved: false, description: null });
      if (block) await planTaskForBlock(userId, block);
    } else {
      const reserved = kind === "reserved";
      if (!intention && before.reserved === reserved) return c.json(asCalendarBlock(before, new Set()), 200);
      // A session's plan and draft recap don't belong to time kept for its own sake.
      block = await updateBlock(userId, blockId, {
        taskId: null,
        fromSuggestion: null,
        reserved,
        ...(reserved ? { agenda: null, recap: null } : {}),
      });
    }
    if (!block) return c.json(apiError("not_found", GONE), 404);
    return c.json(asCalendarBlock(block, new Set()), 200);
  })
  .openapi(descriptionRoute, async (c) => {
    const userId = c.var.user.id;
    const { blockId } = c.req.valid("param");
    const parsed = blockDescriptionSchema.safeParse(c.req.valid("json").description);
    if (!parsed.success) return c.json(apiError("invalid_request", firstIssue(parsed.error)), 400);
    const before = await getBlock(userId, blockId);
    if (!before) return c.json(apiError("not_found", GONE), 404);
    // A task's time is described by the task itself, so the description reads the same everywhere.
    if (before.taskId) {
      const description = taskDescriptionSchema.safeParse(parsed.data);
      if (!description.success) return c.json(apiError("invalid_request", firstIssue(description.error)), 400);
      if (!(await updateTask(userId, before.taskId, { description: description.data }))) return c.json(apiError("not_found", TASK_GONE), 404);
      return c.body(null, 204);
    }
    if (before.description !== parsed.data && !(await updateBlock(userId, blockId, { description: parsed.data }))) {
      return c.json(apiError("not_found", GONE), 404);
    }
    return c.body(null, 204);
  })
  .openapi(agendaRoute, async (c) => {
    const label = z.string().trim().min(1).max(120).safeParse(c.req.valid("json").when);
    if (!label.success) return c.json(apiError("invalid_request", "Couldn't tell when this block is."), 400);
    const block = await getBlock(c.var.user.id, c.req.valid("param").blockId);
    if (!block) return c.json(apiError("not_found", GONE), 404);
    if (block.reserved) return c.json(apiError("invalid_request", RESERVED), 400);
    try {
      const agenda = await prepareAgenda(c.var.user.id, c.req.valid("param").blockId, label.data);
      return c.json(asAgenda(agenda), 200);
    } catch (error) {
      if (error instanceof AgendaError) return c.json(apiError("unavailable", error.message), 502);
      console.error("[agenda] failed", error);
      return c.json(apiError("unavailable", "Couldn't prepare an agenda right now. Try again."), 502);
    }
  })
  .openapi(focusRoute, async (c) => {
    const { when, instead } = c.req.valid("json");
    const label = z.string().trim().min(1).max(120).safeParse(when);
    if (!label.success) return c.json(apiError("invalid_request", "Couldn't tell when this block is."), 400);
    const block = await getBlock(c.var.user.id, c.req.valid("param").blockId);
    if (!block) return c.json(apiError("not_found", GONE), 404);
    if (block.reserved) return c.json(apiError("invalid_request", RESERVED), 400);
    try {
      const focus = await suggestFocus(c.var.user.id, c.req.valid("param").blockId, label.data, instead ?? []);
      return c.json(focus, 200);
    } catch (error) {
      if (error instanceof AgendaError) return c.json(apiError("unavailable", error.message), 502);
      console.error("[focus] failed", error);
      return c.json(apiError("unavailable", "Couldn't suggest a focus right now. Try again."), 502);
    }
  })
  .openapi(recapRoute, async (c) => {
    const block = await getBlock(c.var.user.id, c.req.valid("param").blockId);
    if (!block) return c.json(apiError("not_found", GONE), 404);
    if (block.reserved) return c.json(apiError("invalid_request", RESERVED), 400);
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
