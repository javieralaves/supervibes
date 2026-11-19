/**
 * Goal colour palette. Goals store the key ("violet"), never a raw hex, so the
 * palette can be retuned and each colour gets a light- and dark-mode variant.
 */
export const GOAL_COLORS = {
  // Vibrant accents against the monochrome UI. Light values stay dark enough for
  // icons on a light tint; dark values are brighter for dark mode.
  coral: { label: "Coral", light: "#e8492f", dark: "#ff7a62" },
  amber: { label: "Amber", light: "#e08a00", dark: "#ffb627" },
  green: { label: "Green", light: "#14a05a", dark: "#3ddc84" },
  teal: { label: "Teal", light: "#0aa395", dark: "#2ee6d0" },
  sky: { label: "Sky", light: "#0a8be0", dark: "#3cb8ff" },
  indigo: { label: "Indigo", light: "#4f46e5", dark: "#8b85ff" },
  violet: { label: "Violet", light: "#8b3df0", dark: "#b88bff" },
  pink: { label: "Pink", light: "#e6327f", dark: "#ff6fae" },
  slate: { label: "Slate", light: "#475569", dark: "#a3b0c2" },
} as const;

export type GoalColor = keyof typeof GOAL_COLORS;

export const GOAL_COLOR_KEYS = Object.keys(GOAL_COLORS) as [GoalColor, ...GoalColor[]];

export const DEFAULT_GOAL_COLOR: GoalColor = "violet";

export function isGoalColor(value: string): value is GoalColor {
  return value in GOAL_COLORS;
}
