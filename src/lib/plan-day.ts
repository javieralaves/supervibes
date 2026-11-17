/*
 * Lays suggestions out on today's timeline. Pure and client-safe: the page runs
 * it in the browser so times follow the viewer's own clock and time zone.
 *
 * Times are minutes from local midnight (0–1440).
 */

export const DAY_MINUTES = 24 * 60;

/** Blocks start on a quarter hour. */
const STEP = 15;
/** Breathing room between one block and the next. */
const GAP = 15;

export type Placed<T> = { item: T; start: number; end: number };

/**
 * Places each goal's suggestions from the next quarter hour after `now` until
 * midnight, one block after another with a short gap. Goals take turns (first
 * suggestion of each goal, then the second of each, …) so no single goal fills
 * the day. Anything that doesn't fit before midnight is returned as `overflow`;
 * a later, shorter one can still take the remaining time.
 */
export function planDay<T extends { minutes: number }>(
  groups: T[][],
  now: number,
): { placed: Placed<T>[]; overflow: T[] } {
  const queue: T[] = [];
  const rounds = Math.max(0, ...groups.map((g) => g.length));
  for (let i = 0; i < rounds; i++) {
    for (const group of groups) if (group[i]) queue.push(group[i]);
  }

  const placed: Placed<T>[] = [];
  const overflow: T[] = [];
  let cursor = Math.ceil(now / STEP) * STEP;

  for (const item of queue) {
    const end = cursor + item.minutes;
    if (end > DAY_MINUTES) {
      overflow.push(item);
      continue;
    }
    placed.push({ item, start: cursor, end });
    cursor = end + GAP;
  }

  return { placed, overflow };
}

/** "09:30" from minutes after midnight. */
export function clockLabel(minutes: number) {
  const h = Math.floor(minutes / 60) % 24;
  const m = Math.floor(minutes % 60);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}
