/**
 * Goal colour palette. Goals store the key ("violet"), never a raw hex, so the
 * palette can be retuned and each colour gets a light- and dark-mode variant.
 */
export const GOAL_COLORS = {
  coral: { label: "Coral", light: "#e2542b", dark: "#ff8a65" },
  amber: { label: "Amber", light: "#c97a04", dark: "#fbbf24" },
  green: { label: "Green", light: "#15924a", dark: "#4ade80" },
  teal: { label: "Teal", light: "#0c8a80", dark: "#2dd4bf" },
  sky: { label: "Sky", light: "#0279b8", dark: "#38bdf8" },
  indigo: { label: "Indigo", light: "#4f46e5", dark: "#818cf8" },
  violet: { label: "Violet", light: "#7c3aed", dark: "#a78bfa" },
  pink: { label: "Pink", light: "#d0246f", dark: "#f472b6" },
  slate: { label: "Slate", light: "#475569", dark: "#94a3b8" },
} as const;

export type GoalColor = keyof typeof GOAL_COLORS;

export const GOAL_COLOR_KEYS = Object.keys(GOAL_COLORS) as [GoalColor, ...GoalColor[]];

export const DEFAULT_GOAL_COLOR: GoalColor = "violet";

export function isGoalColor(value: string): value is GoalColor {
  return value in GOAL_COLORS;
}

/** CSS custom properties consumed by the `.goal-tint` utilities in globals.css. */
export function goalColorStyle(color: string): React.CSSProperties {
  const c = GOAL_COLORS[isGoalColor(color) ? color : DEFAULT_GOAL_COLOR];
  return { "--goal-light": c.light, "--goal-dark": c.dark } as React.CSSProperties;
}
