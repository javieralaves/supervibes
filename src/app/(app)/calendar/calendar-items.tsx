"use client";

import {
  Add01Icon,
  ArrowRight02Icon,
  ArrowTurnBackwardIcon,
  CircleIcon,
  Tick02Icon,
  DashedLineCircleIcon,
  Delete02Icon,
  PencilEdit02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { formatRange } from "@/lib/clock";
import { goalColorStyle } from "@/lib/goal-colors";
import type { BlockView } from "@/lib/block-schema";
import type { Clock } from "@/lib/settings-schema";

import { GUTTER, y } from "./geometry";

export type CalendarGoal = { id: string; title: string; icon: string; color: string };

/** Short items get a single line: title and time side by side. */
const isShort = (start: number, end: number) => end - start < 60;

function place(start: number, end: number, inset = 0): React.CSSProperties {
  return {
    top: y(start) + 1,
    height: Math.max(y(end) - y(start) - 2, 14),
    left: `calc(${GUTTER} + ${4 + inset}px)`,
    right: 8 + inset,
  };
}

function Label({
  title,
  time,
  short,
  icon,
  done = false,
}: {
  title: string;
  time: string;
  short: boolean;
  icon?: React.ReactNode;
  /** A finished task: the title is crossed out. */
  done?: boolean;
}) {
  const titleTone = done ? "text-muted line-through decoration-foreground/25" : "text-foreground";
  return short ? (
    <div className="flex h-full items-center gap-2 pl-3 pr-8">
      {icon}
      {/* Too short for a second line, so the time lives in the hover tooltip instead. */}
      <p className={`min-w-0 flex-1 truncate text-[13px] font-medium ${titleTone}`} title={`${title} · ${time}`}>
        {title}
      </p>
    </div>
  ) : (
    <div className="flex h-full flex-col gap-1 py-2 pl-3 pr-8">
      <p className={`flex min-w-0 items-start gap-1.5 text-sm font-medium leading-snug ${titleTone}`}>
        {icon}
        <span className="line-clamp-2">{title}</span>
      </p>
      <p className="text-xs tabular-nums text-muted">{time}</p>
    </div>
  );
}

/** An intention or protected time. Drag to move; click to edit; ⋯ for the rest. */
export function BlockCard({
  block,
  goal,
  start,
  end,
  clock,
  pending,
  dragging,
  onPointerDown,
  onEdit,
  onTomorrow,
  onToggleDone,
  onRemove,
}: {
  block: BlockView;
  goal: CalendarGoal | undefined;
  start: number;
  end: number;
  clock: Clock;
  pending: boolean;
  dragging: boolean;
  onPointerDown: (e: React.PointerEvent<HTMLLIElement>) => void;
  onEdit: () => void;
  onTomorrow: () => void;
  /** Only for intentions that schedule a task. */
  onToggleDone?: () => void;
  onRemove: () => void;
}) {
  const intention = Boolean(block.fromSuggestion || block.taskId);
  const kind = intention ? "goal-tint-opaque" : block.keepOpen ? "goal-open border border-card-border" : "goal-hatch";
  const title = block.title ?? goal?.title ?? "Protected time";
  const time = formatRange(start, end, clock);
  const what = intention ? (block.taskDone ? "Done" : "Intention") : block.keepOpen ? "Time set aside" : "Protected time";

  return (
    <li
      style={{ ...goalColorStyle(goal?.color ?? "slate"), ...place(start, end) }}
      onPointerDown={pending ? undefined : onPointerDown}
      aria-label={`${what}: ${title}, ${time}`}
      className={`goal-tint ${kind} group absolute z-10 touch-none select-none overflow-hidden rounded-lg ${
        pending ? "opacity-60" : dragging ? "z-30 cursor-grabbing" : "cursor-grab"
      }`}
    >
      <span aria-hidden="true" className="goal-solid absolute inset-y-0 left-0 w-[3px]" />
      {!pending && (
        <>
          {/* Drag the top or bottom edge to change the length. */}
          <span aria-hidden="true" data-edge="start" className="absolute inset-x-0 top-0 z-10 h-1.5 cursor-ns-resize" />
          <span aria-hidden="true" data-edge="end" className="absolute inset-x-0 bottom-0 z-10 flex h-2 cursor-ns-resize justify-center">
            <span className="mt-0.5 h-1 w-6 rounded-full bg-foreground/20 opacity-0 transition-opacity group-hover:opacity-100" />
          </span>
        </>
      )}
      <Label
        title={title}
        time={time}
        short={isShort(start, end)}
        done={block.taskDone}
        icon={
          block.taskDone ? (
            <span className="mt-[3px] flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full bg-foreground text-background">
              <HugeiconsIcon icon={Tick02Icon} size={9} strokeWidth={3} />
            </span>
          ) : block.keepOpen ? (
            <HugeiconsIcon icon={DashedLineCircleIcon} size={13} className="mt-[3px] shrink-0 text-[var(--goal)]" />
          ) : undefined
        }
      />
      {!pending && !dragging && (
        <div className="absolute right-1.5 top-1.5 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 has-[[data-state=open]]:opacity-100">
          <MoreMenu label={`Options for ${title}`} small>
            <MoreMenuItem icon={PencilEdit02Icon} onSelect={onEdit}>
              Edit
            </MoreMenuItem>
            {onToggleDone && (
              <MoreMenuItem icon={block.taskDone ? ArrowTurnBackwardIcon : Tick02Icon} onSelect={onToggleDone}>
                {block.taskDone ? "Reopen task" : "Mark done"}
              </MoreMenuItem>
            )}
            <MoreMenuItem icon={ArrowRight02Icon} onSelect={onTomorrow}>
              Move to tomorrow
            </MoreMenuItem>
            <MoreMenuItem icon={Delete02Icon} destructive onSelect={onRemove}>
              Remove
            </MoreMenuItem>
          </MoreMenu>
        </div>
      )}
    </li>
  );
}

/** Where a task dragged from the panel would land: an outline in its goal's colour, with the time. */
export function DropPreview({
  title,
  goal,
  start,
  end,
  clock,
}: {
  title: string;
  goal: CalendarGoal | undefined;
  start: number;
  end: number;
  clock: Clock;
}) {
  return (
    <div
      aria-hidden="true"
      style={{ ...goalColorStyle(goal?.color ?? "slate"), ...place(start, end) }}
      className="goal-tint goal-glimpse-task pointer-events-none absolute z-30 overflow-hidden rounded-lg border-dashed! shadow-[0_6px_16px_rgb(15_17_20/0.12)]"
    >
      {isShort(start, end) ? (
        // Unlike a card, the time stays visible even on one line: it's what you're choosing.
        <div className="flex h-full items-center gap-2 px-3">
          <span className="shrink-0 text-xs font-medium tabular-nums text-foreground">{formatRange(start, end, clock)}</span>
          <span className="min-w-0 truncate text-[13px] text-muted">{title}</span>
        </div>
      ) : (
        <Label
          title={title}
          time={formatRange(start, end, clock)}
          short={false}
          icon={<HugeiconsIcon icon={CircleIcon} size={13} className="mt-[3px] shrink-0 text-[var(--goal)]" />}
        />
      )}
    </div>
  );
}

/**
 * Something Glimpse proposes, with + to commit it to this time. Your own tasks
 * have a thin solid outline and a circle like their checkbox; suggestions are dashed.
 */
export function GlimpseCard({
  kind,
  title,
  goal,
  start,
  end,
  clock,
  inBlock,
  onAdd,
}: {
  kind: "task" | "suggestion";
  title: string;
  goal: CalendarGoal;
  start: number;
  end: number;
  clock: Clock;
  /** Sits inside a protected block, so it's inset to keep the block visible around it. */
  inBlock: boolean;
  onAdd: () => void;
}) {
  const time = formatRange(start, end, clock);
  const task = kind === "task";
  return (
    <li
      style={{ ...goalColorStyle(goal.color), ...place(start, end, inBlock ? 8 : 0) }}
      aria-label={`${task ? "Task" : "Suggestion"}: ${title}, ${time}`}
      className={`goal-tint ${task ? "goal-glimpse-task" : "goal-suggest"} group absolute z-20 overflow-hidden rounded-lg`}
    >
      <Label
        title={title}
        time={time}
        short={isShort(start, end)}
        icon={task ? <HugeiconsIcon icon={CircleIcon} size={13} className="mt-[3px] shrink-0 text-[var(--goal)]" /> : undefined}
      />
      <button
        type="button"
        onClick={onAdd}
        aria-label={`Schedule “${title}” at ${time}`}
        title="Add to your calendar"
        className="absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full border border-card-border bg-card text-foreground/70 opacity-0 shadow-[0_1px_2px_rgb(15_17_20/0.08)] transition-[opacity,color,border-color] hover:border-line-strong hover:text-foreground focus-visible:opacity-100 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-foreground/30 group-hover:opacity-100"
      >
        <HugeiconsIcon icon={Add01Icon} size={14} />
      </button>
    </li>
  );
}
