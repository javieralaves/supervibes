import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, errorResponses } from "@/lib/api/errors";
import { AreaLimitError } from "@/lib/areas";
import {
  clarifyPlate,
  FirstRunError,
  MAX_PLATE_TEXT,
  plateQuestionSchema,
  savePlate,
  sortedAreaSchema,
  sortedItemSchema,
  sortPlate,
  startFirstSeason,
  type SortedPlate,
} from "@/lib/first-run";
import { GoalLimitError } from "@/lib/goals";
import { MAX_QUESTS, questWordsSchema } from "@/lib/season-schema";
import { SeasonError } from "@/lib/seasons";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { todayIn } from "@/lib/target-date";

/*
 * First run's shared start (src/lib/first-run.ts): ask about what's fuzzy in what someone typed, sort it into areas,
 * projects and practices with their answers, then, once they've fixed what's off, make it.
 */

// Each nullable field may also be left out: the Mac app's generated client leaves out what's nil rather than sending
// null, so saving a plate sends no perWeek for a project. Left out reads as null (see asSortedPlate).
const SortedItemSchema = sortedItemSchema
  .extend({
    detail: z.string().nullish().openapi({ description: "A few words they said that help place it: a deadline, who it's with." }),
    perWeek: z.int().nullish().openapi({ description: "For a practice, times a week; null when they didn't say (ask before saving)." }),
    targetDate: z.iso.date().nullish().openapi({ description: "For a project, the day they want it done by, if they said." }),
    tasks: z.array(z.string()).openapi({ description: "One-off things to do on a project, saved to Later." }),
    bucket: z.boolean().nullish().openapi({ description: "The area's bucket for one-offs that belong to nothing bigger; false when left out." }),
  })
  .openapi("SortedItem");

const SortedAreaSchema = sortedAreaSchema.extend({ items: z.array(SortedItemSchema) }).openapi("SortedArea");
const SortedPlateSchema = z.object({ areas: z.array(SortedAreaSchema) }).openapi("SortedPlate");

const PlateAnswerSchema = z
  .object({
    quote: z.string().max(200),
    question: z.string().max(200),
    answer: z.string().max(200).nullish().openapi({ description: "The option picked: its title and line. Left out when skipped." }),
    more: z.string().max(1000).nullish().openapi({ description: "What they added in their own words." }),
  })
  .openapi("PlateAnswer");

const PlateTextSchema = z
  .object({
    text: z.string().trim().min(1, "Write a few things down first.").max(MAX_PLATE_TEXT, "That’s a lot at once. Try a shorter list."),
    timeZone: timeZoneSchema.optional().openapi({ description: "The device's time zone, for working out dates; defaults to the stored one." }),
    answers: z.array(PlateAnswerSchema).max(8).optional().openapi({ description: "Answers to the questions asked before sorting." }),
  })
  .openapi("PlateText");

const PlateQuestionsSchema = z
  .object({
    questions: z.array(
      plateQuestionSchema
        .extend({
          options: z.array(
            z
              .object({ title: z.string(), line: z.string(), kind: z.enum(["project", "practice", "task"]) })
              .openapi("PlateQuestionOption"),
          ),
        })
        .openapi("PlateQuestion"),
    ),
  })
  .openapi("PlateQuestions", { description: "What's worth asking before sorting; none when the plate is clear." });

const SavedPlateSchema = z
  .object({
    areas: z.int(),
    projects: z.int(),
    practices: z.int(),
    tasks: z.int(),
    goalIds: z.array(z.string()).openapi({ description: "The projects and practices made, to send back as `replacing` on a later save." }),
    areaIds: z.array(z.string()).openapi({ description: "The areas made, likewise." }),
  })
  .openapi("SavedPlate", { description: "How much was made: new areas, projects, practices and tasks, and their ids." });

// Spelled out rather than extended from SortedPlate: an extended schema becomes an allOf, which the Mac app's
// generated client turns into a wrapper instead of a plain struct.
const PlateToSaveSchema = z.object({
  areas: z.array(SortedAreaSchema),
  replacing: z
    .object({ goalIds: z.array(z.uuid()), areaIds: z.array(z.uuid()) })
    .optional()
    .openapi({ description: "What an earlier save of this plate made, taken out first so saving again replaces it." }),
}).openapi("PlateToSave");

const json = <T extends z.ZodType>(schema: T, description = "OK") => ({ description, content: { "application/json": { schema } } });
const secured = [{ bearerAuth: [] }];

const clarifyRoute = createRoute({
  method: "post",
  path: "/first-run/clarify",
  operationId: "clarifyPlate",
  summary: "The few questions worth asking about what someone typed before sorting it; often none; takes a few seconds",
  security: secured,
  request: { body: { content: { "application/json": { schema: PlateTextSchema } } } },
  responses: { 200: json(PlateQuestionsSchema), ...errorResponses },
});

const sortRoute = createRoute({
  method: "post",
  path: "/first-run/sort",
  operationId: "sortPlate",
  summary: "Sort what someone typed into areas, projects and practices; nothing is saved; takes a few seconds",
  security: secured,
  request: { body: { content: { "application/json": { schema: PlateTextSchema } } } },
  responses: { 200: json(SortedPlateSchema), ...errorResponses },
});

const saveRoute = createRoute({
  method: "post",
  path: "/first-run/save",
  operationId: "savePlate",
  summary: "Make a sorted plate: the areas not there yet, each project and practice in its area, and the projects' tasks; replacing an earlier save of it when given",
  security: secured,
  request: { body: { content: { "application/json": { schema: PlateToSaveSchema } } } },
  responses: { 201: json(SavedPlateSchema, "Made"), ...errorResponses },
});

const FirstSeasonInputSchema = z
  .object({
    focus: z
      .array(
        z.object({
          goalId: z.uuid(),
          title: questWordsSchema.shape.title.openapi({ description: "The quest's name, as named on its card; starts as the goal's title." }),
        }),
      )
      .min(1)
      .max(MAX_QUESTS)
      .openapi({ description: "The focuses in order, each a project or practice in its own area." }),
    waiting: z.array(z.uuid()).openapi({ description: "What waits for next season. Its practices are paused until the season ends." }),
  })
  .openapi("FirstSeasonInput");

const FirstSeasonSchema = z
  .object({
    id: z.string(),
    startsOn: z.iso.date(),
    endsOn: z.iso.date().openapi({ description: "Its last day, included." }),
    quests: z
      .array(
        z
          .object({
            id: z.string(),
            goalId: z.string().openapi({ description: "The one project or practice that moves it." }),
            title: z.string(),
            position: z.int().openapi({ description: "Its number in the season, 1 first." }),
          })
          .openapi("FirstSeasonQuest"),
      )
      .openapi({ description: "In order." }),
  })
  .openapi("FirstSeason");

const seasonRoute = createRoute({
  method: "post",
  path: "/first-run/season",
  operationId: "startFirstSeason",
  summary: "Route 2: make a season from up to three focuses, each its own area's quest, start it, and pause what waits",
  security: secured,
  request: { body: { content: { "application/json": { schema: FirstSeasonInputSchema } } } },
  responses: { 201: json(FirstSeasonSchema, "Started"), ...errorResponses },
});

/** A plate as sent, with whatever was left out as null, as savePlate takes it. */
function asSortedPlate(plate: z.infer<typeof SortedPlateSchema>): SortedPlate {
  return {
    areas: plate.areas.map((area) => ({
      ...area,
      items: area.items.map((item) => ({
        ...item,
        detail: item.detail ?? null,
        perWeek: item.perWeek ?? null,
        targetDate: item.targetDate ?? null,
        bucket: item.bucket ?? false,
      })),
    })),
  };
}

function failure(error: unknown) {
  if (error instanceof FirstRunError) return apiError("first_run", error.message);
  if (error instanceof SeasonError) return apiError(error.code, error.message);
  if (error instanceof GoalLimitError || error instanceof AreaLimitError) return apiError("limit", error.message);
  throw error;
}

export const firstRun = new OpenAPIHono<ApiEnv>()
  .openapi(clarifyRoute, async (c) => {
    const userId = c.var.user.id;
    const { text, timeZone } = c.req.valid("json");
    try {
      const today = todayIn(timeZone ?? (await getTimeZone(userId)));
      return c.json({ questions: await clarifyPlate(userId, text, today) }, 200);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  })
  .openapi(sortRoute, async (c) => {
    const userId = c.var.user.id;
    const { text, timeZone, answers } = c.req.valid("json");
    try {
      const today = todayIn(timeZone ?? (await getTimeZone(userId)));
      const given = (answers ?? []).map((a) => ({ quote: a.quote, question: a.question, answer: a.answer ?? null, more: a.more ?? null }));
      return c.json(await sortPlate(userId, text, today, given), 200);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  })
  .openapi(saveRoute, async (c) => {
    try {
      const body = c.req.valid("json");
      return c.json(await savePlate(c.var.user.id, asSortedPlate(body), body.replacing), 201);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  })
  .openapi(seasonRoute, async (c) => {
    const userId = c.var.user.id;
    try {
      return c.json(await startFirstSeason(userId, c.req.valid("json"), todayIn(await getTimeZone(userId))), 201);
    } catch (error) {
      return c.json(failure(error), 400);
    }
  });
