import { config } from "dotenv";
import { defineConfig } from "drizzle-kit";

config({ path: ".env.local", quiet: true });

// drizzle-kit talks to Postgres directly, so it uses the unpooled connection.
const url = process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL;
if (!url) {
  throw new Error(
    "DATABASE_URL is not set. Run `vercel env pull .env.local` first.",
  );
}

export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url },
  // Must match the casing in src/db/index.ts so camelCase keys map to snake_case columns.
  casing: "snake_case",
  strict: true,
  verbose: true,
});
