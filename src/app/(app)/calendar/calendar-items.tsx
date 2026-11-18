"use client";

import {
  ArrowRight02Icon,
  ArrowTurnBackwardIcon,
  CircleIcon,
  Tick02Icon,
  Delete02Icon,
  PencilEdit02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import { formatRange } from "@/lib/clock";
import { goalColorStyle } from "@/lib/goal-colors";
import type { BlockView } from "@/lib/block-schema";
import type { Clock } from "@/lib/settings-schema";

import { GUTTER, HOUR, y } from "./geometry";

export type CalendarGoal = { id: string; title: string; icon: string; color: string };

/** Height a block needs for its title and time on two lines, in px. Shorter ones get a single line. */
const TWO_LINES = 48;
const isShort = (start: number, end: number) => ((end - start) / 60) * HOUR < TWO_LINES;

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
  selected = false,
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
  /** Its panel is open. */
  selected?: boolean;
  onPointerDown: (e: React.PointerEvent<HTMLLIElement>) => void;
  onEdit: () => void;
  onTomorrow: () => void;
  /** Only for intentions that schedule a task. */
  onToggleDone?: () => void;
  onRemove: () => void;
}) {
  const intention = Boolean(block.fromSuggestion || block.taskId);
  const kind = intention ? "goal-tint-opaque" : "goal-hatch";
  const title = block.title ?? goal?.title ?? "Protected time";
  const time = formatRange(start, end, clock);
  const what = intention ? (block.taskDone ? "Done" : "Intention") : "Protected time";
  // A recap waiting to be read and posted, or one drafting itself.
  const recapWaiting = !block.recapPost && (block.recap !== null || block.recapDrafting);

  return (
    <li
      style={{ ...goalColorStyle(goal?.color ?? "slate"), ...place(start, end) }}
      onPointerDown={pending ? undefined : onPointerDown}
      aria-label={`${what}: ${title}, ${time}${recapWaiting ? (block.recap ? ", recap to review" : ", drafting recap") : ""}`}
      className={`goal-tint ${kind} group absolute z-10 touch-none select-none overflow-hidden rounded-lg ${
        pending ? "opacity-60" : dragging ? "z-30 cursor-grabbing" : "cursor-grab"
      } ${selected ? "ring-2 ring-[var(--goal)]/60" : ""}`}
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
          ) : undefined
        }
      />
      {recapWaiting && (
        <span
          aria-hidden="true"
          title={block.recap ? "Recap to review" : "Drafting recap"}
          className={`goal-solid absolute right-2.5 top-2.5 h-1.5 w-1.5 rounded-full transition-opacity group-hover:opacity-0 ${
            block.recap ? "" : "animate-pulse"
          }`}
        />
      )}
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
      className="goal-tint goal-task-outline pointer-events-none absolute z-30 overflow-hidden rounded-lg border-dashed! shadow-[0_6px_16px_rgb(15_17_20/0.12)]"
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
