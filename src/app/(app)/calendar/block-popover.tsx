"use client";

import { DashedLineCircleIcon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { useEffect, useId, useRef, useState } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { MAX_BLOCK_TITLE, type BlockDetails } from "@/lib/block-schema";

import type { CalendarGoal } from "./calendar-items";
import { GUTTER } from "./geometry";

/** Roughly how tall the popover is, to decide whether it opens above or below. */
const EST_HEIGHT = 300;

/**
 * Sits next to a block on the timeline to name it, pick its goal and choose
 * whether to keep it open. Enter saves; Esc or a click elsewhere cancels.
 */
export function BlockPopover({
  anchorTop,
  anchorBottom,
  timelineHeight,
  goals,
  initial,
  intention,
  timeLabel,
  onSave,
  onCancel,
}: {
  anchorTop: number;
  anchorBottom: number;
  timelineHeight: number;
  goals: CalendarGoal[];
  initial: BlockDetails;
  /** Intentions are a task already; they can't be kept open. */
  intention: boolean;
  timeLabel: string;
  onSave: (details: BlockDetails) => void;
  onCancel: () => void;
}) {
  const [title, setTitle] = useState(initial.title ?? "");
  const [goalId, setGoalId] = useState(initial.goalId);
  const [keepOpen, setKeepOpen] = useState(initial.keepOpen);
  const ref = useRef<HTMLFormElement>(null);
  const titleId = useId();
  const switchId = useId();

  // Bring it into view, and close it on a press anywhere else.
  useEffect(() => {
    ref.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onCancel();
    }
    document.addEventListener("pointerdown", onDown, true);
    return () => document.removeEventListener("pointerdown", onDown, true);
  }, [onCancel]);

  const above = anchorBottom + 8 + EST_HEIGHT > timelineHeight;
  const goal = goals.find((g) => g.id === goalId);

  return (
    <form
      ref={ref}
      data-calendar-popover
      onSubmit={(e) => {
        e.preventDefault();
        if (goalId) onSave({ goalId, title: title.trim() || null, keepOpen: intention ? false : keepOpen });
      }}
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          e.preventDefault();
          onCancel();
        }
      }}
      onPointerDown={(e) => e.stopPropagation()}
      style={{
        left: `calc(${GUTTER} + 12px)`,
        ...(above ? { bottom: timelineHeight - anchorTop + 8 } : { top: anchorBottom + 8 }),
      }}
      className="absolute z-40 w-[min(340px,calc(100%-5.5rem))] rounded-2xl border border-card-border bg-card p-4 shadow-[0_16px_40px_-12px_rgb(15_17_20/0.3)] animate-[pop-in_140ms_ease-out]"
    >
      <p className="text-xs font-medium tabular-nums text-muted">{timeLabel}</p>

      <label htmlFor={titleId} className="sr-only">
        Title
      </label>
      <input
        id={titleId}
        autoFocus
        value={title}
        maxLength={MAX_BLOCK_TITLE}
        onChange={(e) => setTitle(e.target.value)}
        placeholder={intention ? "What you'll do" : "What's this time for? (optional)"}
        className="mt-1.5 block w-full bg-transparent text-[0.95rem] font-medium text-foreground outline-none placeholder:font-normal placeholder:text-muted/80"
      />

      <div className="mt-4">
        <p className="text-xs font-medium text-muted">
          Goal{goal ? <span className="text-foreground"> · {goal.title}</span> : null}
        </p>
        {goals.length === 0 ? (
          <p className="mt-2 text-sm text-muted">Add a goal first.</p>
        ) : (
          <div role="radiogroup" aria-label="Goal" className="mt-2 flex flex-wrap gap-2">
            {goals.map((g) => (
              <button
                key={g.id}
                type="button"
                role="radio"
                aria-checked={g.id === goalId}
                aria-label={g.title}
                title={g.title}
                onClick={() => setGoalId(g.id)}
                className={`rounded-xl transition-shadow focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 ${
                  g.id === goalId ? "ring-2 ring-foreground/70 ring-offset-2 ring-offset-card" : "opacity-70 hover:opacity-100"
                }`}
              >
                <GoalBadge icon={g.icon} color={g.color} />
              </button>
            ))}
          </div>
        )}
      </div>

      {!intention && (
        <div className="mt-4 flex items-start justify-between gap-4 border-t border-card-border pt-4">
          <label htmlFor={switchId} className="min-w-0">
            <span className="flex items-center gap-1.5 text-sm font-medium text-foreground">
              <HugeiconsIcon icon={DashedLineCircleIcon} size={14} className="text-muted" />
              Keep it open
            </span>
            <span className="mt-0.5 block text-xs text-muted">No suggestions will be placed here.</span>
          </label>
          <button
            id={switchId}
            type="button"
            role="switch"
            aria-checked={keepOpen}
            onClick={() => setKeepOpen((v) => !v)}
            className={`relative mt-0.5 h-5 w-9 shrink-0 rounded-full transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 ${
              keepOpen ? "bg-foreground" : "bg-foreground/15"
            }`}
          >
            <span
              className={`absolute top-0.5 h-4 w-4 rounded-full bg-card shadow-sm transition-[left] ${keepOpen ? "left-[18px]" : "left-0.5"}`}
            />
          </button>
        </div>
      )}

      <div className="mt-4 flex items-center justify-end gap-1.5">
        <button
          type="button"
          onClick={onCancel}
          className="h-8 rounded-lg px-3 text-sm font-medium text-muted hover:bg-wash hover:text-foreground"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={!goalId}
          className="h-8 rounded-lg bg-foreground px-3 text-sm font-semibold text-background hover:opacity-90 disabled:opacity-30"
        >
          Save
        </button>
      </div>
    </form>
  );
}
