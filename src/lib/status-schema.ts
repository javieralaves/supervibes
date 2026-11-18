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

/** "On track", or for a goal judged on momentum, "Moving". */
export function statusLabel(status: GoalStatus, basis: StatusBasis): string {
  if (status === "unclear") return "Too early to tell";
  if (basis === "momentum") return { on_track: "Moving", at_risk: "Slowing", off_track: "Stalled" }[status];
  return { on_track: "On track", at_risk: "At risk", off_track: "Off track" }[status];
}

/** What the status is measured against, for a tooltip. */
export function basisLabel(basis: StatusBasis): string {
  return basis === "target" ? "Judged against the target date" : basis === "week" ? "Judged against this week's objective" : "Judged on momentum";
}
