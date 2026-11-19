# Supervibes

Supervibes is a Mac app for planning your time around your goals. This repository holds both
halves:

- **`macos/`**: the app (SwiftUI): goals, the calendar, connections and settings, plus a menu bar
  item and a widget. Its dev loop is in `.claude/skills/mac-dev/SKILL.md`.
- **`src/`**: the server it talks to (Next.js on Vercel, Neon Postgres): the API at `/api/v1`,
  sign-in (`/api/auth`, `/api/native/*`), the callback for connecting apps, and the daily sync
  (`/api/cron/sync`). There's no web UI; the site's root only says Supervibes is a Mac app.

## Running it locally

```bash
npm install
npm run dev
```

Then build and run the Debug app ("Supervibes Dev"), which talks to `http://localhost:3000`:

```bash
cd macos && scripts/run.sh
```

`scripts/release.sh --install` builds the Release app, which talks to production, and installs it
in /Applications.

## Changing the API

After changing anything in `src/lib/api`, run `npm run api:spec` with the dev server running. It
rewrites `macos/Supervibes/API/openapi.json`, which the app's Swift client is generated from.

Database changes go through Drizzle: `npm run db:generate`, then `npm run db:migrate`.
