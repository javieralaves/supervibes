"use client";

import { Cancel01Icon, CircleIcon, PencilEdit02Icon, Refresh01Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { useState, useTransition } from "react";

import { GoalBadge } from "@/components/goal-badge";
import type { BlockAgenda, BlockView } from "@/lib/block-schema";
import { goalColorStyle } from "@/lib/goal-colors";
import { minutesLabel } from "@/lib/task-schema";

import { setTaskDoneAction } from "../goals/[id]/actions";
import { prepareAgendaAction } from "./actions";
import type { CalendarGoal } from "./calendar-items";

/**
 * The block you clicked, beside the calendar on the right. Protected time can
 * get an agenda: a short plan for the session from the goal's tasks, notes and
 * latest read, with the tasks it draws on listed below as context. An intention
 * shows the task it schedules.
 */
export function BlockPanel({
  block,
  goal,
  timeLabel,
  when,
  openTaskIds,
  onEdit,
  onClose,
  onToggleDone,
}: {
  block: BlockView;
  goal: CalendarGoal | undefined;
  /** Shown under the title, e.g. "Wednesday · 9:00–11:00 AM". */
  timeLabel: string;
  /** How the block reads in the viewer's time zone, for the agenda. */
  when: string;
  /** Open tasks across goals; a related task that isn't open anymore shows as done. */
  openTaskIds: Set<string>;
  onEdit: () => void;
  onClose: () => void;
  /** Only for intentions that schedule a task. */
  onToggleDone?: () => void;
}) {
  const intention = Boolean(block.fromSuggestion || block.taskId);
  const kind = intention ? (block.taskDone ? "Done" : "Intention") : block.keepOpen ? "Time set aside" : "Protected time";
  const title = block.title ?? goal?.title ?? "Protected time";

  return (
    <aside
      data-block-panel
      aria-label={`${kind}: ${title}`}
      style={goalColorStyle(goal?.color ?? "slate")}
      className="hidden w-80 shrink-0 flex-col overflow-hidden rounded-2xl border border-card-border bg-card lg:flex"
    >
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-5 pt-3">
        {/* What kind of time this is, with its goal's icon; then the title; then when. */}
        <div className="flex items-center gap-2">
          {goal && (
            <span title={goal.title} aria-label={`Goal: ${goal.title}`} className="flex shrink-0">
              <GoalBadge icon={goal.icon} color={goal.color} size="xs" />
            </span>
          )}
          <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-muted">{kind}</span>
          <PanelButton label="Edit block" icon={PencilEdit02Icon} onClick={onEdit} />
          <PanelButton label="Close" icon={Cancel01Icon} onClick={onClose} />
        </div>

        <h2 className="mt-3 text-[17px] font-semibold leading-snug tracking-[-0.01em] text-foreground [text-wrap:pretty]">{title}</h2>
        <p className="mt-1 text-sm tabular-nums text-muted">{timeLabel}</p>

        {intention ? (
          onToggleDone && (
            <button
              type="button"
              onClick={onToggleDone}
              className="mt-6 flex h-9 w-full items-center justify-center gap-2 rounded-lg border border-card-border bg-card px-3 text-sm font-medium text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] transition-colors hover:border-line-strong"
            >
              <HugeiconsIcon icon={block.taskDone ? Refresh01Icon : Tick02Icon} size={15} />
              {block.taskDone ? "Reopen task" : "Mark done"}
            </button>
          )
        ) : (
          <Agenda key={block.id} blockId={block.id} saved={block.agenda} when={when} openTaskIds={openTaskIds} />
        )}
      </div>
    </aside>
  );
}

function Agenda({
  blockId,
  saved,
  when,
  openTaskIds,
}: {
  blockId: string;
  saved: BlockAgenda | null;
  when: string;
  openTaskIds: Set<string>;
}) {
  const [fresh, setFresh] = useState<BlockAgenda | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [preparing, startPreparing] = useTransition();
  const [, startToggling] = useTransition();
  // Tasks checked off or reopened here, until the calendar catches up.
  const [toggled, setToggled] = useState<Map<string, boolean>>(new Map());

  // Whichever is newer: what's saved on the block, or what was just prepared here.
  const agenda = fresh && (!saved || fresh.preparedAt > saved.preparedAt) ? fresh : saved;

  function prepare() {
    setError(null);
    startPreparing(async () => {
      const result = await prepareAgendaAction(blockId, when);
      if (result.ok) setFresh(result.agenda);
      else setError(result.error);
    });
  }

  function toggleTask(taskId: string, done: boolean) {
    setToggled((m) => new Map(m).set(taskId, done));
    startToggling(async () => {
      const result = await setTaskDoneAction(taskId, done);
      if (!result.ok) {
        setError(result.error);
        setToggled((m) => {
          const next = new Map(m);
          next.delete(taskId);
          return next;
        });
      }
    });
  }

  return (
    <>
      <section aria-label="Agenda" className="mt-6">
        {agenda && (
          <div className="flex items-baseline gap-2">
            <h3 className="text-[13px] font-semibold text-foreground">Agenda</h3>
            {!preparing && (
              <span className="text-xs text-muted" suppressHydrationWarning>
                {preparedLabel(agenda.preparedAt)}
              </span>
            )}
          </div>
        )}

        {preparing && !agenda ? (
          <div aria-label="Preparing agenda" className="space-y-2">
            {["w-full", "w-[92%]", "w-full", "w-3/5"].map((w, i) => (
              <div key={i} className={`h-3 animate-pulse rounded bg-foreground/[.07] ${w}`} />
            ))}
          </div>
        ) : (
          agenda && (
            <p className={`mt-1.5 text-sm leading-relaxed text-foreground/90 [text-wrap:pretty] ${preparing ? "opacity-50" : ""}`}>
              {agenda.text}
            </p>
          )
        )}

        {error && (
          <p role="alert" className="my-2 text-sm text-red-600 dark:text-red-400">
            {error}
          </p>
        )}

        {agenda ? (
          <button
            type="button"
            onClick={prepare}
            disabled={preparing}
            className="mt-3 flex h-7 items-center gap-1.5 rounded-lg px-2 -ml-2 text-xs font-medium text-muted transition-colors hover:bg-wash hover:text-foreground disabled:opacity-60"
          >
            <HugeiconsIcon icon={Refresh01Icon} size={13} className={preparing ? "animate-spin" : undefined} />
            {preparing ? "Preparing…" : "Prepare again"}
          </button>
        ) : (
          <button
            type="button"
            onClick={prepare}
            disabled={preparing}
            title="A short plan for this session, from the goal's tasks, notes and latest read"
            className={`flex h-9 w-full items-center justify-center rounded-lg bg-foreground px-3 text-sm font-semibold text-background transition-opacity hover:opacity-90 disabled:opacity-60 ${
              preparing ? "mt-4" : ""
            }`}
          >
            {preparing ? "Preparing…" : "Prepare agenda"}
          </button>
        )}
      </section>

      {agenda && agenda.tasks.length > 0 && (
        <section aria-label="Related tasks" className="mt-6">
          <h3 className="text-[13px] font-semibold text-foreground">Related tasks</h3>
          <ul className="mt-1.5 -mx-2">
            {agenda.tasks.map((task) => {
              const done = toggled.get(task.id) ?? !openTaskIds.has(task.id);
              return (
                <li key={task.id} className="flex items-start gap-2 rounded-lg px-2 py-1.5">
                  <button
                    type="button"
                    role="checkbox"
                    aria-checked={done}
                    aria-label={`${done ? "Reopen" : "Check off"} “${task.title}”`}
                    onClick={() => toggleTask(task.id, !done)}
                    className="mt-[2px] flex h-4 w-4 shrink-0 items-center justify-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30"
                  >
                    {done ? (
                      <span className="flex h-4 w-4 items-center justify-center rounded-full bg-foreground text-background">
                        <HugeiconsIcon icon={Tick02Icon} size={10} strokeWidth={3} />
                      </span>
                    ) : (
                      <HugeiconsIcon icon={CircleIcon} size={15} className="text-[var(--goal-light)] dark:text-[var(--goal-dark)]" />
                    )}
                  </button>
                  <div className="min-w-0 flex-1">
                    <p
                      className={`text-[13px] font-medium leading-snug [text-wrap:pretty] ${
                        done ? "text-muted line-through decoration-foreground/25" : "text-foreground"
                      }`}
                    >
                      {task.title}
                    </p>
                    <p className="mt-0.5 text-xs tabular-nums text-muted">{minutesLabel(task.minutes)}</p>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      )}
    </>
  );
}

function PanelButton({
  label,
  icon,
  onClick,
}: {
  label: string;
  icon: typeof Cancel01Icon;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg text-muted transition-colors hover:bg-wash hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30"
    >
      <HugeiconsIcon icon={icon} size={15} />
    </button>
  );
}

/** "Prepared just now", "Prepared 5 min ago", "Prepared 3 hr ago", or the date. */
function preparedLabel(iso: string) {
  const minutes = Math.round((Date.now() - Date.parse(iso)) / 60_000);
  if (minutes < 1) return "Prepared just now";
  if (minutes < 60) return `Prepared ${minutes} min ago`;
  if (minutes < 24 * 60) return `Prepared ${Math.round(minutes / 60)} hr ago`;
  return `Prepared ${new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
}
