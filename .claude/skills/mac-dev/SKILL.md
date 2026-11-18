---
name: mac-dev
description: Build, run, test and visually check the native Supervibes Mac app in macos/. Use whenever a change touches macos/ (SwiftUI views, the menu bar, widgets, the web shell, project.yml) or the user asks to run, see or check the Mac app.
---

# Supervibes Mac app: local dev loop

The Mac app lives in `macos/`. Its Xcode project is generated from `macos/project.yml` by XcodeGen. Never edit or commit `Supervibes.xcodeproj`. Change `project.yml` instead; every script regenerates the project first.

## Layout

- `Supervibes/`: the app target. `@main`, scenes (main window plus `MenuBarExtra`), and `WebShellView` (the web app in a WKWebView while screens are still web).
- `Shared/`: compiled into the app, the widget **and** the tests. Models, fixtures, logging, config, and every SwiftUI view that should be snapshot-tested. Put new views here so they can be tested without launching the app.
- `SupervibesWidgets/`: the WidgetKit extension.
- `Tests/Snapshots/`: snapshot tests. Reference PNGs live in `__Snapshots__/` and are checked in.
- `Config/*.xcconfig`: per-configuration settings. Debug talks to `http://localhost:3000`, Release to production. Signing is ad hoc unless `Config/Signing.local.xcconfig` (gitignored) sets a team.

## The API and the generated client

- The app talks to `/api/v1`, a Hono app in `src/lib/api/` mounted by `src/app/api/v1/[[...route]]/route.ts`. Each route is one `createRoute` declaration (path, zod input and output, `operationId`) plus a handler that calls the same `src/lib` functions the server actions use, scoped with `c.var.user.id`. Errors are always `{ error: { code, message } }`, with a message written for people.
- After changing anything in `src/lib/api`, run `npm run api:spec` (dev server running) to rewrite `macos/Supervibes/API/openapi.json`. The Swift client (`Client`, `Components.Schemas.*`, `Operations.*`) is generated from it at build time by swift-openapi-generator; nothing generated is checked in. `npm run api:spec -- --check` fails if the checked-in document is stale.
- `APIClient.make` adds the bearer token and decodes dates with fractional seconds (the server sends `.000Z`). Map generated types into the app's own models (e.g. `Block.init(api:)`) rather than using them in views, so views stay snapshot-testable with fixtures.
- Handle `.unauthorized` by calling `auth.sessionEnded()`.
- The generated client can't send an explicit JSON null for an optional field, so PATCH bodies use an empty string to clear a value (see `TaskPatch` in src/lib/api/routes/tasks.ts).
- Never call write endpoints with made-up data against the real database to "test" them. Some writes have side effects beyond the response (passing on a suggestion remembers its title). Test validation and 404 paths with an all-zero UUID, and leave real writes to the person.

## Design system

- Native screens look like the web app, not like stock macOS. Use `Shared/DesignSystem/`: `Theme` colours (ported from `src/app/globals.css`, light and dark), `.appText(.sm, .medium, tracking:)` for Tailwind's type scale in Instrument Sans (bundled), `Icon` for the web's Hugeicons, and the components (`Card`, `CardHeader`, `SelectField`, `ToggleGroup`, `SaveStatusView`, `PageHeader`, `Backdrop`, `Avatar`). Each component names the Tailwind classes it matches; compare against the web source when building a screen.
- Icons are generated: add the Hugeicons name and stroke width to `scripts/mac-icons.mjs`, run `node --no-warnings scripts/mac-icons.mjs`, and add a case to `Icon`. The same script exports every goal icon (`Goal-<name>` assets) and writes `GoalPalette.generated.swift` (icon groups, labels, keywords, goal colours) straight from `src/lib/goal-icons.ts` and `goal-colors.ts`; rerun it whenever those change. Goals draw with `GoalBadge`, `StatusText` and `TrajectoryStrip` (`GoalStyle.swift`).
- Put shadows on a background shape, never on a view with text in it, or the text gets a halo.
- Field placeholders: give the TextField an empty title and add `.placeholder(text, when: value.isEmpty, font:)`; macOS ignores a prompt's colour.
- Anything that animates on its own (like `SpinningIcon`) must stay still when `\.staticRendering` is true; the snapshot helper sets it so every render is the same image. Likewise pass a fixed `now` into views that show relative times.
- If `globals.css` tokens change, change `Theme` to match.

## The window and moving a screen from web to native

- The main window is native: `MainView` puts the native `Rail` (Shared/UI/Shell) beside `AppWindowFrame`, which shows either the web view (`WebContentModel`) or a native screen, chosen by `ShellModel.route`. The web page is told it's inside the app (`html[data-shell="mac"]`) and hides its own rail and frame (`[data-app-rail]`, `[data-app-window]` in globals.css).
- To move a page: build it in `Shared/UI/` against plain models (`Shared/Models/`), with fixtures and a snapshot test (render it inside `Rail` + `AppWindowFrame` too); keep the API calls in an `@Observable` model in `Supervibes/`. Add a `Route` case, add its web path to `WebContentModel.nativePaths`, route it in `ShellModel`, and give it a rail item or menu entry. A page script catches in-app links to native paths before Next.js handles them, and full loads of them are cancelled.
- Menus and confirm dialogs go through `OverlayCenter` (`@Environment(\.overlays)`), drawn above the window like the web's Radix portals: anchor a menu with `AnchorReader`, then `showMenu(anchor:)` with a `MenuPanel` of `MenuItem`s, or `showDialog` with a `ConfirmDialog`.
- Dates the web formats in US English use `Date.webDay` / `webMonthDay` / `webMonthDayTime`, so they match whatever the Mac's locale.
- Done so far: `/` → `GoalsHome` (the window opens on it; the web view isn't loaded until a web page is wanted), with the new goal `GoalDialog`; a goal's own page (`/goals/<id>`) is still web, via `ShellModel.openGoal`, while its native `GoalPage` is built in parts (header, progress, this week and tasks are done; notes and sources follow in its `sections`). In Debug builds, Option-click a goal card to preview the native page. `/settings` → `SettingsPage` (also ⌘,), opened from the account menu; `/connections` → `ConnectionsPage`, the rail's Connections item. Connecting an app runs its consent page in the system sign-in sheet; see `src/lib/app-connect.ts` for why the code comes back to the app to finish.

## Commands (run from `macos/`)

| Goal | Command |
|---|---|
| Build | `scripts/build.sh` (prints only warnings and errors) |
| Build and launch, replacing any running copy | `scripts/run.sh` |
| All tests | `scripts/test.sh` (extra args go to xcodebuild, e.g. `-only-testing:...`) |
| Snapshot tests, compare | `scripts/snapshot.sh` |
| Snapshot tests, re-record after an intended UI change | `scripts/snapshot.sh --record` |
| App logs, last N minutes | `scripts/logs.sh 2m` |
| App logs, live | `scripts/logs.sh` (streams; run in the background) |

Debug builds load the local Next.js server. Start it with the preview tool's `dev` configuration (or `npm run dev` at the repo root) before `scripts/run.sh`.

## Verifying a change

1. **Views:** add or update a test in `Tests/Snapshots/` using `assertAppearances(view, width:)`, which renders light and dark. Run `scripts/snapshot.sh --record`, then **open the PNGs it lists with the Read tool and look at them.** Re-run without `--record` to confirm the run is green. On a failed comparison, the new image and a diff are in `build/snapshot-failures/`.
2. **Runtime behaviour:** log through `Log.app` / `Log.web` / `Log.widgets` (subsystem `com.supervibes.mac`) at `.info` or higher. `.debug` is not persisted, so `logs.sh 2m` won't show it. Launch with `scripts/run.sh`, then read `scripts/logs.sh 1m`.
3. **Web content inside the shell:** check it in the browser pane as usual. Debug builds also allow Safari's Web Inspector to attach to the app's web view.
4. **Real menu bar, widgets, notifications, permission prompts:** these can't be seen from the shell (`screencapture` has no Screen Recording permission here). Say what you couldn't check, and ask the user to look.

## Gotchas

- The menu bar runs on `/api/v1/today` (fetched every 5 minutes, on sign-in, on wake and when the day changes). Fixtures remain for snapshot tests and the widget, which can't read the app's data until there's an App Group, and that needs a real signing team. `Fixtures.referenceNow` is fixed so snapshots are deterministic. Never use `Date()` in a snapshot test.
- `xcodebuild` runs with `-skipPackagePluginValidation` (in `scripts/_common.sh`) so the OpenAPI generator plugin runs without an Xcode trust prompt.
- Times are formatted in the Mac's locale and time zone (Europe/Madrid), so the references assume that.
- Ad-hoc signing turns hardened runtime off and means Screen Recording and Accessibility permissions won't survive rebuilds. Set up `Signing.local.xcconfig` before any work on screen context.
- Sign-in goes through the system sign-in sheet (`Supervibes/Auth/AuthModel.swift`, server side in `src/lib/native-auth.ts` and `src/app/api/native/*`). The app keeps a bearer token and gives the web view the same session through `/api/native/handoff`. Google sign-in can't run inside the WKWebView, and the web app's `/sign-in` page is replaced by native sign-in.
- Completing a sign-in needs the user to pick their Google account in the sheet. Don't try to drive it. Debug builds keep the token in `~/Library/Application Support/Supervibes/dev-session-<host>` (Release builds use the Keychain), so delete that file to test signing in again.
- After adding a target, entitlement or Info.plist key, edit `project.yml`. Generated plists and entitlements are gitignored.
