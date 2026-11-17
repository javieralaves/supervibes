/*
 * The shape of a day on the calendar. Pure and client-safe: times are minutes
 * from local midnight (0–1440); days are offsets from today.
 */

export const DAY_MINUTES = 24 * 60;

export type Sleep = { sleepStart: number; wakeTime: number };
export type Span = { start: number; end: number };

/** A block (or the part of one) on a given day. */
export type DaySegment = Span & {
  id: string;
  goalId: string;
  day: number;
  title: string | null;
  fromSuggestion: string | null;
  taskId: string | null;
};

/** The parts of any day spent asleep, e.g. 00:00–07:00 and 23:00–24:00. */
export function sleepSpans({ sleepStart, wakeTime }: Sleep): Span[] {
  if (sleepStart === wakeTime) return [];
  if (sleepStart < wakeTime) return [{ start: sleepStart, end: wakeTime }];
  return [
    { start: 0, end: wakeTime },
    { start: sleepStart, end: DAY_MINUTES },
  ].filter((s) => s.end > s.start);
}
