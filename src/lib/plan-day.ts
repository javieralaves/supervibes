/*
 * Lays suggestions out on the calendar. Pure and client-safe: the page runs it
 * in the browser so times follow the viewer's own clock and time zone.
 *
 * Times are minutes from local midnight (0–1440); days are offsets from today.
 */

export const DAY_MINUTES = 24 * 60;

/** Blocks start on a quarter hour. */
const STEP = 15;
/** How far ahead suggestions can spill. */
export const MAX_DAYS = 7;

export type Sleep = { sleepStart: number; wakeTime: number };
export type Span = { start: number; end: number };

/** A block (or the part of one) on a given day. */
export type PlanBlock = Span & {
  id: string;
  goalId: string;
  day: number;
  title: string | null;
  keepOpen: boolean;
  fromSuggestion: string | null;
  taskId: string | null;
  fits: string[];
};

/** Something Glimpse can place: one of your open tasks, or a suggestion from a read. */
export type PlanItem = {
  kind: "task" | "suggestion";
  goalId: string;
  title: string;
  minutes: number;
  /** How titled blocks refer to it in `fits`: "t:<task id>" or "s:<suggestion title>". */
  fitKey: string;
};
export type Placed<T> = Span & { item: T; day: number; /** The protected block it sits in, if any. */ blockId: string | null };

/** The parts of any day spent asleep, e.g. 00:00–07:00 and 23:00–24:00. */
export function sleepSpans({ sleepStart, wakeTime }: Sleep): Span[] {
  if (sleepStart === wakeTime) return [];
  if (sleepStart < wakeTime) return [{ start: sleepStart, end: wakeTime }];
  return [
    { start: 0, end: wakeTime },
    { start: sleepStart, end: DAY_MINUTES },
  ].filter((s) => s.end > s.start);
}

/** `spans` with every interval in `cut` removed. */
function subtract(spans: Span[], cut: Span[]): Span[] {
  let out = spans;
  for (const c of cut) {
    out = out.flatMap((s) => {
      if (c.end <= s.start || c.start >= s.end) return [s];
      return [
        { start: s.start, end: c.start },
        { start: c.end, end: s.end },
      ].filter((p) => p.end > p.start);
    });
  }
  return out;
}

const isProtected = (b: PlanBlock) => !b.keepOpen && !b.fromSuggestion && !b.taskId;

/** Whether a titled block's matches include this item (plain titles are older suggestion matches). */
const fitsBlock = (block: PlanBlock, item: PlanItem) =>
  block.fits.includes(item.fitKey) || (item.kind === "suggestion" && block.fits.includes(item.title));

/** Goals in the order their items first appear, each with its items in order. */
function byGoal<T extends PlanItem>(items: T[]): T[][] {
  const groups = new Map<string, T[]>();
  for (const item of items) groups.set(item.goalId, [...(groups.get(item.goalId) ?? []), item]);
  return [...groups.values()];
}

/** Goals take turns: the first of each goal, then the second of each, and so on. */
function takeTurns<T>(groups: T[][]): T[] {
  const out: T[] = [];
  const rounds = Math.max(0, ...groups.map((g) => g.length));
  for (let i = 0; i < rounds; i++) for (const group of groups) if (group[i]) out.push(group[i]);
  return out;
}

/**
 * Places open tasks and suggestions from the next quarter hour after `now`.
 * Your tasks are your plan, so they get time before suggestions:
 *
 * 1. Left out: tasks already on the calendar from now on, and suggestions
 *    already turned into intentions.
 * 2. Each goal's protected blocks are filled first, soonest first, with that
 *    goal's tasks (in your order) and then its suggestions. An untitled block
 *    takes any of them; a titled one only those judged to fit it; kept-open
 *    blocks and intentions take nothing.
 * 3. Free awake time, back to back with blocks but never inside
 *    another goal's protected time: first the remaining tasks, goals taking
 *    turns and each goal's tasks in your order; then the remaining
 *    suggestions, goals taking turns and longer ones first. Each takes the
 *    earliest gap it fits, so a short one can still use a gap.
 *
 * `items` should list goals in their order. Nothing crosses midnight; anything
 * that doesn't fit within a week is left out.
 */
export function planDays<T extends PlanItem>(items: T[], now: number, sleep: Sleep, blocks: PlanBlock[]): Placed<T>[] {
  const firstStart = Math.ceil(now / STEP) * STEP;
  const earliest = (day: number) => (day === 0 ? firstStart : 0);

  // 1. What's already on the calendar.
  const upcoming = (b: PlanBlock) => b.day > 0 || (b.day === 0 && b.end > now);
  const scheduled = new Set(blocks.filter((b) => b.taskId && upcoming(b)).map((b) => `t:${b.taskId}`));
  const planned = new Set(blocks.filter((b) => b.fromSuggestion).map((b) => `${b.goalId}\n${b.fromSuggestion}`));
  const open = items.filter((item) =>
    item.kind === "task" ? !scheduled.has(item.fitKey) : !planned.has(`${item.goalId}\n${item.title}`),
  );

  const placed: Placed<T>[] = [];
  const taken = new Set<T>();

  // 2. Protected time first.
  const protectedBlocks = blocks
    .filter((b) => isProtected(b) && b.day >= 0 && b.day < MAX_DAYS && b.end > earliest(b.day))
    .sort((a, b) => a.day - b.day || a.start - b.start);
  for (const block of protectedBlocks) {
    let cursor = Math.max(block.start, Math.ceil(earliest(block.day) / STEP) * STEP);
    const candidates = [
      ...open.filter((i) => i.kind === "task"),
      ...open.filter((i) => i.kind === "suggestion"),
    ].filter((i) => i.goalId === block.goalId && !taken.has(i) && (!block.title || fitsBlock(block, i)));
    for (const item of candidates) {
      if (cursor + item.minutes > block.end) continue;
      placed.push({ item, day: block.day, start: cursor, end: cursor + item.minutes, blockId: block.id });
      taken.add(item);
      cursor += item.minutes;
    }
  }

  // 3. Free time for the rest.
  const awake = subtract([{ start: 0, end: DAY_MINUTES }], sleepSpans(sleep));
  const windows: (Span & { day: number; cursor: number })[] = [];
  for (let day = 0; day < MAX_DAYS; day++) {
    const busy = blocks
      .filter((b) => b.day === day)
      .map((b) => ({ start: b.start, end: b.end }));
    const free = subtract(awake, [...busy, { start: 0, end: earliest(day) }]);
    for (const span of free) {
      const start = Math.ceil(span.start / STEP) * STEP;
      if (span.end > start) windows.push({ day, start, end: span.end, cursor: start });
    }
  }

  const rest = open.filter((i) => !taken.has(i));
  const tasks = takeTurns(byGoal(rest.filter((i) => i.kind === "task")));
  const suggestions = takeTurns(byGoal(rest.filter((i) => i.kind === "suggestion"))).sort((a, b) => b.minutes - a.minutes);

  for (const item of [...tasks, ...suggestions]) {
    const window = windows.find((w) => w.cursor + item.minutes <= w.end);
    if (!window) continue;
    placed.push({ item, day: window.day, start: window.cursor, end: window.cursor + item.minutes, blockId: null });
    window.cursor += item.minutes;
  }
  return placed;
}
