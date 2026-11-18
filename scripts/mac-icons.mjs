#!/usr/bin/env node
// Writes the Hugeicons the Mac app uses into an asset catalog, as template SVGs, so native
// screens use the same icons as the web app. Add a name to ICONS and run `node scripts/mac-icons.mjs`.
import { copyFile, mkdir, rm, writeFile } from "node:fs/promises";

import * as icons from "@hugeicons/core-free-icons";

// The web app's own lists, read straight from its source (Node runs TypeScript without types).
import { DEFAULT_GOAL_COLOR, GOAL_COLORS } from "../src/lib/goal-colors.ts";
import { DEFAULT_GOAL_ICON, GOAL_ICON_GROUPS } from "../src/lib/goal-icons.ts";

// Icon name → stroke widths needed (the web passes strokeWidth per use; 1.5 is Hugeicons' default).
const ICONS = {
  Target02Icon: [1.8],
  Calendar03Icon: [1.8],
  Plug01Icon: [1.8],
  Settings02Icon: [1.5, 1.8],
  Logout01Icon: [1.5],
  Moon02Icon: [1.5],
  Sun03Icon: [1.5],
  Tick02Icon: [1.5, 2.5],
  ArrowDown01Icon: [1.5],
  MoreHorizontalIcon: [1.5],
  Refresh01Icon: [1.5],
  Unlink04Icon: [1.5],
  Add01Icon: [1.5],
  ArrowRight01Icon: [1.5],
  Cancel01Icon: [1.5],
  Search01Icon: [1.5],
  Delete02Icon: [1.5],
  Calendar03Icon: [1.8, 1.5],
  ArrowLeft01Icon: [1.5],
  PencilEdit02Icon: [1.5],
  Note01Icon: [1.5],
  CheckListIcon: [1.5],
  Clock01Icon: [1.5],
  DashedLineCircleIcon: [1.5],
  DragDropVerticalIcon: [1.5],
  ViewIcon: [1.5],
  Flag02Icon: [1.5],
};

// Connected apps' marks (src/components/provider-mark.tsx): filled paths, drawn white on a tile.
const BRAND_PATHS = {
  LinearMark:
    "M2.886 4.18A11.982 11.982 0 0 1 11.99 0C18.624 0 24 5.376 24 12.009c0 3.64-1.62 6.903-4.18 9.105L2.887 4.18ZM1.817 5.626l16.556 16.556c-.524.33-1.075.62-1.65.866L.951 7.277c.247-.575.537-1.126.866-1.65ZM.322 9.163l14.515 14.515c-.71.172-1.443.282-2.195.322L0 11.358a12 12 0 0 1 .322-2.195Zm-.17 4.862 9.823 9.824a12.02 12.02 0 0 1-9.824-9.824Z",
  GitHubMark:
    "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12",
};
// Bitmap app icons copied as they are.
const BRAND_IMAGES = { GranolaMark: "../public/brands/granola.png" };

const CATALOG = new URL("../macos/Shared/DesignSystem/Icons.xcassets/", import.meta.url);
const GOAL_SWIFT = new URL("../macos/Shared/DesignSystem/GoalPalette.generated.swift", import.meta.url);

const attr = (name) => name.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

function svg(nodes, strokeWidth) {
  const body = nodes
    .map(([tag, attrs]) => {
      const parts = Object.entries(attrs)
        .filter(([k]) => k !== "key")
        .map(([k, v]) => {
          let value = String(v).replaceAll("currentColor", "#000000");
          if (k === "strokeWidth") value = String(strokeWidth);
          return `${attr(k)}="${value}"`;
        });
      return `  <${tag} ${parts.join(" ")}/>`;
    })
    .join("\n");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">\n${body}\n</svg>\n`;
}

await rm(CATALOG, { recursive: true, force: true });
await mkdir(CATALOG, { recursive: true });
await writeFile(new URL("Contents.json", CATALOG), JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2));

const names = [];
for (const [name, widths] of Object.entries(ICONS)) {
  const nodes = icons[name];
  if (!nodes) throw new Error(`No icon named ${name}`);
  for (const width of widths) {
    const asset = `${name.replace(/Icon$/, "")}-${String(width).replace(".", "_")}`;
    const folder = new URL(`${asset}.imageset/`, CATALOG);
    await mkdir(folder, { recursive: true });
    await writeFile(new URL(`${asset}.svg`, folder), svg(nodes, width));
    await writeFile(
      new URL("Contents.json", folder),
      JSON.stringify(
        {
          images: [{ filename: `${asset}.svg`, idiom: "universal" }],
          info: { author: "xcode", version: 1 },
          properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
        },
        null,
        2,
      ),
    );
    names.push(asset);
  }
}
async function imageset(asset, filename, properties) {
  const folder = new URL(`${asset}.imageset/`, CATALOG);
  await mkdir(folder, { recursive: true });
  await writeFile(
    new URL("Contents.json", folder),
    JSON.stringify({ images: [{ filename, idiom: "universal" }], info: { author: "xcode", version: 1 }, properties }, null, 2),
  );
  return folder;
}

for (const [asset, d] of Object.entries(BRAND_PATHS)) {
  const folder = await imageset(asset, `${asset}.svg`, {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template",
  });
  await writeFile(
    new URL(`${asset}.svg`, folder),
    `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">\n  <path d="${d}" fill="#000000"/>\n</svg>\n`,
  );
  names.push(asset);
}

for (const [asset, source] of Object.entries(BRAND_IMAGES)) {
  const folder = await imageset(asset, `${asset}.png`, { "template-rendering-intent": "original" });
  await copyFile(new URL(source, import.meta.url), new URL(`${asset}.png`, folder));
  names.push(asset);
}

// Goal icons (drawn at the web's strokeWidth 1.8), plus their groups, labels and keywords for the
// picker, and the goal colours, as Swift.
const swiftString = (value) => JSON.stringify(value);
let goalIconCount = 0;
for (const group of GOAL_ICON_GROUPS) {
  for (const [name, def] of Object.entries(group.icons)) {
    const asset = `Goal-${name}`;
    const folder = await imageset(asset, `${asset}.svg`, {
      "preserves-vector-representation": true,
      "template-rendering-intent": "template",
    });
    await writeFile(new URL(`${asset}.svg`, folder), svg(def.icon, 1.8));
    goalIconCount++;
  }
}
const groupsSwift = GOAL_ICON_GROUPS.map(
  (group) =>
    `        GoalIconGroup(label: ${swiftString(group.label)}, icons: [\n` +
    Object.entries(group.icons)
      .map(([name, def]) => `            GoalIconInfo(name: ${swiftString(name)}, label: ${swiftString(def.label)}, keywords: ${swiftString(def.keywords)}),`)
      .join("\n") +
    `\n        ]),`,
).join("\n");
const colorsSwift = Object.entries(GOAL_COLORS)
  .map(([key, c]) => `        GoalColorInfo(key: ${swiftString(key)}, label: ${swiftString(c.label)}, light: ${swiftString(c.light)}, dark: ${swiftString(c.dark)}),`)
  .join("\n");
await writeFile(
  GOAL_SWIFT,
  `// Generated by scripts/mac-icons.mjs from src/lib/goal-icons.ts and src/lib/goal-colors.ts. Don't edit.

enum GoalPalette {
    static let defaultIcon = ${swiftString(DEFAULT_GOAL_ICON)}
    static let defaultColor = ${swiftString(DEFAULT_GOAL_COLOR)}

    static let iconGroups: [GoalIconGroup] = [
${groupsSwift}
    ]

    static let colors: [GoalColorInfo] = [
${colorsSwift}
    ]
}
`,
);

console.log(`Wrote ${names.length} icons (${names.join(", ")}), ${goalIconCount} goal icons and GoalPalette.generated.swift`);
