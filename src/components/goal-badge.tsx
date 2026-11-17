"use client";

import { HugeiconsIcon } from "@hugeicons/react";

import { goalColorStyle } from "@/lib/goal-colors";
import { goalIcon } from "@/lib/goal-icons";

const sizes = {
  xs: { tile: "h-6 w-6 rounded-md", icon: 14 },
  // Sits beside a two-line field, like the calendar popover's title.
  field: { tile: "h-9 w-9 rounded-lg", icon: 18 },
  sm: { tile: "h-10 w-10 rounded-xl", icon: 20 },
  lg: { tile: "h-14 w-14 rounded-2xl", icon: 28 },
};

/** A goal's icon on a tile tinted with the goal's colour. */
export function GoalBadge({
  icon,
  color,
  size = "sm",
}: {
  icon: string;
  color: string;
  size?: keyof typeof sizes;
}) {
  const s = sizes[size];
  return (
    <span
      style={goalColorStyle(color)}
      className={`goal-tint inline-flex shrink-0 items-center justify-center transition-colors ${s.tile}`}
    >
      <HugeiconsIcon icon={goalIcon(icon)} size={s.icon} strokeWidth={1.8} color="currentColor" />
    </span>
  );
}
