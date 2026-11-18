"use client";

import { CircleIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { GoalBadge } from "@/components/goal-badge";
import { formatTime } from "@/lib/clock";
import { goalColorStyle } from "@/lib/goal-colors";
import type { BlockView } from "@/lib/block-schema";
import type { Clock } from "@/lib/settings-schema";
import { minutesLabel } from "@/lib/task-schema";
import { daysUntil, relativeDayLabel } from "@/lib/target-date";

import type { CalendarGoal } from "./calendar-items";

/** An open task as the panel lists it. */
export type PanelTask = {
  id: string;
  goalId: string;
  title: string;
  minutes: number;
  /** The day it's planned for, "YYYY-MM-DD". */
  plannedFor: string | null;
  /** The day it's due, "YYYY-MM-DD". */
  dueOn: string | null;
  /** Its next block that hasn't ended. Dropping the task moves this block instead of adding another. */
  block: BlockView | null;
};

export type PanelGroup = { goal: CalendarGoal; tasks: PanelTask[] };

/**
 * Open tasks across goals, beside the calendar. Drag one onto the day to give it
 * a time, or onto the day's strip to plan it for the day. Tasks planned for the
 * shown day lead their goal; scheduled tasks sit at the end, faded, with their
 * time, and dragging one moves its block. Each shows its planned day and due date.
 */
export function TaskPanel({
  groups,
  clock,
  today,
  todayISO,
  draggingId,
  onTaskPointerDown,
}: {
  groups: PanelGroup[];
  clock: Clock;
  /** Local midnight today, for "Today" and "Tomorrow" labels. */
  today: Date | null;
  /** Today as "YYYY-MM-DD", for planned days and due dates. */
  todayISO: string | null;
  /** The task being dragged, if any. */
  draggingId: string | null;
  onTaskPointerDown: (e: React.PointerEvent<HTMLElement>, task: PanelTask) => void;
}) {
  const count = groups.reduce((n, g) => n + g.tasks.length, 0);
  return (
    <aside
      data-task-panel
      aria-label="Open tasks"
      className="hidden w-72 shrink-0 flex-col overflow-hidden rounded-2xl border border-card-border bg-card lg:flex"
    >
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-2 py-2">
        <h2 className="px-2 pb-1 pt-1.5 text-[15px] font-semibold tracking-[-0.01em] text-foreground">Tasks</h2>
        {count === 0 ? (
          <p className="px-2 py-1.5 text-sm text-muted">No open tasks. Add tasks to a goal and they show up here.</p>
        ) : (
          groups.map(({ goal, tasks }) => (
            <section key={goal.id} aria-label={goal.title} className="py-1.5">
              <h3 className="flex items-center gap-2 px-2 pb-1 pt-0.5">
                <GoalBadge icon={goal.icon} color={goal.color} size="xs" />
                <span className="truncate text-[13px] font-semibold text-foreground">{goal.title}</span>
              </h3>
              <ul>
                {tasks.map((task) => (
                  <TaskRow
                    key={task.id}
                    task={task}
                    goal={goal}
                    clock={clock}
                    today={today}
                    todayISO={todayISO}
                    dragging={task.id === draggingId}
                    onPointerDown={(e) => onTaskPointerDown(e, task)}
                  />
                ))}
              </ul>
            </section>
          ))
        )}
      </div>
    </aside>
  );
}

function TaskRow({
  task,
  goal,
  clock,
  today,
  todayISO,
  dragging,
  onPointerDown,
}: {
  task: PanelTask;
  goal: CalendarGoal;
  clock: Clock;
  today: Date | null;
  todayISO: string | null;
  dragging: boolean;
  onPointerDown: (e: React.PointerEvent<HTMLElement>) => void;
}) {
  const pending = task.block?.id.startsWith("pending-") ?? false;
  const scheduled = task.block ? scheduleLabel(task.block.startsAt, today, clock) : null;
  // A time says when already; without one, the day it's planned for.
  const planned = !scheduled && task.plannedFor && todayISO ? relativeDayLabel(task.plannedFor, todayISO) : null;
  const missed = Boolean(planned && todayISO && daysUntil(task.plannedFor!, todayISO) < 0);
  const overdue = Boolean(task.dueOn && todayISO && daysUntil(task.dueOn, todayISO) < 0);
  const due = task.dueOn && todayISO ? `${overdue ? "Overdue" : "Due"} ${relativeDayLabel(task.dueOn, todayISO)}` : null;
  return (
    <li
      style={goalColorStyle(goal.color)}
      onPointerDown={pending ? undefined : onPointerDown}
      aria-roledescription="draggable task"
      aria-label={[
        task.title,
        minutesLabel(task.minutes),
        scheduled && `scheduled ${scheduled}`,
        planned && `planned for ${planned}`,
        due,
      ]
        .filter(Boolean)
        .join(", ")}
      title={scheduled ? "Drag to move it to another time" : "Drag onto the calendar to schedule it"}
      className={`group relative flex touch-none select-none items-start gap-2 rounded-lg px-2 py-1.5 transition-colors hover:bg-foreground/[.04] ${
        pending ? "opacity-50" : dragging ? "cursor-grabbing bg-foreground/[.04] opacity-50" : "cursor-grab"
      } ${task.block && !dragging && !pending ? "opacity-60" : ""}`}
    >
      {/* As wide as the goal badge above, so the circle sits centred under it. */}
      <span className="flex w-6 shrink-0 justify-center pt-[3px]">
        <HugeiconsIcon icon={CircleIcon} size={13} className="text-[var(--goal-light)] dark:text-[var(--goal-dark)]" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="line-clamp-2 text-[13px] font-medium leading-snug text-foreground">{task.title}</p>
        <p className="mt-0.5 text-xs tabular-nums text-muted">
          {minutesLabel(task.minutes)}
          {scheduled && <> · {scheduled}</>}
          {planned && (
            <>
              {" · "}
              <span className={missed ? "text-amber-700 dark:text-amber-400" : undefined}>{planned}</span>
            </>
          )}
          {due && (
            <>
              {" · "}
              <span className={overdue ? "text-red-600 dark:text-red-400" : undefined}>{due}</span>
            </>
          )}
        </p>
      </div>
    </li>
  );
}

/** "Today 14:00", "Tomorrow 9:30 AM" or "Thu 14:00", in the viewer's time zone. */
function scheduleLabel(iso: string, today: Date | null, clock: Clock) {
  const at = new Date(iso);
  const time = formatTime(at.getHours() * 60 + at.getMinutes(), clock);
  if (!today) return time;
  const days = Math.round((new Date(at.getFullYear(), at.getMonth(), at.getDate()).getTime() - today.getTime()) / 86_400_000);
  const day = days === 0 ? "Today" : days === 1 ? "Tomorrow" : at.toLocaleDateString(undefined, { weekday: "short" });
  return `${day} ${time}`;
}
