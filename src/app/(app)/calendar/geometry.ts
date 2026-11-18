/* Shared layout of the day timeline. */

/** Height of one hour on the timeline, in px. */
export const HOUR = 176;
/** Room above midnight and below the last hour so their labels aren't clipped. */
export const PAD = 12;
/** Width of the hour-label column. */
export const GUTTER = "4rem";

/** Top of a time (minutes after midnight) on the timeline, in px. */
export const y = (minutes: number) => PAD + (minutes / 60) * HOUR;

/** Minutes after midnight at a y offset, unrounded. */
export const minutesAt = (px: number) => ((px - PAD) / HOUR) * 60;

export const DAY_MS = 24 * 60 * 60 * 1000;

/** Midnight at the start of `date`'s day, local time. */
export const startOfDay = (date: Date) => new Date(date.getFullYear(), date.getMonth(), date.getDate());

/** Days from `base` (a local midnight) to `date`'s day. Rounds away daylight-saving hours. */
export const dayOffset = (date: Date, base: Date) => Math.round((startOfDay(date).getTime() - base.getTime()) / DAY_MS);

/** ISO time for `minutes` after midnight, `day` days after `base`. */
export const isoAt = (base: Date, day: number, minutes: number) =>
  new Date(base.getFullYear(), base.getMonth(), base.getDate() + day, 0, minutes).toISOString();
