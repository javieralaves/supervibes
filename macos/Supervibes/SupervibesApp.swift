import SwiftUI

@main
struct SupervibesApp: App {
    @State private var auth: AuthModel
    @State private var model: AppModel
    @State private var shell: ShellModel

    init() {
        Log.app.info("Launched, talking to \(AppConfig.baseURL.absoluteString, privacy: .public)")
        let auth = AuthModel(baseURL: AppConfig.baseURL)
        let model = AppModel(auth: auth)
        let shell = ShellModel(auth: auth)
        // Clicking a session notice opens the calendar on its block.
        model.notifier.onOpenBlock = { shell.openBlock($0) }
        _auth = State(initialValue: auth)
        _model = State(initialValue: model)
        _shell = State(initialValue: shell)
    }

    var body: some Scene {
        // The main window: the rail beside the app's window, which shows the screen for the route.
        Window(appName, id: "main") {
            MainView(auth: auth, shell: shell, notifier: model.notifier)
                .frame(minWidth: 900, minHeight: 600)
                .task { await auth.restore() }
                .onChange(of: auth.isSignedIn) { model.refreshSoon() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsButton(shell: shell, enabled: auth.isSignedIn)
            }
            CommandGroup(after: .appInfo) {
                if auth.isSignedIn {
                    Button("Sign Out") {
                        Task { await auth.signOut() }
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarRoot(model: model)
        } label: {
            MenuBarLabel(model: model, shell: shell)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Settings… (⌘,): the Settings page in the main window, opening the window if it's closed.
private struct OpenSettingsButton: View {
    let shell: ShellModel
    let enabled: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            shell.openSettings()
            openWindow(id: "main")
        }
        .keyboardShortcut(",")
        .disabled(!enabled)
    }
}

/// "Supervibes", or "Supervibes Dev" for Debug builds.
let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Supervibes"

/// The menu bar item's title. It's drawn for as long as the app runs, even with the window closed,
/// so it's also what opens the window when something asks for it (clicking a session notice).
private struct MenuBarLabel: View {
    let model: AppModel
    let shell: ShellModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            #if DEBUG
            // Next to the installed app's item, this one says it's the Dev build.
            Text("\(model.menuBarTitle) Dev")
            #else
            model.menuBarTitle
            #endif
        }
        .onChange(of: shell.windowRequests) {
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}

/// Connects the shared menu bar view to app actions (opening the window, quitting).
private struct MenuBarRoot: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContent(
            current: model.current,
            upcoming: model.upcoming,
            now: model.now,
            isSignedIn: model.isSignedIn,
            appName: appName,
            taskError: model.taskError,
            onSetTaskDone: model.setTaskDone,
            onOpen: {
                openWindow(id: "main")
                NSApp.activate()
            },
            onQuit: { NSApp.terminate(nil) }
        )
        .onAppear { model.refreshIfStale() }
    }
}
