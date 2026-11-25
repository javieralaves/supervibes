import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { completeSuggestion, getLatestRead, passOnSuggestion } from "@/lib/progress";
import { getGoal } from "@/lib/sources";
import { TASK_MINUTES, taskDaySchema, taskPatchSchema, taskTitleSchema } from "@/lib/task-schema";
import { PracticeError } from "@/lib/goals";
import { createTask, deleteTask, markTaskDone, PlacementError, placeTask, reorderTasks, updateTask, type TaskDTO } from "@/lib/tasks";

/*
 * A goal's tasks and the read's suggestions, for the goal page's Tasks section
 * (app/(app)/goals/[id]/tasks-section.tsx and its actions). Same rules and messages.
 */

export const TaskSchema = z
  .object({
    id: z.string(),
    title: z.string(),
    description: z.string().nullable(),
    minutes: z.int().openapi({ description: "The estimate: 15, 30, 60 or 120." }),
    doneAt: z.iso.datetime().nullable(),
    plannedFor: z.iso.date().nullable().openapi({ description: "The day they mean to do it." }),
    plannedWeek: z.iso.date().nullable().openapi({
      description:
        "The Monday of the week they mean to do it (a planned day sets its week). Null with no planned day: not planned yet, Unplanned.",
    }),
    dueOn: z.iso.date().nullable().openapi({ description: "The day it's due." }),
    scheduledAt: z.iso.datetime().nullable().openapi({ description: "When it's next on the calendar, if it is." }),
  })
  .openapi("Task");

export const SuggestionSchema = z
  .object({ title: z.string(), why: z.string(), minutes: z.int() })
  .openapi("Suggestion");

export function asTask(task: TaskDTO, scheduledAt: Date | null = null): z.infer<typeof TaskSchema> {
  return {
    id: task.id,
    title: task.title,
    description: task.description,
    minutes: task.minutes,
    doneAt: task.doneAt?.toISOString() ?? null,
    plannedFor: task.plannedFor,
    plannedWeek: task.plannedWeek,
    dueOn: task.dueOn,
    scheduledAt: scheduledAt?.toISOString() ?? null,
  };
}

const TASK_GONE = "That task doesn’t exist anymore.";
const GOAL_GONE = "That goal doesn’t exist anymore.";
const SUGGESTION_GONE = "That suggestion doesn’t exist anymore.";

const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const goalParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const taskParam = z.object({ taskId: z.uuid().openapi({ param: { name: "taskId", in: "path" } }) });
const taskResponse = { description: "OK", content: { "application/json": { schema: TaskSchema } } };

/**
 * Only what changes is sent. A JSON client can't always send an explicit null, so an empty
 * string clears `description`, `plannedFor`, `plannedWeek` or `dueOn`. A planned day and week are
 * kept in step: see src/lib/task-horizon.ts.
 */
const PLANNED_FOR = "YYYY-MM-DD; also plans it for that day's week. Empty clears the day and keeps the week.";
const PLANNED_WEEK = "Any day of this week or next (kept as its Monday); drops a planned day outside it. Empty moves it to Unplanned.";

const TaskPatchSchema = z
  .object({
    title: z.string().optional(),
    description: z.string().optional().openapi({ description: "Empty clears it." }),
    minutes: z.int().optional().openapi({ description: `One of ${TASK_MINUTES.join(", ")}.` }),
    plannedFor: z.string().optional().openapi({ description: PLANNED_FOR }),
    plannedWeek: z.string().optional().openapi({ description: PLANNED_WEEK }),
    dueOn: z.string().optional().openapi({ description: "YYYY-MM-DD; empty clears it." }),
  })
  .openapi("TaskPatch");

/** Where a task goes: an empty string clears a field. Fields left out stay as they are. */
const TaskPlacementSchema = z
  .object({
    plannedFor: z.string().optional().openapi({ description: PLANNED_FOR }),
    plannedWeek: z.string().optional().openapi({ description: PLANNED_WEEK }),
    before: z
      .string()
      .optional()
      .openapi({ description: "An open task on the same goal to put it just before; left out, it goes after all of them." }),
  })
  .openapi("TaskPlacement");

const SuggestionChoiceSchema = z.object({ title: z.string() }).openapi("SuggestionChoice");

const addRoute = createRoute({
  method: "post",
  path: "/goals/{id}/tasks",
  operationId: "addTask",
  summary: "Add a task at the end of the goal's open tasks, in Unplanned unless given a day or week",
  security: [{ bearerAuth: [] }],
  request: {
    params: goalParam,
    body: {
      required: true,
      content: {
        "application/json": {
          schema: z
            .object({
              title: z.string(),
              plannedFor: z.string().optional().openapi({ description: "YYYY-MM-DD." }),
              plannedWeek: z.string().optional().openapi({ description: "Any day of this week or next." }),
            })
            .openapi("NewTask"),
        },
      },
    },
  },
  responses: { 201: { description: "Added", content: { "application/json": { schema: TaskSchema } } }, ...errorResponses, 404: notFound },
});

const orderRoute = createRoute({
  method: "put",
  path: "/goals/{id}/tasks/order",
  operationId: "reorderTasks",
  summary: "Put the goal's open tasks in this order (all of them, exactly once)",
  security: [{ bearerAuth: [] }],
  request: {
    params: goalParam,
    body: { required: true, content: { "application/json": { schema: z.object({ ids: z.array(z.string()) }).openapi("TaskOrder") } } },
  },
  responses: { 204: { description: "Saved" }, ...errorResponses, 404: notFound },
});

const editRoute = createRoute({
  method: "patch",
  path: "/tasks/{taskId}",
  operationId: "editTask",
  summary: "Change a task's title, description, estimate, planned day or week, or due date",
  security: [{ bearerAuth: [] }],
  request: { params: taskParam, body: { required: true, content: { "application/json": { schema: TaskPatchSchema } } } },
  responses: { 200: taskResponse, ...errorResponses, 404: notFound },
});

const placeRoute = createRoute({
  method: "put",
  path: "/tasks/{taskId}/place",
  operationId: "placeTask",
  summary: "Move an open task to a day, a week or Unplanned, and to a spot among the goal's open tasks",
  security: [{ bearerAuth: [] }],
  request: { params: taskParam, body: { required: true, content: { "application/json": { schema: TaskPlacementSchema } } } },
  responses: { 200: taskResponse, ...errorResponses, 404: notFound },
});

const doneRoute = createRoute({
  method: "put",
  path: "/tasks/{taskId}/done",
  operationId: "setTaskDone",
  summary: "Check a task off (it moves to the goal's activity) or reopen it",
  security: [{ bearerAuth: [] }],
  request: {
    params: taskParam,
    body: { required: true, content: { "application/json": { schema: z.object({ done: z.boolean() }).openapi("TaskDone") } } },
  },
  responses: { 200: taskResponse, ...errorResponses, 404: notFound },
});

const deleteRoute = createRoute({
  method: "delete",
  path: "/tasks/{taskId}",
  operationId: "deleteTask",
  summary: "Delete a task",
  security: [{ bearerAuth: [] }],
  request: { params: taskParam },
  responses: { 204: { description: "Deleted" }, 401: errorResponses[401], 404: notFound },
});

const acceptRoute = createRoute({
  method: "post",
  path: "/goals/{id}/suggestions/accept",
  operationId: "acceptSuggestion",
  summary: "Add a suggestion as a task, keeping its estimate and reason",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: SuggestionChoiceSchema } } } },
  responses: { 201: { description: "Added", content: { "application/json": { schema: TaskSchema } } }, ...errorResponses, 404: notFound },
});

const passRoute = createRoute({
  method: "post",
  path: "/goals/{id}/suggestions/pass",
  operationId: "passOnSuggestion",
  summary: "Not now: hide a suggestion and keep later reads from suggesting it again",
  security: [{ bearerAuth: [] }],
  request: { params: goalParam, body: { required: true, content: { "application/json": { schema: SuggestionChoiceSchema } } } },
  responses: { 204: { description: "Passed on" }, ...errorResponses, 404: notFound },
});

const clearable = (value: string | undefined) => (value === undefined ? undefined : value === "" ? null : value);
const placementSchema = z.object({ plannedFor: taskDaySchema.optional(), plannedWeek: taskDaySchema.optional() });
const STALE = "Your tasks changed since this page loaded. Try again.";

/** A PlacementError as a 400; anything else is rethrown. */
function placementProblem(error: unknown) {
  if (error instanceof PlacementError) return apiError("invalid_request", error.message);
  throw error;
}
const suggestionTitle = z.string().trim().min(1).max(140);

export const tasks = new OpenAPIHono<ApiEnv>()
  .openapi(addRoute, async (c) => {
    const body = c.req.valid("json");
    const title = taskTitleSchema.safeParse(body.title);
    if (!title.success) return c.json(apiError("invalid_request", title.error.issues[0]?.message ?? "Check the task."), 400);
    const placement = placementSchema.safeParse({ plannedFor: body.plannedFor || undefined, plannedWeek: body.plannedWeek || undefined });
    if (!placement.success) return c.json(apiError("invalid_request", placement.error.issues[0]?.message ?? "Check the task."), 400);
    try {
      const task = await createTask(c.var.user.id, c.req.valid("param").id, title.data, placement.data);
      if (!task) return c.json(apiError("not_found", GOAL_GONE), 404);
      return c.json(asTask(task), 201);
    } catch (error) {
      if (error instanceof PracticeError) return c.json(apiError("practice", error.message), 400);
      return c.json(placementProblem(error), 400);
    }
  })
  .openapi(orderRoute, async (c) => {
    const ids = z.array(z.uuid()).max(500).safeParse(c.req.valid("json").ids);
    if (!ids.success) return c.json(apiError("invalid_request", "Couldn’t reorder these tasks."), 400);
    const { id } = c.req.valid("param");
    if (!(await getGoal(c.var.user.id, id))) return c.json(apiError("not_found", GOAL_GONE), 404);
    if (!(await reorderTasks(c.var.user.id, id, ids.data))) return c.json(apiError("stale", STALE), 400);
    return c.body(null, 204);
  })
  .openapi(editRoute, async (c) => {
    const body = c.req.valid("json");
    const parsed = taskPatchSchema.safeParse({
      title: body.title,
      description: clearable(body.description),
      minutes: body.minutes,
      plannedFor: clearable(body.plannedFor),
      plannedWeek: clearable(body.plannedWeek),
      dueOn: clearable(body.dueOn),
    });
    if (!parsed.success) return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the task."), 400);
    try {
      const task = await updateTask(c.var.user.id, c.req.valid("param").taskId, parsed.data);
      if (!task) return c.json(apiError("not_found", TASK_GONE), 404);
      return c.json(asTask(task), 200);
    } catch (error) {
      return c.json(placementProblem(error), 400);
    }
  })
  .openapi(placeRoute, async (c) => {
    const body = c.req.valid("json");
    const placement = placementSchema.safeParse({ plannedFor: clearable(body.plannedFor), plannedWeek: clearable(body.plannedWeek) });
    const before = z.uuid().optional().safeParse(body.before || undefined);
    if (!placement.success) return c.json(apiError("invalid_request", placement.error.issues[0]?.message ?? "Check the task."), 400);
    if (!before.success) return c.json(apiError("stale", STALE), 400);
    try {
      const task = await placeTask(c.var.user.id, c.req.valid("param").taskId, placement.data, before.data);
      if (task === "not_found") return c.json(apiError("not_found", TASK_GONE), 404);
      if (task === "stale") return c.json(apiError("stale", STALE), 400);
      return c.json(asTask(task), 200);
    } catch (error) {
      return c.json(placementProblem(error), 400);
    }
  })
  .openapi(doneRoute, async (c) => {
    // Checking a task off shows up in the goal's activity; reopening it takes that back.
    const task = await markTaskDone(c.var.user.id, c.req.valid("param").taskId, c.req.valid("json").done);
    if (!task) return c.json(apiError("not_found", TASK_GONE), 404);
    return c.json(asTask(task), 200);
  })
  .openapi(deleteRoute, async (c) => {
    if (!(await deleteTask(c.var.user.id, c.req.valid("param").taskId))) return c.json(apiError("not_found", TASK_GONE), 404);
    return c.body(null, 204);
  })
  .openapi(acceptRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const title = suggestionTitle.safeParse(c.req.valid("json").title);
    if (!title.success) return c.json(apiError("not_found", SUGGESTION_GONE), 404);
    const read = await getLatestRead(userId, id);
    const suggestion = read?.suggestions.find((s) => s.title === title.data);
    if (!suggestion) return c.json(apiError("not_found", SUGGESTION_GONE), 404);
    // A practice has no reads, so no suggestions: this is a project's.
    const task = await createTask(userId, id, suggestion.title, {
      minutes: suggestion.minutes,
      description: suggestion.why || null,
    });
    if (!task) return c.json(apiError("not_found", GOAL_GONE), 404);
    await completeSuggestion(userId, id, suggestion.title);
    return c.json(asTask(task), 201);
  })
  .openapi(passRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const title = suggestionTitle.safeParse(c.req.valid("json").title);
    if (!title.success) return c.json(apiError("not_found", SUGGESTION_GONE), 404);
    // Only a suggestion that's actually there: passing on remembers the title for later reads,
    // so an unknown one would be remembered too.
    const read = await getLatestRead(userId, id);
    if (!read?.suggestions.some((s) => s.title === title.data)) return c.json(apiError("not_found", SUGGESTION_GONE), 404);
    await passOnSuggestion(userId, id, title.data);
    return c.body(null, 204);
  });
