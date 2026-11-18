"use client";

import { Calendar03Icon, Flag02Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { useRef } from "react";

import { addDays, daysUntil, formatTargetDate, relativeDayLabel, weekdayName } from "@/lib/target-date";

/*
 * A pill for one of a task's days, opening a menu of the next week's days, any
 * other day, and Clear:
 * - "plan": the day the person means to do it, without a time.
 * - "due": the day it has to be done by.
 * Days are "YYYY-MM-DD" in the person's own calendar; `today` is theirs too.
 */

type Kind = "plan" | "due";

const KIND: Record<Kind, { icon: typeof Calendar03Icon; empty: string; menu: string; clear: string }> = {
  plan: { icon: Calendar03Icon, empty: "Plan", menu: "Plan for", clear: "Clear plan" },
  due: { icon: Flag02Icon, empty: "Due", menu: "Due on", clear: "Clear due date" },
};

/** Same shape as the estimate pill beside it. */
const PILL =
  "inline-flex w-fit items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium tabular-nums transition-colors focus-visible:outline-2 focus-visible:outline-foreground/30";

const ITEM =
  "flex h-8 cursor-default select-none items-center justify-between gap-3 rounded-lg px-2.5 text-sm text-foreground outline-none data-[highlighted]:bg-wash";

/** What the pill says, and how loudly. */
function describe(kind: Kind, day: string, today: string) {
  const days = daysUntil(day, today);
  const label = relativeDayLabel(day, today);
  if (kind === "plan") {
    return {
      text: label,
      // A planned day that's gone by without the task getting done.
      tone: days < 0 ? "text-amber-700 dark:text-amber-400" : "text-muted",
      aria: `Planned for ${days < 0 ? `${label}, which has passed` : label}`,
    };
  }
  return {
    text: days < 0 ? `Overdue · ${label}` : `Due ${label === "Today" || label === "Tomorrow" ? label.toLowerCase() : label}`,
    tone:
      days < 0
        ? "text-red-600 dark:text-red-400"
        : days <= 1
          ? "text-foreground"
          : "text-muted",
    aria: days < 0 ? `Overdue, due ${label}` : `Due ${label}`,
  };
}

export function DayPill({
  kind,
  value,
  today,
  onChange,
  disabled = false,
  className = "",
}: {
  kind: Kind;
  value: string | null;
  /** The person's today, "YYYY-MM-DD". */
  today: string;
  onChange: (day: string | null) => void;
  disabled?: boolean;
  /** Extra classes on the pill, e.g. to hide an empty one until hover. */
  className?: string;
}) {
  const picker = useRef<HTMLInputElement>(null);
  const { icon, empty, menu, clear } = KIND[kind];
  const shown = value ? describe(kind, value, today) : null;
  const week = Array.from({ length: 7 }, (_, i) => addDays(today, i));

  function pickOther() {
    const input = picker.current;
    if (!input) return;
    input.value = value ?? "";
    // After the menu has closed and given focus back.
    setTimeout(() => {
      try {
        input.showPicker();
      } catch {
        input.focus();
      }
    }, 0);
  }

  const pillClass = `${PILL} ${
    shown ? `border-card-border bg-card ${shown.tone}` : "border-dashed border-card-border text-muted"
  } hover:border-line-strong hover:text-foreground data-[state=open]:border-line-strong data-[state=open]:text-foreground ${className}`;

  if (disabled) {
    return shown ? (
      <span className={pillClass}>
        <HugeiconsIcon icon={icon} size={12} />
        {shown.text}
      </span>
    ) : null;
  }

  return (
    <>
      <DropdownMenu.Root>
        <DropdownMenu.Trigger aria-label={shown ? `${shown.aria}. Change` : kind === "plan" ? "Plan for a day" : "Set a due date"} className={pillClass}>
          <HugeiconsIcon icon={icon} size={12} />
          {shown ? shown.text : empty}
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content
            align="start"
            sideOffset={6}
            collisionPadding={12}
            className="z-50 w-52 rounded-xl border border-card-border bg-card p-1 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)] outline-none data-[state=open]:animate-[pop-in_120ms_ease-out]"
          >
            <DropdownMenu.Label className="px-2.5 pb-1 pt-1.5 text-xs font-medium text-muted">{menu}</DropdownMenu.Label>
            {week.map((day, i) => (
              <DropdownMenu.Item key={day} onSelect={() => onChange(day)} className={ITEM}>
                <span>{i === 0 ? "Today" : i === 1 ? "Tomorrow" : weekdayName(day, "long")}</span>
                <span className="flex items-center gap-1.5 text-xs tabular-nums text-muted">
                  {formatTargetDate(day, today)}
                  {day === value && <HugeiconsIcon icon={Tick02Icon} size={13} />}
                </span>
              </DropdownMenu.Item>
            ))}
            <DropdownMenu.Separator className="mx-1 my-1 h-px bg-card-border" />
            <DropdownMenu.Item onSelect={pickOther} className={ITEM}>
              <span>Another day…</span>
              {value && !week.includes(value) && (
                <span className="flex items-center gap-1.5 text-xs tabular-nums text-muted">
                  {formatTargetDate(value, today)}
                  <HugeiconsIcon icon={Tick02Icon} size={13} />
                </span>
              )}
            </DropdownMenu.Item>
            {value && (
              <DropdownMenu.Item
                onSelect={() => onChange(null)}
                className={`${ITEM} text-red-600 dark:text-red-400`}
              >
                {clear}
              </DropdownMenu.Item>
            )}
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
      {/* The browser's own date picker, for days beyond the next week. */}
      <input
        ref={picker}
        type="date"
        tabIndex={-1}
        aria-hidden="true"
        onChange={(e) => {
          if (e.target.value) onChange(e.target.value);
        }}
        className="pointer-events-none absolute h-0 w-0 opacity-0"
      />
    </>
  );
}
