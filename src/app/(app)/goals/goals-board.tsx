"use client";

import { Add01Icon, ArrowRight01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import Link from "next/link";
import { startTransition, useOptimistic, useState } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { StatusText } from "@/components/status-pill";
import { StatusTrajectory } from "@/components/status-trajectory";
import { DEFAULT_GOAL_COLOR, isGoalColor } from "@/lib/goal-colors";
import { DEFAULT_GOAL_ICON, isGoalIcon } from "@/lib/goal-icons";
import { MAX_GOALS, type GoalInput } from "@/lib/goal-schema";
import type { GoalDTO } from "@/lib/goals";
import { buildTrajectory, type TrajectoryDay } from "@/lib/status-schema";
import { daysUntil, formatTargetDate, shortRelative } from "@/lib/target-date";

import { createGoalAction, deleteGoalAction, updateGoalAction, type GoalActionResult } from "./actions";
import { GoalDialog } from "./goal-dialog";

type Op =
  | { type: "create"; goal: GoalDTO }
  | { type: "update"; goal: GoalDTO }
  | { type: "delete"; id: string };

function applyOp(goals: GoalDTO[], op: Op): GoalDTO[] {
  switch (op.type) {
    case "create":
      return [...goals, op.goal];
    case "update":
      return goals.map((g) => (g.id === op.goal.id ? op.goal : g));
    case "delete":
      return goals.filter((g) => g.id !== op.id);
  }
}

type DialogState =
  | { mode: "closed" }
  | { mode: "create"; initial: GoalInput }
  | { mode: "edit"; goal: GoalDTO };

const BLANK: GoalInput = { title: "", description: null, targetDate: null, icon: DEFAULT_GOAL_ICON, color: DEFAULT_GOAL_COLOR };

const SUGGESTIONS: GoalInput[] = [
  { title: "Turn Supervibes into a world-class experience", icon: "SparklesIcon", color: "violet", description: null, targetDate: null },
  { title: "Create political program as side project", icon: "Megaphone01Icon", color: "coral", description: null, targetDate: null },
];

const PENDING_PREFIX = "pending-";

/** Stored values are plain strings; fall back to defaults if one is no longer in the set. */
function toInput(goal: GoalDTO): GoalInput {
  return {
    title: goal.title,
    description: goal.description,
    targetDate: goal.targetDate,
    icon: isGoalIcon(goal.icon) ? goal.icon : DEFAULT_GOAL_ICON,
    color: isGoalColor(goal.color) ? goal.color : DEFAULT_GOAL_COLOR,
  };
}

export function GoalsBoard({
  goals,
  trajectories = {},
  today,
}: {
  goals: GoalDTO[];
  /** Each goal's status day by day over the last few weeks, by goal id. */
  trajectories?: Record<string, { days: TrajectoryDay[]; reads: number }>;
  /** The person's today, "YYYY-MM-DD". */
  today: string;
}) {
  const [optimisticGoals, apply] = useOptimistic(goals, applyOp);
  const [dialog, setDialog] = useState<DialogState>({ mode: "closed" });
  const [dialogKey, setDialogKey] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const atLimit = optimisticGoals.length >= MAX_GOALS;

  function openDialog(next: Exclude<DialogState, { mode: "closed" }>) {
    setError(null);
    setDialogKey((k) => k + 1); // fresh form state every time it opens
    setDialog(next);
  }

  function run(op: Op, action: () => Promise<GoalActionResult>) {
    setDialog({ mode: "closed" });
    setError(null);
    startTransition(async () => {
      apply(op);
      const result = await action();
      if (!result.ok) setError(result.error);
    });
  }

  function save(input: GoalInput) {
    if (dialog.mode === "edit") {
      const { goal } = dialog;
      run({ type: "update", goal: { ...goal, ...input } }, () => updateGoalAction(goal.id, input));
    } else {
      const goal: GoalDTO = { id: `${PENDING_PREFIX}${Date.now()}`, position: Infinity, ...input };
      run({ type: "create", goal }, () => createGoalAction(input));
    }
  }

  function remove() {
    if (dialog.mode !== "edit") return;
    const { goal } = dialog;
    run({ type: "delete", id: goal.id }, () => deleteGoalAction(goal.id));
  }

  return (
    <section aria-labelledby="goals-heading">
      <div className="mb-4 flex items-baseline justify-between">
        <h2 id="goals-heading" className="text-lg font-semibold tracking-[-0.02em] text-foreground">
          Goals
        </h2>
        {optimisticGoals.length > 0 && (
          <p className="text-xs tabular-nums text-muted">
            {optimisticGoals.length} of {MAX_GOALS}
          </p>
        )}
      </div>

      {error && (
        <p
          role="alert"
          className="mb-4 rounded-xl border border-red-500/20 bg-red-500/[.07] px-4 py-3 text-sm text-red-700 dark:text-red-300"
        >
          {error}
        </p>
      )}

      {optimisticGoals.length === 0 ? (
        <EmptyState
          onCreate={(initial) => openDialog({ mode: "create", initial })}
        />
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {optimisticGoals.map((goal) => {
            const pending = goal.id.startsWith(PENDING_PREFIX);
            // Two parts: who it is at the top, how it's going pinned to the bottom, so footers line up across a row.
            const cardClass =
              "group relative flex h-full w-full flex-col rounded-2xl border border-card-border bg-card p-5 text-left transition-colors hover:border-line-strong focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30";
            const trajectory = trajectories[goal.id];
            // Its latest status: the last day's, which carries the most recent read.
            const latest = trajectory?.days.at(-1);
            const days = goal.targetDate ? daysUntil(goal.targetDate, today) : null;
            const content = (
              <>
                {/* Who it is: the icon on the title's first line. */}
                <span className="flex items-start gap-2.5 pr-5">
                  <GoalBadge icon={goal.icon} color={goal.color} size="xs" />
                  <span className="line-clamp-2 min-w-0 text-[0.95rem] font-semibold leading-snug tracking-[-0.01em] text-foreground [overflow-wrap:anywhere]">
                    {goal.title}
                  </span>
                </span>
                <span
                  aria-hidden="true"
                  className="absolute right-4 top-5 text-muted opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100 [@media(hover:none)]:opacity-60"
                >
                  <HugeiconsIcon icon={ArrowRight01Icon} size={16} />
                </span>

                {/* How it's going: status and target date, then the last weeks, edge to edge. */}
                <span className="mt-auto block pt-5">
                  <span className="flex items-baseline justify-between gap-3 text-xs">
                    {latest?.status && latest.basis ? (
                      <StatusText status={latest.status} basis={latest.basis} />
                    ) : (
                      <span className="text-muted">No status yet</span>
                    )}
                    {goal.targetDate && days !== null && (
                      <span
                        suppressHydrationWarning
                        title={`Target ${formatTargetDate(goal.targetDate, today)}`}
                        className={`shrink-0 tabular-nums ${days < 0 ? "text-amber-700 dark:text-amber-400" : "text-muted"}`}
                      >
                        {formatTargetDate(goal.targetDate, today)} · {shortRelative(days)}
                      </span>
                    )}
                  </span>
                  <StatusTrajectory
                    days={trajectory?.days ?? buildTrajectory([], null, today)}
                    today={today}
                    size="mini"
                    className="mt-2"
                  />
                </span>
              </>
            );
            return (
              <li key={goal.id}>
                {pending ? (
                  <div aria-busy="true" className={`${cardClass} pointer-events-none opacity-60`}>
                    {content}
                  </div>
                ) : (
                  <Link href={`/goals/${goal.id}`} className={cardClass}>
                    {content}
                  </Link>
                )}
              </li>
            );
          })}

          {!atLimit && (
            <li>
              <button
                type="button"
                onClick={() => openDialog({ mode: "create", initial: BLANK })}
                className="flex h-full min-h-[84px] w-full items-center justify-center gap-2 rounded-2xl border border-dashed border-foreground/15 text-sm font-medium text-muted transition-colors hover:border-foreground/30 hover:bg-card hover:text-foreground focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30"
              >
                <HugeiconsIcon icon={Add01Icon} size={18} />
                New goal
              </button>
            </li>
          )}
        </ul>
      )}

      {dialog.mode !== "closed" && (
        <GoalDialog
          key={dialogKey}
          open
          onOpenChange={(open) => !open && setDialog({ mode: "closed" })}
          mode={dialog.mode}
          initial={dialog.mode === "edit" ? toInput(dialog.goal) : dialog.initial}
          onSave={save}
          onDelete={dialog.mode === "edit" ? remove : undefined}
        />
      )}
    </section>
  );
}

function EmptyState({ onCreate }: { onCreate: (initial: GoalInput) => void }) {
  return (
    <div className="rounded-2xl border border-card-border bg-card p-6 sm:p-8">
      <h3 className="text-xl font-semibold tracking-[-0.02em] text-foreground">
        What are you working toward?
      </h3>
      <p className="mt-1.5 max-w-md text-sm leading-relaxed text-muted">
        Add a handful of goals, each with its own icon and color. Start from scratch or pick one below.
      </p>

      <div className="mt-6 flex flex-col gap-2">
        {SUGGESTIONS.map((s) => (
          <button
            key={s.title}
            type="button"
            onClick={() => onCreate(s)}
            className="flex items-center gap-3 rounded-2xl border border-card-border bg-background/60 p-3 pr-4 text-left text-sm font-medium text-foreground transition-colors hover:bg-background focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground/30"
          >
            <GoalBadge icon={s.icon} color={s.color} />
            <span className="min-w-0 flex-1">{s.title}</span>
            <HugeiconsIcon icon={Add01Icon} size={16} className="text-muted" />
          </button>
        ))}
      </div>

      <button
        type="button"
        onClick={() => onCreate(BLANK)}
        className="mt-6 inline-flex h-10 items-center gap-2 rounded-xl bg-foreground px-4 text-sm font-semibold text-background transition-opacity hover:opacity-90"
      >
        <HugeiconsIcon icon={Add01Icon} size={16} />
        New goal
      </button>
    </div>
  );
}
