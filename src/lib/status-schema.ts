/*
 * A goal's status, as each progress read judges it. Client-safe; storage lives in
 * goal-statuses.ts and the judging in progress.ts.
 *
 * What a status is measured against (its basis) depends on what the goal has:
 * - "target": its target date. On track: done by then at the current pace. At risk:
 *   still possible, but something needs to change. Off track: not at this pace.
 * - "week": no target date, but an objective for this week: the same, for the week.
 * - "momentum": neither: moving steadily, slowing, or stalled.
 * "unclear" is too little to go on, whatever the basis.
 */

export const STATUSES = ["on_track", "at_risk", "off_track", "unclear"] as const;
export type GoalStatus = (typeof STATUSES)[number];

export const STATUS_BASES = ["target", "week", "momentum"] as const;
export type StatusBasis = (typeof STATUS_BASES)[number];

export const CONFIDENCES = ["low", "medium", "high"] as const;
export type Confidence = (typeof CONFIDENCES)[number];

/** For a goal with a target date: where it's heading by then, if things go on as they are. */
export type Outlook = {
  status: Exclude<GoalStatus, "unclear">;
  /** The likely range of days it's done, "YYYY-MM-DD"; either can fall after the target date. */
  finishFrom: string | null;
  finishTo: string | null;
  confidence: Confidence;
};

/** A status as it's shown: the read's judgment, why, and when. */
export type StatusView = {
  status: GoalStatus;
  basis: StatusBasis;
  reason: string;
  outlook: Outlook | null;
  /** ISO time of the read it came from. */
  at: string;
};

/** How many days a trajectory shows, ending today. */
export const TRAJECTORY_DAYS = 28;

/**
 * One day of a goal's trajectory: the status as of that day. A day with a read has
 * that day's last status; a day without one carries the status before it, marked as
 * carried; days before the first status are empty.
 */
export type TrajectoryDay = {
  /** "YYYY-MM-DD", in the person's own calendar. */
  day: string;
  status: GoalStatus | null;
  basis: StatusBasis | null;
  reason: string | null;
  /** No read that day: the status shown is the one before it. */
  carried: boolean;
};

/**
 * Lays statuses out by day, oldest first, for the `days` days ending `today`.
 * `statuses` are the window's statuses with their day; `before` is the last one
 * before the window, if any, to carry into its first days.
 */
export function buildTrajectory(
  statuses: { day: string; status: GoalStatus; basis: StatusBasis; reason: string; at: string }[],
  before: { status: GoalStatus; basis: StatusBasis; reason: string } | null,
  today: string,
  days = TRAJECTORY_DAYS,
): TrajectoryDay[] {
  const first = shiftDay(today, -(days - 1));
  // The last status of each day; any from before the window carry into it.
  const byDay = new Map<string, (typeof statuses)[number]>();
  let last = before;
  for (const s of statuses.toSorted((a, b) => a.at.localeCompare(b.at))) {
    if (s.day < first) last = s;
    else byDay.set(s.day, s);
  }

  const out: TrajectoryDay[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = shiftDay(today, -i);
    const own = byDay.get(day);
    if (own) last = own;
    out.push({
      day,
      status: last?.status ?? null,
      basis: last?.basis ?? null,
      reason: last?.reason ?? null,
      carried: !own && last !== null,
    });
  }
  return out;
}

function shiftDay(day: string, n: number): string {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d) + n * 86_400_000).toISOString().slice(0, 10);
}
