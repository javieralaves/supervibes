"use client";

import { Calendar03Icon, Cancel01Icon, Flag02Icon } from "@hugeicons/core-free-icons";
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
  const dueLabel =
    due === "overdue" && task.dueOn ? `Overdue since ${relativeDayLabel(task.dueOn, today)}` : due ? "Due this day" : null;
  const carried = carriedFrom ? `from ${relativeDayLabel(carriedFrom, today)}` : null;
  // The icon says why it's here: a flag when it's due (red once overdue), a calendar when it's planned.
  const icon = due ? Flag02Icon : Calendar03Icon;
  const iconTone =
    due === "overdue" ? "text-red-600 dark:text-red-400" : "text-[var(--goal-light)] dark:text-[var(--goal-dark)]";
  return (
    <li
      style={goalColorStyle(goal?.color ?? "slate")}
      onPointerDown={pending ? undefined : onPointerDown}
      aria-roledescription="draggable task"
      aria-label={[task.title, minutesLabel(task.minutes), planned && (carried ? `planned ${carried}` : "planned"), dueLabel]
        .filter(Boolean)
        .join(", ")}
      title={[task.title, planned && !carried ? "Planned for this day" : carried && `Planned ${carried}`, dueLabel]
        .filter(Boolean)
        .concat("Drag onto the timeline to give it a time")
        .join("\n")}
      // Capped, so a few fit side by side; the full title is in the tooltip.
      // --chip is the chip's tint as a solid colour, for the × to fade in over its end.
      className={`goal-tint group relative flex max-w-[min(100%,17rem)] touch-none select-none items-center gap-1.5 overflow-hidden rounded-lg border border-card-border bg-card py-1 pl-2 pr-2.5 [--chip:color-mix(in_oklab,var(--goal)_13%,var(--card))] dark:[--chip:color-mix(in_oklab,var(--goal)_18%,var(--card))] shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-opacity ${dragging || pending ? "opacity-50" : "cursor-grab"}`}
    >
      <HugeiconsIcon icon={icon} size={13} className={`shrink-0 ${iconTone}`} />
      <span className="min-w-0 truncate text-[13px] font-medium text-foreground">{task.title}</span>
      <span className="shrink-0 text-[11px] tabular-nums text-muted">{minutesLabel(task.minutes)}</span>
      {carried && <span className="shrink-0 text-[11px] font-medium text-amber-700 dark:text-amber-400">{carried}</span>}
      {/* Takes no room: it fades in over the end of the chip on hover. */}
      {planned && !pending && (
        <button
          type="button"
          aria-label={`Take “${task.title}” off this day`}
          title="Take it off this day"
          onClick={onUnplan}
          className="group/x absolute inset-y-0 right-0 flex items-center pl-4 pr-1 text-muted opacity-0 transition-opacity [background:linear-gradient(to_right,transparent,var(--chip)_0.875rem)] focus-visible:opacity-100 group-hover:opacity-100 [@media(hover:none)]:opacity-100"
        >
          <span className="flex h-5 w-5 items-center justify-center rounded-md transition-colors group-hover/x:bg-foreground/10 group-hover/x:text-foreground">
            <HugeiconsIcon icon={Cancel01Icon} size={12} />
          </span>
        </button>
      )}
    </li>
  );
}
