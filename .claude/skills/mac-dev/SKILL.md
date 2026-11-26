---
name: mac-dev
description: Build, run, test and visually check the native Supervibes Mac app in macos/. Use whenever a change touches macos/ (SwiftUI views, the menu bar, widgets, project.yml) or the user asks to run, see or check the Mac app.
---

# Supervibes Mac app: local dev loop

The Mac app lives in `macos/`. Its Xcode project is generated from `macos/project.yml` by XcodeGen. Never edit or commit `Supervibes.xcodeproj`. Change `project.yml` instead; every script regenerates the project first.

## Layout

- `Supervibes/`: the app target. `@main`, scenes (main window plus `MenuBarExtra`), the shell (`MainView`, `ShellModel`), sign-in, and the `@Observable` models that call the API.
- `Shared/`: compiled into the app, the widget **and** the tests. Models, fixtures, logging, config, and every SwiftUI view that should be snapshot-tested. Put new views here so they can be tested without launching the app.
- `SupervibesWidgets/`: the WidgetKit extension.
- `Tests/Snapshots/`: snapshot tests. Reference PNGs live in `__Snapshots__/` and are checked in.
- `Config/*.xcconfig`: per-configuration settings. Debug talks to `http://localhost:3000`, Release to production. Signing is ad hoc unless `Config/Signing.local.xcconfig` (gitignored) sets a team.

## The API and the generated client

- The app talks to `/api/v1`, a Hono app in `src/lib/api/` mounted by `src/app/api/v1/[[...route]]/route.ts`. Each route is one `createRoute` declaration (path, zod input and output, `operationId`) plus a handler that calls `src/lib` functions, scoped with `c.var.user.id`. The server only serves this API, sign-in (`/api/auth`, `/api/native/*`), the connection callback, cron and a one-line page at `/`; there is no web UI. Errors are always `{ error: { code, message } }`, with a message written for people.
- After changing anything in `src/lib/api`, run `npm run api:spec` (dev server running) to rewrite `macos/Supervibes/API/openapi.json`. The Swift client (`Client`, `Components.Schemas.*`, `Operations.*`) is generated from it at build time by swift-openapi-generator; nothing generated is checked in. `npm run api:spec -- --check` fails if the checked-in document is stale.
- `APIClient.make` adds the bearer token and decodes dates with fractional seconds (the server sends `.000Z`). Map generated types into the app's own models (e.g. `Block.init(api:)`) rather than using them in views, so views stay snapshot-testable with fixtures.
- Handle `.unauthorized` by calling `auth.sessionEnded()`.
- The generated client can't send an explicit JSON null for an optional field, so PATCH bodies use an empty string to clear a value (see `TaskPatch` in src/lib/api/routes/tasks.ts).
- Never call write endpoints with made-up data against the real database to "test" them. Some writes have side effects beyond the response (passing on a suggestion remembers its title). Test validation and 404 paths with an all-zero UUID, and leave real writes to the person.

## Design system

- Screens keep the look of the web app they replaced, not stock macOS. Use `Shared/DesignSystem/`: `Theme` colours (light and dark), `.appText(.sm, .medium, tracking:)` for Tailwind's type scale in Instrument Sans (bundled), `Icon` for the web's Hugeicons, and the components (`Card`, `CardHeader`, `SelectField`, `ToggleGroup`, `SaveStatusView`, `PageHeader`, `Backdrop`, `Avatar`). Each component names the Tailwind classes it was matched to; the web source is in git history (before the commit that retired the web UI) if you need to compare.
- Icons are generated: add the Hugeicons name and stroke width to `scripts/mac-icons.mjs`, run `node --no-warnings scripts/mac-icons.mjs`, and add a case to `Icon`. The same script exports every goal icon (`Goal-<name>` assets) and writes `GoalPalette.generated.swift` (icon groups, labels, keywords, goal colours) straight from `src/lib/goal-icons.ts` and `goal-colors.ts`; rerun it whenever those change. Goals draw with `GoalBadge`, `StatusText` and `TrajectoryStrip` (`GoalStyle.swift`).
- Put shadows on a background shape, never on a view with text in it, or the text gets a halo.
- Field placeholders: give the TextField an empty title and add `.placeholder(text, when: value.isEmpty, font:)`; macOS ignores a prompt's colour.
- Anything that animates on its own (like `SpinningIcon`) must stay still when `\.staticRendering` is true; the snapshot helper sets it so every render is the same image. Likewise pass a fixed `now` into views that show relative times.

## The window and adding a screen

- `MainView` puts the `Rail` (Shared/UI/Shell) beside `AppWindowFrame`, which shows the screen for `ShellModel.route`: Goals (`GoalsHome`, the window opens on it), a goal's page (`GoalPage` with `TasksSection`, `SourcesSection`, `NotesSection`, via `ShellModel.openGoal`), Calendar (`DayView`, `WeekView`, `CalendarModel`), Connections (`ConnectionsPage`) and Settings (`SettingsPage`, also ⌘,, from the account menu).
- To add a screen: build it in `Shared/UI/` against plain models (`Shared/Models/`), with fixtures and a snapshot test (render it inside `Rail` + `AppWindowFrame` too); keep the API calls in an `@Observable` model in `Supervibes/`. Add a `Route` case, route it in `ShellModel`, and give it a rail item or menu entry.
- Menus and confirm dialogs go through `OverlayCenter` (`@Environment(\.overlays)`), drawn above the window: anchor a menu with `AnchorReader`, then `showMenu(anchor:)` with a `MenuPanel` of `MenuItem`s (`alignLeading: true` to line up with a button's left edge), or `showDialog` with a `ConfirmDialog`.
- Dates use `Date.webDay` / `webMonthDay` / `webMonthDayTime` (US English, as the web app wrote them), so they read the same whatever the Mac's locale.
- Connecting an app runs its consent page in the system sign-in sheet; see `src/lib/app-connect.ts` for why the code comes back to the app to finish.
- The widget reads today's blocks from the App Group the app writes to (`Shared/Models/WidgetShare.swift`); it never calls the API.

## Commands (run from `macos/`)

| Goal | Command |
|---|---|
| Build | `scripts/build.sh` (prints only warnings and errors) |
| Build and launch the Debug app ("Supervibes Dev"), replacing a running Debug copy | `scripts/run.sh` |
| Build the Release app (talks to production) | `scripts/release.sh` |
| Build Release and install it in /Applications, replacing and reopening it | `scripts/release.sh --install` (only when the user asks: it replaces the copy they use every day) |
| All tests | `scripts/test.sh` (extra args go to xcodebuild, e.g. `-only-testing:...`) |
| Snapshot tests, compare (every class with references) | `scripts/snapshot.sh` |
| Snapshot tests, re-record only what a UI change touched | `scripts/snapshot.sh --record testWeekView testLifeNoSeason` (names are tests, classes like `SeasonTests`, or `Class/test`) |
| Snapshot tests, re-record everything | `scripts/snapshot.sh --record` (rarely: it re-renders every reference, render noise included) |
| App logs, last N minutes | `scripts/logs.sh 2m` |
| App logs, live | `scripts/logs.sh` (streams; run in the background) |

Debug builds load the local Next.js server. Start it with the preview tool's `dev` configuration (or `npm run dev` at the repo root) before `scripts/run.sh`.

Debug and Release are separate apps: Debug is "Supervibes Dev" (`Supervibes Dev.app`, `com.supervibes.mac.debug`, "Dev" after its menu bar title, localhost, token in a file), Release is "Supervibes" (`com.supervibes.mac`, production, token in the Keychain), so the user can keep the installed Release app open while you work. `run.sh` only ever quits the Debug one. Release is signed with the user's Apple Developer team once an Apple Development certificate is in the Keychain: `release.sh` then writes the gitignored `Config/Signing.local.xcconfig` from it; until then it's signed ad hoc.

## Seeing changes live: previews and Xcode's tools

- Every screen in `Shared/UI/` ends with `#Preview` blocks built from `Fixtures` at `Fixtures.referenceNow`, mirroring its snapshot tests. `Rail.swift` has a "Window" preview of the whole window on Goals. When you add or change a screen, add or update its preview alongside the snapshot test. Use `@Previewable @State` for bindings so toggles work in the canvas.
- The person keeps `macos/Supervibes.xcodeproj` open in Xcode with the canvas showing (⌥⌘↩). Xcode reloads files edited on disk, so the canvas follows your edits in a second or two, with no rebuild or relaunch. If `xcodegen generate` rewrites the project while it's open, Xcode may ask to revert to the version on disk; that's expected.
- Xcode's own tools are registered with Claude Code as the `xcode` MCP server (`xcrun mcpbridge`, user scope). Xcode must be running with the project open. The first time, call `XcodeOpenWorkspace` with the project's path; Xcode then asks the person to approve the agent. Useful tools:
  - `RenderPreview`: renders a `#Preview` and returns the path of a PNG; open it with the Read tool. Pass `workspaceIdentifier` from `XcodeOpenWorkspace`'s result, `sourceFilePath` as the project path (`Supervibes/Shared/UI/Shell/Rail.swift`), and `previewDefinitionIndexInFile` for a file's second or later preview. The first render after a change takes about a minute; later ones take a few seconds. Use it to check a view while iterating; keep snapshot tests as the record.
  - `XcodeRefreshCodeIssuesInFile`: compiler errors for one file, faster than a full build.
  - `BuildProject`, `RunProject` / `StopProject`, `GetConsoleOutput`: build, run and read the app's console through Xcode.
- The scripts below stay the source of truth for builds, tests and release; Xcode's tools are for fast looks.

## Verifying a change

1. **Views:** add or update a test in `Tests/Snapshots/` using `assertAppearances(view, width:)`, which renders light and dark. Run `scripts/snapshot.sh --record` with the tests the change touches (only those are re-recorded), then **open the PNGs it lists with the Read tool and look at them.** Then run `scripts/snapshot.sh` with no names to confirm every snapshot is green, which also shows what else the change touched. A logic-only change needs no recording: `scripts/test.sh` compares every snapshot anyway. On a failed comparison, the new image and a diff are in `build/snapshot-failures/`.
2. **Runtime behaviour:** log through `Log.app` / `Log.auth` / `Log.widgets` (subsystem `com.supervibes.mac`) at `.info` or higher. `.debug` is not persisted, so `logs.sh 2m` won't show it. Launch with `scripts/run.sh`, then read `scripts/logs.sh 1m`.
3. **Real menu bar, widgets, notifications, permission prompts:** these can't be seen from the shell (`screencapture` has no Screen Recording permission here). Say what you couldn't check, and ask the user to look.

## Gotchas

- The menu bar runs on `/api/v1/today` (fetched every 5 minutes, on sign-in, on wake and when the day changes). Fixtures are for snapshot tests and the widget gallery's preview. `Fixtures.referenceNow` is fixed so snapshots are deterministic. Never use `Date()` in a snapshot test.
- `xcodebuild` runs with `-skipPackagePluginValidation` (in `scripts/_common.sh`) so the OpenAPI generator plugin runs without an Xcode trust prompt.
- Times are formatted in the Mac's locale and time zone (Europe/Madrid), so the references assume that.
- Hardened runtime is on for Release only (`project.yml`). In Debug it stops Xcode from loading its preview code, and every preview fails with "did not launch in 30 seconds". Keep it off for Debug.
- Ad-hoc signing turns hardened runtime off and means Screen Recording and Accessibility permissions won't survive rebuilds. Set up `Signing.local.xcconfig` before any work on screen context.
- Sign-in goes through the system sign-in sheet (`Supervibes/Auth/AuthModel.swift`, server side in `src/lib/native-auth.ts` and `src/app/api/native/*`). The app keeps a bearer token and sends it with every API call.
- Completing a sign-in needs the user to pick their Google account in the sheet. Don't try to drive it. Debug builds keep the token in `~/Library/Application Support/Supervibes/dev-session-<host>` (Release builds use the Keychain), so delete that file to test signing in again.
- After adding a target, entitlement or Info.plist key, edit `project.yml`. Generated plists and entitlements are gitignored.
