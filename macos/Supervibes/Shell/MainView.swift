import SwiftUI

/// What the app's window shows beside the rail.
enum Route: Hashable {
    /// A web page; the web view keeps its own path.
    case web
    case settings
}

/// The main window: sign-in while signed out; otherwise the native rail beside the app's window,
/// which shows either a web page or a native screen.
struct MainView: View {
    let auth: AuthModel
    @Bindable var shell: ShellModel

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut(let message):
                SignInView(message: message, onSignIn: auth.signIn)
            case .signingIn:
                SignInView(isSigningIn: true)
            case .signedIn:
                signedIn
            }
        }
        .background(Theme.shell)
        .ignoresSafeArea()
        .task(id: auth.isSignedIn) { await shell.signedInChanged() }
    }

    private var signedIn: some View {
        HStack(spacing: 0) {
            Rail(
                active: shell.route == .web ? RailItem.matching(path: shell.web.currentPath) : nil,
                account: shell.account,
                isMenuOpen: shell.isAccountMenuOpen,
                topInset: 28,
                onSelect: shell.open,
                onAccount: { shell.isAccountMenuOpen.toggle() }
            )
            .zIndex(1)

            AppWindowFrame {
                ZStack {
                    // Kept alive under native screens, so going back to a web page is instant.
                    WebContentView(model: shell.web)
                        .opacity(shell.route == .web ? 1 : 0)
                        .allowsHitTesting(shell.route == .web)

                    if shell.route == .settings {
                        ZStack {
                            Backdrop()
                            SettingsScreen(auth: auth)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if shell.isAccountMenuOpen {
                ZStack(alignment: .bottomLeading) {
                    // Clicking anywhere else closes the menu.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { shell.isAccountMenuOpen = false }
                    AccountMenu(
                        account: shell.account,
                        onSettings: { shell.openSettings() },
                        onSignOut: {
                            shell.isAccountMenuOpen = false
                            Task { await auth.signOut() }
                        }
                    )
                    .padding(.leading, Rail.width - 12 + 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomLeading)))
                }
            }
        }
        .animation(.easeOut(duration: 0.14), value: shell.isAccountMenuOpen)
    }
}

/// The Settings page with its data, in the app's window.
private struct SettingsScreen: View {
    @State private var model: SettingsModel

    init(auth: AuthModel) {
        _model = State(initialValue: SettingsModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your settings", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                SettingsPage(
                    settings: $model.settings,
                    status: model.status,
                    usage: model.usage,
                    onChange: model.changed
                )
            }
        }
        .task { await model.refresh() }
    }
}
