import SwiftUI

@main
struct SupervibesApp: App {
    @State private var auth: AuthModel
    @State private var model: AppModel
    @State private var shell: ShellModel

    init() {
        Log.app.info("Launched, talking to \(AppConfig.baseURL.absoluteString, privacy: .public)")
        let auth = AuthModel(baseURL: AppConfig.baseURL)
        _auth = State(initialValue: auth)
        _model = State(initialValue: AppModel(auth: auth))
        _shell = State(initialValue: ShellModel(auth: auth))
    }

    var body: some Scene {
        // The main window: the native rail beside the app's window, which shows web pages and,
        // one by one, native screens in their place.
        Window("Supervibes", id: "main") {
            MainView(auth: auth, shell: shell)
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
            model.menuBarTitle
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
            onOpen: {
                openWindow(id: "main")
                NSApp.activate()
            },
            onQuit: { NSApp.terminate(nil) }
        )
    }
}
