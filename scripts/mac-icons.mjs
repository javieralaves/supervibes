#!/usr/bin/env node
// Writes the Hugeicons the Mac app uses into an asset catalog, as template SVGs, so native
// screens use the same icons as the web app. Add a name to ICONS and run `node scripts/mac-icons.mjs`.
import { mkdir, rm, writeFile } from "node:fs/promises";

import * as icons from "@hugeicons/core-free-icons";

// Icon name → stroke widths needed (the web passes strokeWidth per use; 1.5 is Hugeicons' default).
const ICONS = {
  Target02Icon: [1.8],
  Calendar03Icon: [1.8],
  Plug01Icon: [1.8],
  Settings02Icon: [1.5, 1.8],
  Logout01Icon: [1.5],
  Moon02Icon: [1.5],
  Sun03Icon: [1.5],
  Tick02Icon: [1.5],
  ArrowDown01Icon: [1.5],
};

const CATALOG = new URL("../macos/Shared/DesignSystem/Icons.xcassets/", import.meta.url);

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
console.log(`Wrote ${names.length} icons: ${names.join(", ")}`);
