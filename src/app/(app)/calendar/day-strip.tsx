"use client";

import { Cancel01Icon, CircleIcon, Flag02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { goalColorStyle } from "@/lib/goal-colors";
import { minutesLabel } from "@/lib/task-schema";
import { relativeDayLabel } from "@/lib/target-date";

import type { CalendarGoal } from "./calendar-items";
import type { PanelTask } from "./task-panel";

/** A task on a day's strip: planned for that day without a time, or due that day. */
export type StripItem = {
  task: PanelTask;
  /** Planned for this day (or, on today, for an earlier day it wasn't done on). */
  planned: boolean;
  /** On today: the earlier day it was planned for and missed, "YYYY-MM-DD". */
  carriedFrom: string | null;
  /** Due this day, or on today, overdue since an earlier one. */
  due: "due" | "overdue" | null;
};

/**
 * The top of a day, above its timeline: tasks meant for that day but not yet
 * given a time, and tasks due that day. On today, missed plans and overdue tasks
 * carry over. Drop a task here to plan it for the day; drag one from here onto
 * the timeline to give it a time.
 */
export function DayStrip({
  items,
  goals,
  today,
  dayName,
  dropping,
  dragging,
  draggingId,
  onTaskPointerDown,
  onUnplan,
}: {
  items: StripItem[];
  goals: Map<string, CalendarGoal>;
  /** The viewer's today, "YYYY-MM-DD", for "from Mon" and "Overdue · Mon". */
  today: string;
  /** "Friday", for the drop hint. */
  dayName: string;
  /** A dragged task is over the strip. */
  dropping: boolean;
  /** A task is being dragged anywhere. */
  dragging: boolean;
  draggingId: string | null;
  onTaskPointerDown: (e: React.PointerEvent<HTMLElement>, task: PanelTask) => void;
  onUnplan: (task: PanelTask) => void;
}) {
  return (
    <div
      data-day-strip
      aria-label={`Planned for ${dayName}, without a time`}
      className={`flex shrink-0 items-start border-b border-card-border transition-colors ${
        dropping ? "bg-foreground/[.05]" : ""
      }`}
    >
      <span className="w-16 shrink-0 pr-2 pt-3 text-right text-[11px] font-medium text-muted">Anytime</span>
      <div className="flex min-h-11 min-w-0 flex-1 flex-wrap items-center gap-1.5 py-2 pr-3">
        {items.length === 0 ? (
          <p className={`px-1 text-xs ${dropping ? "text-foreground" : "text-muted"}`}>
            {dragging ? `Drop to plan it for ${dayName}` : "Drag a task here to plan it for the day, without a time."}
          </p>
        ) : (
          <ul className="contents">
            {items.map((item) => (
              <StripChip
                key={item.task.id}
                item={item}
                goal={goals.get(item.task.goalId)}
                today={today}
                dragging={item.task.id === draggingId}
                onPointerDown={(e) => onTaskPointerDown(e, item.task)}
                onUnplan={() => onUnplan(item.task)}
              />
            ))}
          </ul>
        )}
        {dropping && items.length > 0 && <p className="px-1 text-xs text-foreground">Drop to plan it for {dayName}</p>}
      </div>
    </div>
  );
}

function StripChip({
  item,
  goal,
  today,
  dragging,
  onPointerDown,
  onUnplan,
}: {
  item: StripItem;
  goal: CalendarGoal | undefined;
  today: string;
  dragging: boolean;
  onPointerDown: (e: React.PointerEvent<HTMLLIElement>) => void;
  onUnplan: () => void;
}) {
  const { task, planned, carriedFrom, due } = item;
  const pending = task.block?.id.startsWith("pending-") ?? false;
  const dueLabel = due === "overdue" && task.dueOn ? `Overdue · ${relativeDayLabel(task.dueOn, today)}` : due ? "Due" : null;
  const carried = carriedFrom ? `from ${relativeDayLabel(carriedFrom, today)}` : null;
  return (
    <li
      style={goalColorStyle(goal?.color ?? "slate")}
      onPointerDown={pending ? undefined : onPointerDown}
      aria-roledescription="draggable task"
      aria-label={[task.title, minutesLabel(task.minutes), carried && `planned ${carried}`, dueLabel].filter(Boolean).join(", ")}
      title={`${task.title}\nDrag onto the timeline to give it a time`}
      // Capped, so a few fit side by side; the full title is in the tooltip.
      className={`goal-tint group relative flex max-w-[min(100%,17rem)] touch-none select-none items-center gap-1.5 rounded-lg border border-card-border bg-card py-1 pl-2 ${
        planned ? "pr-7" : "pr-2.5"
      } shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-opacity ${dragging || pending ? "opacity-50" : "cursor-grab"}`}
    >
      <HugeiconsIcon icon={CircleIcon} size={12} className="shrink-0 text-[var(--goal-light)] dark:text-[var(--goal-dark)]" />
      <span className="min-w-0 truncate text-[13px] font-medium text-foreground">{task.title}</span>
      <span className="shrink-0 text-[11px] tabular-nums text-muted">{minutesLabel(task.minutes)}</span>
      {carried && <span className="shrink-0 text-[11px] font-medium text-amber-700 dark:text-amber-400">{carried}</span>}
      {dueLabel && (
        <span
          className={`flex shrink-0 items-center gap-0.5 text-[11px] font-medium ${
            due === "overdue" ? "text-red-600 dark:text-red-400" : "text-foreground"
          }`}
        >
          <HugeiconsIcon icon={Flag02Icon} size={11} />
          {dueLabel}
        </span>
      )}
      {planned && !pending && (
        <button
          type="button"
          aria-label={`Take “${task.title}” off this day`}
          title="Take it off this day"
          onClick={onUnplan}
          className="absolute right-1 top-1/2 flex h-5 w-5 -translate-y-1/2 items-center justify-center rounded-md text-muted opacity-0 transition-opacity hover:bg-wash hover:text-foreground focus-visible:opacity-100 group-hover:opacity-100 [@media(hover:none)]:opacity-100"
        >
          <HugeiconsIcon icon={Cancel01Icon} size={12} />
        </button>
      )}
    </li>
  );
}
