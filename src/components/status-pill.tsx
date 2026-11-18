import { basisLabel, statusLabel, type GoalStatus, type StatusBasis } from "@/lib/status-schema";

/** Quiet tones per status: a dot and a tinted pill, never shouting. */
const TONE: Record<GoalStatus, { pill: string; dot: string }> = {
  on_track: { pill: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-400", dot: "bg-emerald-500" },
  at_risk: { pill: "bg-amber-500/12 text-amber-700 dark:text-amber-400", dot: "bg-amber-500" },
  off_track: { pill: "bg-red-500/10 text-red-700 dark:text-red-400", dot: "bg-red-500" },
  unclear: { pill: "bg-foreground/[.06] text-muted", dot: "bg-foreground/30" },
};

/** A goal's status as a small pill: "On track", "At risk", "Off track", or on momentum "Moving" and so on. */
export function StatusPill({
  status,
  basis,
  className = "",
}: {
  status: GoalStatus;
  basis: StatusBasis;
  className?: string;
}) {
  const tone = TONE[status];
  return (
    <span
      title={basisLabel(basis)}
      className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium ${tone.pill} ${className}`}
    >
      <span aria-hidden="true" className={`h-1.5 w-1.5 rounded-full ${tone.dot}`} />
      {statusLabel(status, basis)}
    </span>
  );
}

const TEXT: Record<GoalStatus, string> = {
  on_track: "text-emerald-700 dark:text-emerald-400",
  at_risk: "text-amber-700 dark:text-amber-400",
  off_track: "text-red-700 dark:text-red-400",
  unclear: "text-muted",
};

/** A quieter status: a dot and the word in its colour, with no pill behind it. For dense places like cards. */
export function StatusText({ status, basis, className = "" }: { status: GoalStatus; basis: StatusBasis; className?: string }) {
  return (
    <span title={basisLabel(basis)} className={`inline-flex items-center gap-1.5 font-medium ${TEXT[status]} ${className}`}>
      <span aria-hidden="true" className={`h-1.5 w-1.5 shrink-0 rounded-full ${TONE[status].dot}`} />
      {statusLabel(status, basis)}
    </span>
  );
}
