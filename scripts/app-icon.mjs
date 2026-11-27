#!/usr/bin/env node
// Writes the Mac app's icon as Icon Composer documents, from the Superfocus mark the rail draws
// (macos/Shared/DesignSystem/SuperfocusLogo.swift) and the goal colours, so the two never drift.
// The icon tile is the mark: macOS's rounded square stands in for the mark's outer square, filled
// with its gradient at full strength, and the mark's square hole sits in the middle as a glass layer.
//   node --no-warnings scripts/app-icon.mjs
// Writes macos/Supervibes/AppIcon.icon (Release, "Supervibes") and AppIconDev.icon (Debug,
// "Supervibes Dev", in greys so the two apps are easy to tell apart in the Dock).
import { mkdir, rm, writeFile } from "node:fs/promises";

import { GOAL_COLORS } from "../src/lib/goal-colors.ts";

const SIZE = 1024;

// The mark's outer square spans 3.5…52.5 on its 56 box; that span becomes the whole tile.
const OUTER = { from: 3.5, to: 52.5 };
const scale = SIZE / (OUTER.to - OUTER.from);
const pt = (x, y) => `${((x - OUTER.from) * scale).toFixed(2)} ${((y - OUTER.from) * scale).toFixed(2)}`;

// The mark's square hole, point for point from SuperfocusLogoShape.
const HOLE = [
  ["M", [28, 18.8125]],
  ["C", [25.1464, 18.8125], [23.7193, 18.8122], [22.5938, 19.2783]],
  ["C", [21.093, 19.9], [19.9, 21.093], [19.2783, 22.5938]],
  ["C", [18.8122, 23.7193], [18.8125, 25.1464], [18.8125, 28]],
  ["C", [18.8125, 30.8536], [18.8122, 32.2807], [19.2783, 33.4063]],
  ["C", [19.9, 34.907], [21.093, 36.1], [22.5938, 36.7217]],
  ["C", [23.7193, 37.1878], [25.1464, 37.1875], [28, 37.1875]],
  ["C", [30.8536, 37.1875], [32.2807, 37.1878], [33.4063, 36.7217]],
  ["C", [34.907, 36.1], [36.1, 34.907], [36.7217, 33.4063]],
  ["C", [37.1878, 32.2807], [37.1875, 30.8536], [37.1875, 28]],
  ["C", [37.1875, 25.1464], [37.1878, 23.7193], [36.7217, 22.5938]],
  ["C", [36.1, 21.093], [34.907, 19.9], [33.4063, 19.2783]],
  ["C", [32.2807, 18.8122], [30.8536, 18.8125], [28, 18.8125]],
];
const holePath = HOLE.map(([cmd, ...points]) => `${cmd} ${points.map(([x, y]) => pt(x, y)).join(" ")}`).join(" ") + " Z";

const svg = (body, defs = "") =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 ${SIZE} ${SIZE}">${defs}${body}</svg>\n`;

// Top left to bottom right, like the mark.
function background(colors) {
  const stops = colors
    .map((color, i) => `<stop offset="${(i / (colors.length - 1)).toFixed(3)}" stop-color="${color}"/>`)
    .join("");
  const defs = `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">${stops}</linearGradient></defs>`;
  return svg(`<rect width="${SIZE}" height="${SIZE}" fill="url(#g)"/>`, defs);
}

const ICONS = {
  // The rail's gradient, without the ink it mixes in: amber, coral, pink, violet, sky.
  AppIcon: ["amber", "coral", "pink", "violet", "sky"].map((key) => GOAL_COLORS[key].light),
  AppIconDev: ["#9a9a9f", "#6e6e73", "#48484c"],
};

const document = {
  groups: [
    {
      layers: [{ "image-name": "hole.svg", name: "Hole", glass: true }],
      shadow: { kind: "neutral", opacity: 0.5 },
      translucency: { enabled: true, value: 0.3 },
    },
    {
      layers: [{ "image-name": "background.svg", name: "Background", glass: false }],
    },
  ],
  "supported-platforms": { squares: ["macOS"] },
};

for (const [name, colors] of Object.entries(ICONS)) {
  const folder = new URL(`../macos/Supervibes/${name}.icon/`, import.meta.url);
  await rm(folder, { recursive: true, force: true });
  await mkdir(new URL("Assets/", folder), { recursive: true });
  await writeFile(new URL("Assets/background.svg", folder), background(colors));
  await writeFile(new URL("Assets/hole.svg", folder), svg(`<path d="${holePath}" fill="#ffffff"/>`));
  await writeFile(new URL("icon.json", folder), JSON.stringify(document, null, 2) + "\n");
}
console.log(`Wrote ${Object.keys(ICONS).join(".icon, ")}.icon in macos/Supervibes`);
