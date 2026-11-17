/*
 * Lays suggestions out on the calendar. Pure and client-safe: the page runs it
 * in the browser so times follow the viewer's own clock and time zone.
 *
 * Times are minutes from local midnight (0–1440); days are offsets from today.
 */

export const DAY_MINUTES = 24 * 60;

/** Blocks start on a quarter hour. */
const STEP = 15;
/** Breathing room between one thing and the next. */
const GAP = 15;
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
  fits: string[];
};

export type PlanItem = { goalId: string; title: string; minutes: number };
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

const isProtected = (b: PlanBlock) => !b.keepOpen && !b.fromSuggestion;

/**
 * Places the goals' open suggestions from the next quarter hour after `now`:
 *
 * 1. Suggestions already planned as intentions are left out.
 * 2. Each goal's protected blocks are filled first, soonest first: an untitled
 *    block takes any of the goal's suggestions, a titled one only those judged
 *    to fit it. Kept-open blocks and intentions take nothing.
 * 3. The rest go into free awake time, with breathing room around blocks and
 *    never inside another goal's protected time. Longer suggestions go first so
 *    they get the longer stretches and shorter ones fill the gaps; within the
 *    same length, goals take turns.
 *
 * Nothing crosses midnight; anything that doesn't fit within a week is left out.
 */
export function planDays<T extends PlanItem>(groups: T[][], now: number, sleep: Sleep, blocks: PlanBlock[]): Placed<T>[] {
  const planned = new Set(blocks.filter((b) => b.fromSuggestion).map((b) => `${b.goalId}\n${b.fromSuggestion}`));
  const open = groups.map((g) => g.filter((item) => !planned.has(`${item.goalId}\n${item.title}`)));

  const firstStart = Math.ceil(now / STEP) * STEP;
  const earliest = (day: number) => (day === 0 ? firstStart : 0);
  const placed: Placed<T>[] = [];
  const taken = new Set<T>();

  // 2. Protected time first.
  const protectedBlocks = blocks
    .filter((b) => isProtected(b) && b.day >= 0 && b.day < MAX_DAYS && b.end > earliest(b.day))
    .sort((a, b) => a.day - b.day || a.start - b.start);
  for (const block of protectedBlocks) {
    let cursor = Math.max(block.start, Math.ceil(earliest(block.day) / STEP) * STEP);
    const candidates = open
      .flat()
      .filter((item) => item.goalId === block.goalId && !taken.has(item))
      .filter((item) => !block.title || block.fits.includes(item.title));
    for (const item of candidates) {
      if (cursor + item.minutes > block.end) continue;
      placed.push({ item, day: block.day, start: cursor, end: cursor + item.minutes, blockId: block.id });
      taken.add(item);
      cursor += item.minutes + GAP;
    }
  }

  // 3. Free time for the rest.
  const awake = subtract([{ start: 0, end: DAY_MINUTES }], sleepSpans(sleep));
  const windows: (Span & { day: number; cursor: number })[] = [];
  for (let day = 0; day < MAX_DAYS; day++) {
    const busy = blocks
      .filter((b) => b.day === day)
      .map((b) => ({ start: b.start - GAP, end: b.end + GAP }));
    const free = subtract(awake, [...busy, { start: 0, end: earliest(day) }]);
    for (const span of free) {
      const start = Math.ceil(span.start / STEP) * STEP;
      if (span.end > start) windows.push({ day, start, end: span.end, cursor: start });
    }
  }

  const queue: T[] = [];
  const rounds = Math.max(0, ...open.map((g) => g.length));
  for (let i = 0; i < rounds; i++) {
    for (const group of open) if (group[i] && !taken.has(group[i])) queue.push(group[i]);
  }
  queue.sort((a, b) => b.minutes - a.minutes);

  for (const item of queue) {
    const window = windows.find((w) => w.cursor + item.minutes <= w.end);
    if (!window) continue;
    placed.push({ item, day: window.day, start: window.cursor, end: window.cursor + item.minutes, blockId: null });
    window.cursor += item.minutes + GAP;
  }
  return placed;
}
