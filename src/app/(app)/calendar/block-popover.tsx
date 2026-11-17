"use client";

import { ArrowLeft01Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import { useEffect, useId, useRef, useState } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { MAX_BLOCK_TITLE, type BlockDetails } from "@/lib/block-schema";

import type { CalendarGoal } from "./calendar-items";
import { GUTTER } from "./geometry";

/** Roughly how tall the popover is, to decide whether it opens above or below. */
const EST_HEIGHT = 200;

/**
 * Sits next to a block on the timeline to name it and pick its goal. The goal icon beside the title switches the popover
 * to a goal list in place. Enter saves; Esc steps back or cancels; a click
 * elsewhere cancels.
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
  /** Intentions are a task already: the title reads as what you'll do. */
  intention: boolean;
  timeLabel: string;
  onSave: (details: BlockDetails) => void;
  onCancel: () => void;
}) {
  const [title, setTitle] = useState(initial.title ?? "");
  const [goalId, setGoalId] = useState(initial.goalId);
  const [view, setView] = useState<"main" | "goals">("main");
  const ref = useRef<HTMLFormElement>(null);
  const goalButton = useRef<HTMLButtonElement>(null);
  const titleInput = useRef<HTMLInputElement>(null);
  const titleId = useId();

  // Bring it into view, and close it on a press anywhere else.
  useEffect(() => {
    ref.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    function onDown(e: PointerEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onCancel();
    }
    document.addEventListener("pointerdown", onDown, true);
    return () => document.removeEventListener("pointerdown", onDown, true);
  }, [onCancel]);

  function backToMain(focus: "goal" | "title" = "goal") {
    setView("main");
    requestAnimationFrame(() => (focus === "goal" ? goalButton.current : titleInput.current)?.focus());
  }

  const above = anchorBottom + 8 + EST_HEIGHT > timelineHeight;
  const goal = goals.find((g) => g.id === goalId);

  return (
    <form
      ref={ref}
      data-calendar-popover
      onSubmit={(e) => {
        e.preventDefault();
        if (goalId) onSave({ goalId, title: title.trim() || null });
      }}
      onKeyDown={(e) => {
        if (e.key !== "Escape") return;
        e.preventDefault();
        if (view === "goals") backToMain();
        else onCancel();
      }}
      onPointerDown={(e) => e.stopPropagation()}
      style={{
        left: `calc(${GUTTER} + 12px)`,
        ...(above ? { bottom: timelineHeight - anchorTop + 8 } : { top: anchorBottom + 8 }),
      }}
      className="absolute z-40 w-[min(320px,calc(100%-5.5rem))] rounded-2xl border border-card-border bg-card p-1.5 shadow-[0_1px_2px_rgb(15_17_20/0.04),0_12px_32px_-8px_rgb(15_17_20/0.18)] animate-[pop-in_140ms_ease-out]"
    >
      {view === "goals" ? (
        <div className="animate-[fade-in_120ms_ease-out]">
          <div className="flex items-center gap-1 px-1 pb-1 pt-0.5">
            <button
              type="button"
              autoFocus
              onClick={() => backToMain()}
              aria-label="Back"
              className="flex h-8 w-8 items-center justify-center rounded-lg text-muted transition-colors hover:bg-wash hover:text-foreground focus-visible:outline-2 focus-visible:outline-foreground/30"
            >
              <HugeiconsIcon icon={ArrowLeft01Icon} size={16} />
            </button>
            <p className="text-sm font-semibold text-foreground">Goal</p>
          </div>
          <div role="radiogroup" aria-label="Goal" className="max-h-64 overflow-y-auto">
            {goals.map((g) => (
              <button
                key={g.id}
                type="button"
                role="radio"
                aria-checked={g.id === goalId}
                onClick={() => {
                  setGoalId(g.id);
                  backToMain("title");
                }}
                className="flex w-full items-center gap-2.5 rounded-lg px-2.5 py-2 text-left text-sm text-foreground outline-none transition-colors hover:bg-wash focus-visible:bg-wash"
              >
                <GoalBadge icon={g.icon} color={g.color} size="xs" />
                <span className="min-w-0 flex-1 leading-snug [text-wrap:pretty]">{g.title}</span>
                {g.id === goalId && <HugeiconsIcon icon={Tick02Icon} size={15} className="shrink-0 text-muted" />}
              </button>
            ))}
          </div>
        </div>
      ) : (
        <div className="animate-[fade-in_120ms_ease-out]">
          <div className="flex items-center gap-3 px-2.5 pb-2.5 pt-2.5">
            {goal ? (
              <button
                ref={goalButton}
                type="button"
                onClick={() => setView("goals")}
                aria-label={`Goal: ${goal.title}. Change goal`}
                title={goal.title}
                className="shrink-0 rounded-lg transition-[box-shadow,transform] hover:ring-2 hover:ring-foreground/10 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30 active:scale-95"
              >
                <GoalBadge icon={goal.icon} color={goal.color} size="field" />
              </button>
            ) : (
              <span className="text-sm text-muted">Add a goal first.</span>
            )}
            <div className="min-w-0 flex-1">
              <p className="text-xs tabular-nums text-muted">{timeLabel}</p>
              <label htmlFor={titleId} className="sr-only">
                Title
              </label>
              <input
                id={titleId}
                ref={titleInput}
                autoFocus
                value={title}
                maxLength={MAX_BLOCK_TITLE}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={intention ? "What you'll do" : "Add a title"}
                className="block w-full bg-transparent text-base font-semibold tracking-[-0.01em] text-foreground outline-none placeholder:font-medium placeholder:text-muted/70"
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-1 px-1.5 pb-1 pt-2">
            <button
              type="button"
              onClick={onCancel}
              className="h-8 rounded-lg px-3 text-sm font-medium text-muted transition-colors hover:bg-wash hover:text-foreground"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!goalId}
              className="h-8 rounded-lg bg-foreground px-3.5 text-sm font-semibold text-background transition-opacity hover:opacity-90 disabled:opacity-30"
            >
              Save
            </button>
          </div>
        </div>
      )}
    </form>
  );
}
