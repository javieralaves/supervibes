import { formatTargetDate, relativeDayLabel } from "@/lib/target-date";
import { statusLabel, type GoalStatus, type TrajectoryDay } from "@/lib/status-schema";

/*
 * A goal's status over the last few weeks, one cell a day, oldest on the left:
 * solid where a read judged it that day, lighter where the status carried over from
 * an earlier read, and blank before the first. Full size, each day shows its status
 * and why on hover; the mini version is a glanceable stripe for cards.
 */

const SOLID: Record<GoalStatus, string> = {
  on_track: "bg-emerald-500",
  at_risk: "bg-amber-500",
  off_track: "bg-red-500",
  unclear: "bg-foreground/25",
};
const CARRIED: Record<GoalStatus, string> = {
  on_track: "bg-emerald-500/35",
  at_risk: "bg-amber-500/35",
  off_track: "bg-red-500/35",
  unclear: "bg-foreground/12",
};

function tone(d: TrajectoryDay) {
  if (!d.status) return "bg-foreground/[.06]";
  return d.carried ? CARRIED[d.status] : SOLID[d.status];
}

export function StatusTrajectory({
  days,
  today,
  size = "full",
  className = "",
}: {
  days: TrajectoryDay[];
  /** The person's today, "YYYY-MM-DD", for the hover labels. */
  today: string;
  size?: "full" | "mini";
  className?: string;
}) {
  const summary = days
    .filter((d) => d.status && !d.carried)
    .map((d) => `${formatTargetDate(d.day, today)}: ${statusLabel(d.status!, d.basis!)}`)
    .join("; ");

  if (size === "mini") {
    return (
      <div role="img" aria-label={summary ? `Status over the last weeks: ${summary}` : "No status yet"} className={`flex h-1.5 gap-px ${className}`}>
        {days.map((d) => (
          <span key={d.day} className={`h-full flex-1 first:rounded-l-full last:rounded-r-full ${tone(d)}`} />
        ))}
      </div>
    );
  }

  return (
    <div role="group" aria-label="Status over the last weeks" className={`flex h-3 gap-[3px] ${className}`}>
      {days.map((d, i) => {
        const label = d.status ? statusLabel(d.status, d.basis!) : "No status yet";
        // Near either end, the hover card lines up with that end so it stays on screen.
        const align = i < 4 ? "left-0" : i >= days.length - 4 ? "right-0" : "left-1/2 -translate-x-1/2";
        const when = relativeDayLabel(d.day, today);
        return (
          <span
            key={d.day}
            tabIndex={-1}
            aria-label={`${when}: ${label}${d.carried ? ", from an earlier read" : ""}`}
            className={`group/day relative h-full flex-1 rounded-[3px] ${tone(d)} ${
              d.day === today ? "ring-1 ring-foreground/40 ring-offset-1 ring-offset-card" : ""
            }`}
          >
            {/* The day's status and why, above it on hover. */}
            <span className={`pointer-events-none absolute bottom-full ${align} z-20 mb-2 hidden w-56 rounded-lg border border-card-border bg-card px-2.5 py-2 text-left shadow-[0_8px_24px_-8px_rgb(15_17_20/0.25)] group-hover/day:block`}>
              <span className="block text-[11px] text-muted">
                {formatTargetDate(d.day, today)}
                {when !== formatTargetDate(d.day, today) && ` · ${when}`}
              </span>
              <span className="mt-0.5 block text-xs font-medium text-foreground">
                {label}
                {d.carried && <span className="font-normal text-muted"> · no read this day</span>}
              </span>
              {d.reason && <span className="mt-1 block text-xs leading-snug text-muted">{d.reason}</span>}
            </span>
          </span>
        );
      })}
    </div>
  );
}
