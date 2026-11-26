import "server-only";

import { createRoute, OpenAPIHono, z } from "@hono/zod-openapi";

import type { ApiEnv } from "@/lib/api/auth";
import { apiError, ErrorSchema, errorResponses } from "@/lib/api/errors";
import { listTrajectories } from "@/lib/goal-statuses";
import {
  getQuestRead,
  getSeasonRead,
  readQuest,
  readSeason,
  readStand,
  SeasonReadError,
  suggestForQuest,
  type ReadDTO,
} from "@/lib/season-reads";
import {
  defaultSeason,
  popularAreasFor,
  questEffort,
  questWordsSchema,
  seasonInputSchema,
  seasonStatus,
  seasonWeek,
  seasonWeeks,
} from "@/lib/season-schema";
import {
  createDraft,
  deleteDraft,
  getGap,
  getQuest,
  getSeason,
  getSeasons,
  listQuests,
  SeasonError,
  setQuestGoals,
  startSeason,
  updateQuest,
  updateSeason,
  type GapDTO,
  type QuestDTO,
  type SeasonDTO,
} from "@/lib/seasons";
import { listAreas } from "@/lib/areas";
import { getTimeZone } from "@/lib/settings";
import { timeZoneSchema } from "@/lib/settings-schema";
import { STATUSES } from "@/lib/status-schema";
import { todayIn } from "@/lib/target-date";

/*
 * Seasons and quests. A season is a stretch of weeks in which the person closes part of a few areas' gaps, each as a
 * quest; projects and practices move the quests. Statuses are counted on read: a quest's effort is its goals' worst,
 * a season's status its quests' worst (src/lib/season-schema.ts). The reads (src/lib/season-reads.ts) only run when
 * asked.
 */

export const GapSchema = z
  .object({
    title: z.string().openapi({ description: "The gap in a headline, e.g. From rituals you plan to rituals you keep." }),
    body: z.string().openapi({ description: "A line or two on what closing it takes; may be empty." }),
    by: z.enum(["supervibes", "you"]).openapi({ description: "Named by Supervibes when asked, or written by the person." }),
    at: z.iso.datetime().openapi({ description: "When it was last named or written." }),
  })
  .openapi("AreaGap");

const QuestSchema = z
  .object({
    id: z.string(),
    seasonId: z.string(),
    areaId: z.string(),
    title: z.string().openapi({ description: "Where it's headed by the season's end; also its name." }),
    fromText: z.string().openapi({ description: "Where it starts." }),
    reach: z.int().openapi({ description: "0–100: how much of the area's gap the season would close." }),
    chosen: z.boolean().openapi({ description: "Chosen for the season. A started season only has chosen quests." }),
    position: z.int().openapi({ description: "Its place among the chosen, 1 first; 0 while not chosen." }),
    goalIds: z.array(z.string()).openapi({ description: "The projects and practices that move it." }),
    effort: z.enum(STATUSES).nullable().openapi({ description: "The worst of its goals' statuses today; null with none." }),
  })
  .openapi("Quest");

const SeasonSchema = z
  .object({
    id: z.string(),
    name: z.string(),
    startsOn: z.iso.date(),
    endsOn: z.iso.date().openapi({ description: "Its last day, included." }),
    state: z.enum(["draft", "active", "ended"]),
    week: z.int().openapi({ description: "The week of the season today falls in, 1 first; 0 before it starts." }),
    weeks: z.int().openapi({ description: "How many weeks it runs." }),
    status: z.enum(STATUSES).nullable().openapi({ description: "The worst of its chosen quests' efforts; null with none." }),
    quests: z.array(QuestSchema).openapi({ description: "Chosen first, in order; then a draft's other candidates." }),
  })
  .openapi("Season");

const PopularAreaSchema = z
  .object({
    name: z.string(),
    icon: z.string().openapi({ description: "A Hugeicons name from lib/goal-icons.ts." }),
    line: z.string().openapi({ description: "What the area covers, in a line." }),
  })
  .openapi("PopularArea");

const CurrentSeasonsSchema = z
  .object({
    today: z.iso.date(),
    // The season running, the one being set up, and one that ended in the last four weeks; each null when there's none.
    // (No descriptions on these: a described reference becomes an allOf wrapper in the Swift client.)
    active: SeasonSchema.nullable(),
    draft: SeasonSchema.nullable(),
    ended: SeasonSchema.nullable(),
    popularAreas: z.array(PopularAreaSchema).openapi({ description: "The usual life areas the person doesn't have yet." }),
  })
  .openapi("CurrentSeasons");

const ReadSchema = z
  .object({
    headline: z.string(),
    summary: z.string(),
    goalIds: z.array(z.string()).openapi({ description: "The goals it drew on." }),
    usedCalendar: z.boolean().openapi({ description: "It drew on the person's time on the calendar." }),
    createdAt: z.iso.datetime(),
  })
  .openapi("SeasonRead");

const SeasonDetailSchema = z
  .object({
    season: SeasonSchema,
    // Its latest read; null until the person asks for one.
    read: ReadSchema.nullable(),
  })
  .openapi("SeasonDetail");

const QuestDetailSchema = z
  .object({
    quest: QuestSchema,
    season: SeasonSchema,
    // Its area's gap (null until named) and its latest read (null until asked for).
    gap: GapSchema.nullable(),
    read: ReadSchema.nullable(),
  })
  .openapi("QuestDetail");

const StandSchema = z.object({ gap: GapSchema, quest: QuestSchema }).openapi("AreaStand");

const SuggestionsSchema = z
  .object({
    suggestions: z.array(
      z
        .object({
          kind: z.enum(["project", "practice"]),
          title: z.string(),
          line: z.string().openapi({ description: "For a project, what done looks like; for a practice, how often and why." }),
          perWeek: z.int().nullable().openapi({ description: "For a practice, how many times a week; null for a project." }),
        })
        .openapi("QuestSuggestion"),
    ),
  })
  .openapi("QuestSuggestions");

const SeasonDaysSchema = z
  .object({
    // Each left out keeps what the season has (or, making one, the default: 13 weeks from the next Monday).
    name: z.string().optional(),
    startsOn: z.iso.date().optional(),
    endsOn: z.iso.date().optional(),
  })
  .openapi("SeasonDays");

const QuestChangeSchema = z
  .object({
    title: z.string().optional(),
    fromText: z.string().optional(),
    chosen: z.boolean().optional().openapi({ description: "Choose it for a draft season, or take it out. Up to three." }),
  })
  .openapi("QuestChange");

const QuestGoalsSchema = z
  .object({ goalIds: z.array(z.uuid()).openapi({ description: "Every goal that moves the quest. Each leaves any other quest of the season." }) })
  .openapi("QuestGoals");

const idParam = z.object({ id: z.uuid().openapi({ param: { name: "id", in: "path" } }) });
const standParams = z.object({
  id: z.uuid().openapi({ param: { name: "id", in: "path" } }),
  areaId: z.uuid().openapi({ param: { name: "areaId", in: "path" } }),
});
const tzQuery = z.object({
  timeZone: timeZoneSchema.optional().openapi({ description: "The device's time zone; defaults to the stored one." }),
});
const notFound = { description: "Not found.", content: { "application/json": { schema: ErrorSchema } } };
const json = <T extends z.ZodType>(schema: T, description = "OK") => ({ description, content: { "application/json": { schema } } });
const secured = [{ bearerAuth: [] }];

const currentRoute = createRoute({
  method: "get",
  path: "/seasons/current",
  operationId: "getCurrentSeasons",
  summary: "The season running, the one being set up, one that just ended, and the popular areas to offer",
  security: secured,
  request: { query: tzQuery },
  responses: { 200: json(CurrentSeasonsSchema), ...errorResponses },
});

const createSeasonRoute = createRoute({
  method: "post",
  path: "/seasons",
  operationId: "createSeason",
  summary: "Start setting up a season: a draft, by default 13 weeks from the next Monday",
  security: secured,
  request: { body: { required: false, content: { "application/json": { schema: SeasonDaysSchema } } } },
  responses: { 201: json(SeasonSchema, "Created"), ...errorResponses },
});

const getSeasonRoute = createRoute({
  method: "get",
  path: "/seasons/{id}",
  operationId: "getSeason",
  summary: "A season's page: the season, its quests and its read",
  security: secured,
  request: { params: idParam, query: tzQuery },
  responses: { 200: json(SeasonDetailSchema), ...errorResponses, 404: notFound },
});

const updateSeasonRoute = createRoute({
  method: "patch",
  path: "/seasons/{id}",
  operationId: "updateSeason",
  summary: "Rename a season or move its days. A running season keeps its first day",
  security: secured,
  request: { params: idParam, body: { required: true, content: { "application/json": { schema: SeasonDaysSchema } } } },
  responses: { 200: json(SeasonSchema, "Saved"), ...errorResponses, 404: notFound },
});

const deleteSeasonRoute = createRoute({
  method: "delete",
  path: "/seasons/{id}",
  operationId: "deleteSeason",
  summary: "Drop a draft season and what was set up in it",
  security: secured,
  request: { params: idParam },
  responses: { 204: { description: "Dropped" }, 401: errorResponses[401], 404: notFound },
});

const startRoute = createRoute({
  method: "post",
  path: "/seasons/{id}/start",
  operationId: "startSeason",
  summary: "Start a draft: one to three chosen quests, each moved by a project or practice",
  security: secured,
  request: { params: idParam },
  responses: { 200: json(SeasonSchema, "Started"), ...errorResponses, 404: notFound },
});

const readSeasonRoute = createRoute({
  method: "post",
  path: "/seasons/{id}/read",
  operationId: "readSeason",
  summary: "Write the season's read from its quests and the calendar, replacing the last; takes a few seconds",
  security: secured,
  request: { params: idParam },
  responses: { 200: json(ReadSchema, "Read"), ...errorResponses, 404: notFound },
});

const standRoute = createRoute({
  method: "post",
  path: "/seasons/{id}/areas/{areaId}/stand",
  operationId: "readAreaStand",
  summary: "For a draft: name the area's gap if it has none, and write its candidate quest; takes a few seconds",
  security: secured,
  request: { params: standParams },
  responses: { 200: json(StandSchema, "Read"), ...errorResponses, 404: notFound },
});

const getQuestRoute = createRoute({
  method: "get",
  path: "/quests/{id}",
  operationId: "getQuest",
  summary: "A quest's page: the quest, its season, its area's gap and its read",
  security: secured,
  request: { params: idParam, query: tzQuery },
  responses: { 200: json(QuestDetailSchema), ...errorResponses, 404: notFound },
});

const updateQuestRoute = createRoute({
  method: "patch",
  path: "/quests/{id}",
  operationId: "updateQuest",
  summary: "Edit a quest's words, or choose it for a draft season",
  security: secured,
  request: { params: idParam, body: { required: true, content: { "application/json": { schema: QuestChangeSchema } } } },
  responses: { 200: json(QuestSchema, "Saved"), ...errorResponses, 404: notFound },
});

const questGoalsRoute = createRoute({
  method: "put",
  path: "/quests/{id}/goals",
  operationId: "setQuestGoals",
  summary: "Set the projects and practices that move a quest",
  security: secured,
  request: { params: idParam, body: { required: true, content: { "application/json": { schema: QuestGoalsSchema } } } },
  responses: { 200: json(QuestSchema, "Saved"), ...errorResponses, 404: notFound },
});

const suggestRoute = createRoute({
  method: "post",
  path: "/quests/{id}/suggestions",
  operationId: "suggestForQuest",
  summary: "Suggest projects and practices that would move a quest; nothing is saved; takes a few seconds",
  security: secured,
  request: { params: idParam },
  responses: { 200: json(SuggestionsSchema), ...errorResponses, 404: notFound },
});

const readQuestRoute = createRoute({
  method: "post",
  path: "/quests/{id}/read",
  operationId: "readQuest",
  summary: "Write the quest's read from its projects, practices and the calendar, replacing the last; takes a few seconds",
  security: secured,
  request: { params: idParam },
  responses: { 200: json(ReadSchema, "Read"), ...errorResponses, 404: notFound },
});

export const asGapView = (gap: GapDTO) => ({ ...gap, at: gap.at.toISOString() });
const asReadView = (read: ReadDTO) => ({ ...read, createdAt: read.createdAt.toISOString() });

/** Seasons as the API sends them: each with its week, its quests' efforts and its status, counted today. */
async function asSeasons(userId: string, list: (SeasonDTO | null)[], timeZone: string | null) {
  const today = todayIn(timeZone);
  const seasonsWithQuests = await Promise.all(list.map(async (season) => (season ? { season, quests: await listQuests(userId, season.id) } : null)));
  const goalIds = [...new Set(seasonsWithQuests.flatMap((s) => s?.quests.flatMap((q) => q.goalIds) ?? []))];
  const trajectories = await listTrajectories(userId, goalIds, timeZone);
  const statusOf = (id: string) => trajectories.get(id)?.days.at(-1)?.status ?? null;
  return seasonsWithQuests.map((entry) => {
    if (!entry) return null;
    const { season, quests } = entry;
    const views = quests.map((quest) => asQuestView(quest, quest.goalIds.map(statusOf)));
    return {
      id: season.id,
      name: season.name,
      startsOn: season.startsOn,
      endsOn: season.endsOn,
      state: season.state,
      week: season.state === "draft" ? 0 : Math.min(seasonWeek(season.startsOn, season.endsOn, today), seasonWeeks(season.startsOn, season.endsOn)),
      weeks: seasonWeeks(season.startsOn, season.endsOn),
      status: seasonStatus(views.filter((q) => q.chosen).map((q) => q.effort)),
      quests: views,
    };
  });
}

const asQuestView = (quest: QuestDTO, statuses: (z.infer<typeof QuestSchema>["effort"])[]) => ({
  ...quest,
  effort: questEffort(statuses),
});

async function oneSeason(userId: string, season: SeasonDTO, timeZone: string | null) {
  const [view] = await asSeasons(userId, [season], timeZone);
  return view!;
}

/** A season change or read's error, as the API answers it. */
function seasonFailure(error: unknown) {
  if (error instanceof SeasonError) {
    return { status: error.code === "not_found" ? (404 as const) : (400 as const), body: apiError(error.code, error.message) };
  }
  if (error instanceof SeasonReadError) return { status: 400 as const, body: apiError("read_failed", error.message) };
  throw error;
}

/** The days a PATCH or POST asks for, filled in from what's there, checked by the season rules. */
function seasonDays(change: z.infer<typeof SeasonDaysSchema>, base: { name: string; startsOn: string; endsOn: string }) {
  return seasonInputSchema.safeParse({
    name: change.name ?? base.name,
    startsOn: change.startsOn ?? base.startsOn,
    endsOn: change.endsOn ?? base.endsOn,
  });
}

const SEASON_GONE = "That season doesn’t exist anymore.";
const QUEST_GONE = "That quest doesn’t exist anymore.";

export const seasonRoutes = new OpenAPIHono<ApiEnv>()
  .openapi(currentRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const today = todayIn(timeZone);
    const [{ active, draft, ended }, areas] = await Promise.all([getSeasons(userId, today), listAreas(userId)]);
    const [activeView, draftView, endedView] = await asSeasons(userId, [active, draft, ended], timeZone);
    const popularAreas = popularAreasFor(areas.map((a) => a.name)).map((a) => ({ ...a }));
    return c.json({ today, active: activeView, draft: draftView, ended: endedView, popularAreas }, 200);
  })
  .openapi(createSeasonRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = await getTimeZone(userId);
    const today = todayIn(timeZone);
    // The body is optional: none at all takes every default.
    const body = SeasonDaysSchema.safeParse(await c.req.json().catch(() => ({})));
    if (!body.success) return c.json(apiError("invalid_request", body.error.issues[0]?.message ?? "Check the days."), 400);
    const change = body.data;
    let input;
    if (change.name || change.startsOn || change.endsOn) {
      const { active } = await getSeasons(userId, today);
      const parsed = seasonDays(change, defaultSeason(active && active.endsOn > today ? active.endsOn : today));
      if (!parsed.success) return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the days."), 400);
      input = parsed.data;
    }
    try {
      return c.json(await oneSeason(userId, await createDraft(userId, today, input), timeZone), 201);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status === 404 ? 400 : failure.status);
    }
  })
  // After /seasons/current, so "current" isn't read as an id.
  .openapi(getSeasonRoute, async (c) => {
    const userId = c.var.user.id;
    const season = await getSeason(userId, c.req.valid("param").id);
    if (!season) return c.json(apiError("not_found", SEASON_GONE), 404);
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const [view, read] = await Promise.all([oneSeason(userId, season, timeZone), getSeasonRead(userId, season.id)]);
    return c.json({ season: view, read: read && asReadView(read) }, 200);
  })
  .openapi(updateSeasonRoute, async (c) => {
    const userId = c.var.user.id;
    const season = await getSeason(userId, c.req.valid("param").id);
    if (!season) return c.json(apiError("not_found", SEASON_GONE), 404);
    const parsed = seasonDays(c.req.valid("json"), season);
    if (!parsed.success) return c.json(apiError("invalid_request", parsed.error.issues[0]?.message ?? "Check the days."), 400);
    try {
      return c.json(await oneSeason(userId, await updateSeason(userId, season.id, parsed.data), await getTimeZone(userId)), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(deleteSeasonRoute, async (c) => {
    if (!(await deleteDraft(c.var.user.id, c.req.valid("param").id))) {
      return c.json(apiError("not_found", "There’s no season being set up with that id."), 404);
    }
    return c.body(null, 204);
  })
  .openapi(startRoute, async (c) => {
    const userId = c.var.user.id;
    const timeZone = await getTimeZone(userId);
    try {
      const season = await startSeason(userId, c.req.valid("param").id, todayIn(timeZone));
      return c.json(await oneSeason(userId, season, timeZone), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(readSeasonRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    if (!(await getSeason(userId, id))) return c.json(apiError("not_found", SEASON_GONE), 404);
    try {
      return c.json(asReadView(await readSeason(userId, id)), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(standRoute, async (c) => {
    const userId = c.var.user.id;
    const { id, areaId } = c.req.valid("param");
    if (!(await getSeason(userId, id))) return c.json(apiError("not_found", SEASON_GONE), 404);
    try {
      const { gap, quest } = await readStand(userId, id, areaId);
      const statuses = await listTrajectories(userId, quest.goalIds, await getTimeZone(userId));
      return c.json({ gap: asGapView(gap), quest: asQuestView(quest, quest.goalIds.map((g) => statuses.get(g)?.days.at(-1)?.status ?? null)) }, 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(getQuestRoute, async (c) => {
    const userId = c.var.user.id;
    const found = await getQuest(userId, c.req.valid("param").id);
    if (!found) return c.json(apiError("not_found", QUEST_GONE), 404);
    const timeZone = c.req.valid("query").timeZone ?? (await getTimeZone(userId));
    const [season, gap, read] = await Promise.all([
      oneSeason(userId, found.season, timeZone),
      getGap(userId, found.quest.areaId),
      getQuestRead(userId, found.quest.id),
    ]);
    const quest = season.quests.find((q) => q.id === found.quest.id)!;
    return c.json({ quest, season, gap: gap && asGapView(gap), read: read && asReadView(read) }, 200);
  })
  .openapi(updateQuestRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    const change = c.req.valid("json");
    const words = questWordsSchema.partial().safeParse({ title: change.title, fromText: change.fromText });
    if (!words.success) return c.json(apiError("invalid_request", words.error.issues[0]?.message ?? "Check the quest."), 400);
    try {
      await updateQuest(userId, id, { ...words.data, chosen: change.chosen });
      return c.json(await questView(userId, id), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(questGoalsRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    try {
      await setQuestGoals(userId, id, c.req.valid("json").goalIds);
      return c.json(await questView(userId, id), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(suggestRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    if (!(await getQuest(userId, id))) return c.json(apiError("not_found", QUEST_GONE), 404);
    try {
      return c.json({ suggestions: await suggestForQuest(userId, id) }, 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  })
  .openapi(readQuestRoute, async (c) => {
    const userId = c.var.user.id;
    const { id } = c.req.valid("param");
    if (!(await getQuest(userId, id))) return c.json(apiError("not_found", QUEST_GONE), 404);
    try {
      return c.json(asReadView(await readQuest(userId, id)), 200);
    } catch (error) {
      const failure = seasonFailure(error);
      return c.json(failure.body, failure.status);
    }
  });

/** One quest as the API sends it, with its effort counted today. */
async function questView(userId: string, questId: string) {
  const found = await getQuest(userId, questId);
  if (!found) throw new SeasonError("not_found", QUEST_GONE);
  const statuses = await listTrajectories(userId, found.quest.goalIds, await getTimeZone(userId));
  return asQuestView(
    found.quest,
    found.quest.goalIds.map((g) => statuses.get(g)?.days.at(-1)?.status ?? null),
  );
}

/** For GET /goals and the areas: each goal's quest in the running season, and each area's. */
export async function seasonLinks(userId: string, timeZone: string | null) {
  const today = todayIn(timeZone);
  const { active } = await getSeasons(userId, today);
  if (!active) return { goalQuest: new Map<string, string>(), areaQuest: new Map<string, string>() };
  const quests = await listQuests(userId, active.id);
  const goalQuest = new Map<string, string>();
  const areaQuest = new Map<string, string>();
  for (const quest of quests) {
    areaQuest.set(quest.areaId, quest.id);
    for (const goalId of quest.goalIds) goalQuest.set(goalId, quest.id);
  }
  return { goalQuest, areaQuest };
}
