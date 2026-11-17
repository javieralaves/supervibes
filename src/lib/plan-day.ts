/*
 * Lays suggestions out on the calendar, inside the user's awake hours. Pure and
 * client-safe: the page runs it in the browser so times follow the viewer's own
 * clock and time zone.
 *
 * Times are minutes from local midnight (0–1440); days are offsets from today.
 */

export const DAY_MINUTES = 24 * 60;

/** Blocks start on a quarter hour. */
const STEP = 15;
/** Breathing room between one block and the next. */
const GAP = 15;
/** How far ahead suggestions can spill. */
const MAX_DAYS = 7;

export type Sleep = { sleepStart: number; wakeTime: number };
export type Span = { start: number; end: number };
export type Placed<T> = Span & { item: T; day: number };

/** The parts of any day spent asleep, e.g. 00:00–07:00 and 23:00–24:00. */
export function sleepSpans({ sleepStart, wakeTime }: Sleep): Span[] {
  if (sleepStart === wakeTime) return [];
  if (sleepStart < wakeTime) return [{ start: sleepStart, end: wakeTime }];
  return [
    { start: 0, end: wakeTime },
    { start: sleepStart, end: DAY_MINUTES },
  ].filter((s) => s.end > s.start);
}

/** The parts of any day spent awake: everything that isn't sleep. */
function awakeSpans(sleep: Sleep): Span[] {
  const spans: Span[] = [];
  let cursor = 0;
  for (const s of sleepSpans(sleep)) {
    if (s.start > cursor) spans.push({ start: cursor, end: s.start });
    cursor = s.end;
  }
  if (cursor < DAY_MINUTES) spans.push({ start: cursor, end: DAY_MINUTES });
  return spans;
}

/**
 * Places each goal's suggestions in awake time, starting at the next quarter
 * hour after `now` today and carrying on through the following days. Goals take
 * turns (first suggestion of each goal, then the second of each, …) so no single
 * goal fills a day. Each suggestion takes the earliest gap it fits in, so a
 * shorter one can still use time a longer one couldn't. Blocks never cross
 * midnight; anything that doesn't fit within a week is left out.
 */
export function planDays<T extends { minutes: number }>(groups: T[][], now: number, sleep: Sleep): Placed<T>[] {
  const queue: T[] = [];
  const rounds = Math.max(0, ...groups.map((g) => g.length));
  for (let i = 0; i < rounds; i++) {
    for (const group of groups) if (group[i]) queue.push(group[i]);
  }

  const firstStart = Math.ceil(now / STEP) * STEP;
  const windows: (Span & { day: number; cursor: number })[] = [];
  for (let day = 0; day < MAX_DAYS; day++) {
    for (const span of awakeSpans(sleep)) {
      const start = day === 0 ? Math.max(span.start, firstStart) : span.start;
      if (span.end > start) windows.push({ day, start, end: span.end, cursor: start });
    }
  }

  const placed: Placed<T>[] = [];
  for (const item of queue) {
    const window = windows.find((w) => w.cursor + item.minutes <= w.end);
    if (!window) continue;
    placed.push({ item, day: window.day, start: window.cursor, end: window.cursor + item.minutes });
    window.cursor += item.minutes + GAP;
  }
  return placed;
}
