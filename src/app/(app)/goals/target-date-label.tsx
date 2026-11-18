import { Calendar03Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { daysUntil, formatTargetDate, relativeTarget } from "@/lib/target-date";

/** "Mar 31 · in 19 weeks", turning amber once the day has passed. */
export function TargetDateLabel({ date, className = "" }: { date: string; className?: string }) {
  const days = daysUntil(date);
  return (
    // "Today" is the viewer's local day, which can differ from the server's.
    <span
      suppressHydrationWarning
      className={`flex items-center gap-1.5 tabular-nums ${days < 0 ? "text-amber-700 dark:text-amber-400" : "text-muted"} ${className}`}
    >
      <HugeiconsIcon icon={Calendar03Icon} size={14} className="shrink-0" />
      <span suppressHydrationWarning>
        {formatTargetDate(date)} · {relativeTarget(days)}
      </span>
    </span>
  );
}
