"use client";

import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";

import { goalColorStyle } from "@/lib/goal-colors";

/*
 * The top of a calendar side panel (Tasks beside a day, This week beside a week):
 * an icon tile matching the panel's toggle, the title and a quiet note, then a
 * summary, often a figure and a bar split by goal. Set apart from the list below
 * by a soft wash and a rule, and it stays put while the list scrolls.
 */
export function PanelHeader({
  icon,
  title,
  note,
  children,
}: {
  icon: IconSvgElement;
  title: string;
  /** A short note on the right, e.g. the week's dates. */
  note?: string;
  /** The summary under the title. */
  children?: React.ReactNode;
}) {
  return (
    <div className="shrink-0 border-b border-card-border bg-[radial-gradient(130%_90%_at_0%_0%,color-mix(in_oklab,var(--foreground)_5%,transparent),transparent_70%)] px-4 pb-4 pt-4">
      <div className="flex items-center gap-2.5">
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[10px] border border-card-border bg-background text-foreground/75 shadow-[0_1px_2px_rgb(15_17_20/0.06)]">
          <HugeiconsIcon icon={icon} size={16} />
        </span>
        <h2 className="min-w-0 flex-1 truncate text-[15px] font-semibold tracking-[-0.01em] text-foreground">{title}</h2>
        {note && <span className="shrink-0 text-xs tabular-nums text-muted">{note}</span>}
      </div>
      {children && <div className="mt-4">{children}</div>}
    </div>
  );
}

/** A big figure with a quiet label beside it, e.g. "5h 32m done of 9h 45m". */
export function PanelFigure({ value, label }: { value: string; label: string }) {
  return (
    <p className="flex items-baseline gap-1.5">
      <span className="text-[22px] font-semibold leading-none tracking-[-0.02em] text-foreground tabular-nums">{value}</span>
      <span className="text-xs text-muted">{label}</span>
    </p>
  );
}

/**
 * One bar split by goal: each goal's part is as wide as its share of the whole, in
 * its colour, light where it's still to come and solid for the part that's `filled`.
 */
export function GoalSplitBar({
  parts,
  label,
}: {
  parts: { goalId: string; color: string; value: number; filled: number }[];
  /** What the bar shows, read aloud. */
  label: string;
}) {
  const shown = parts.filter((p) => p.value > 0);
  return (
    <div role="img" aria-label={label} className="mt-3 flex h-2 gap-[3px]">
      {shown.length === 0 ? (
        <span className="h-full flex-1 rounded-full bg-foreground/[.06]" />
      ) : (
        shown.map((p) => (
          <span
            key={p.goalId}
            style={{ ...goalColorStyle(p.color), flexGrow: p.value, flexBasis: 0 }}
            className="goal-track relative h-full min-w-1.5 overflow-hidden rounded-full"
          >
            <span
              className="goal-solid absolute inset-y-0 left-0"
              style={{ width: `${Math.min(1, p.filled / p.value) * 100}%` }}
            />
          </span>
        ))
      )}
    </div>
  );
}
