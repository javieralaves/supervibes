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

- Fixtures stand in for real data until the API exists. `Fixtures.referenceNow` is fixed so snapshots are deterministic. Never use `Date()` in a snapshot test.
- Times are formatted in the Mac's locale and time zone (Europe/Madrid), so the references assume that.
- Ad-hoc signing turns hardened runtime off and means Screen Recording and Accessibility permissions won't survive rebuilds. Set up `Signing.local.xcconfig` before any work on screen context.
- Google sign-in can't run inside a WKWebView. The shell stops it and shows a native message until native sign-in exists.
- After adding a target, entitlement or Info.plist key, edit `project.yml`. Generated plists and entitlements are gitignored.
