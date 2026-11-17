"use client";

import { HugeiconsIcon } from "@hugeicons/react";

import { goalColorStyle } from "@/lib/goal-colors";
import { goalIcon } from "@/lib/goal-icons";

const sizes = {
  sm: { tile: "h-11 w-11 rounded-[14px]", icon: 22 },
  lg: { tile: "h-16 w-16 rounded-[20px]", icon: 32 },
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
