import SwiftUI

@main
struct SupervibesApp: App {
    @State private var model = AppModel()
    @State private var auth = AuthModel(baseURL: AppConfig.baseURL)

    init() {
        Log.app.info("Launched, talking to \(AppConfig.baseURL.absoluteString, privacy: .public)")
    }

    var body: some Scene {
        // The main window. For now it hosts the web app; screens move to SwiftUI one at a time.
        Window("Supervibes", id: "main") {
            WebShellView(auth: auth)
                .frame(minWidth: 900, minHeight: 600)
                .task { await auth.restore() }        }
        .defaultSize(width: 1280, height: 820)
        .commands {
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

/// Connects the shared menu bar view to app actions (opening the window, quitting).
private struct MenuBarRoot: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContent(
            current: model.current,
            upcoming: model.upcoming,
            now: model.now,
            onOpen: {
                openWindow(id: "main")
                NSApp.activate()
            },
            onQuit: { NSApp.terminate(nil) }
        )
    }
}
