#!/usr/bin/env node
// Writes the API's OpenAPI document to the Mac app, which generates its Swift client from it.
// Run after changing anything in src/lib/api, with the dev server running (`npm run dev`):
//   npm run api:spec          write it
//   npm run api:spec -- --check   fail if the checked-in copy is out of date
import { readFile, writeFile } from "node:fs/promises";

const SOURCE = process.env.API_SPEC_URL ?? "http://localhost:3000/api/v1/openapi.json";
const TARGET = new URL("../macos/Supervibes/API/openapi.json", import.meta.url);

let spec;
try {
  const response = await fetch(SOURCE);
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  spec = await response.json();
} catch (error) {
  console.error(`Couldn't fetch ${SOURCE}: ${error.message}. Is \`npm run dev\` running?`);
  process.exit(1);
}

const text = `${JSON.stringify(spec, null, 2)}\n`;

if (process.argv.includes("--check")) {
  const current = await readFile(TARGET, "utf8").catch(() => "");
  if (current !== text) {
    console.error("macos/Supervibes/API/openapi.json is out of date. Run `npm run api:spec`.");
    process.exit(1);
  }
  console.log("OpenAPI document is up to date.");
} else {
  await writeFile(TARGET, text);
  console.log(`Wrote ${Object.keys(spec.paths).length} paths to macos/Supervibes/API/openapi.json`);
}
