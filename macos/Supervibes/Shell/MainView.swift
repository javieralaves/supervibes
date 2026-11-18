import AppKit
import SwiftUI

/// What the app's window shows beside the rail.
enum Route: Hashable {
    /// A web page; the web view keeps its own path.
    case web
    case goals
    /// A goal's own page. Native goal pages are being built; cards still open the web one.
    case goal(String)
    case settings
    case connections
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
                active: shell.activeRailItem,
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

                    switch shell.route {
                    case .web:
                        EmptyView()
                    case .goals:
                        ZStack {
                            Backdrop()
                            GoalsScreen(auth: auth, shell: shell)
                        }
                    case .goal(let id):
                        ZStack {
                            Backdrop()
                            GoalScreen(id: id, auth: auth, shell: shell)
                        }
                        .id(id)
                    case .settings:
                        ZStack {
                            Backdrop()
                            SettingsScreen(auth: auth)
                        }
                    case .connections:
                        ZStack {
                            Backdrop()
                            ConnectionsScreen(auth: auth)
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
        .overlayHost(shell.overlays)
    }
}

/// The home page with its goals, in the app's window. A goal's own page is still web.
private struct GoalsScreen: View {
    let shell: ShellModel
    @State private var model: GoalsModel
    @Environment(\.overlays) private var overlays

    init(auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: GoalsModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your goals", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                GoalsHome(
                    firstName: shell.account?.firstName ?? "there",
                    goals: model.goals,
                    today: model.today,
                    max: model.max,
                    error: model.error,
                    onOpen: { goal in
                        #if DEBUG
                        // Option-click previews the native goal page while it's being built.
                        if NSEvent.modifierFlags.contains(.option) { return shell.openNativeGoal(goal.id) }
                        #endif
                        shell.openGoal(goal.id)
                    },
                    onNew: newGoal
                )
            }
        }
        .task { await model.refresh() }
    }

    private func newGoal(_ input: GoalInput) {
        guard let overlays else { return }
        overlays.showDialog {
            GoalDialog(
                input: input,
                today: model.today,
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    model.create(saved)
                }
            )
        }
    }
}

/// A goal's own page with its data, in the app's window.
private struct GoalScreen: View {
    let shell: ShellModel
    @State private var model: GoalPageModel
    @Environment(\.overlays) private var overlays

    init(id: String, auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: GoalPageModel(id: id, auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView {
                    Label("This goal is gone", systemImage: "target")
                } description: {
                    Text("It may have been deleted.")
                } actions: {
                    Button("All goals") { shell.open(.goals) }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load this goal", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                if let detail = model.detail {
                    GoalPage(
                        detail: detail,
                        requestingRead: model.requestingRead,
                        readError: model.readError,
                        headerError: model.headerError,
                        weekState: model.weekState,
                        onBack: { shell.open(.goals) },
                        onUpdateStatus: model.updateStatus,
                        onEdit: { edit(detail.goal) },
                        onDelete: confirmDelete,
                        onSaveWeek: model.saveWeek
                    ) { EmptyView() }
                }
            }
        }
        .task { await model.refresh() }
        .onDisappear { model.stop() }
    }

    private func edit(_ goal: Goal) {
        guard let overlays else { return }
        let input = GoalInput(
            title: goal.title,
            description: goal.description ?? "",
            targetDate: goal.targetDate,
            icon: GoalPalette.iconName(goal.icon),
            color: GoalPalette.colorInfo(goal.color).key
        )
        overlays.showDialog {
            GoalDialog(
                input: input,
                mode: .edit,
                today: model.detail?.today ?? CalendarDay.today(),
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    model.save(saved)
                },
                onDelete: {
                    overlays.dismiss()
                    delete()
                }
            )
        }
    }

    private func confirmDelete() {
        guard let overlays else { return }
        overlays.showDialog {
            ConfirmDialog(
                title: "Delete this goal?",
                message: "Its sources and progress read will be removed too. Your connected apps aren’t affected.",
                confirmTitle: "Delete goal",
                onCancel: { overlays.dismiss() },
                onConfirm: {
                    overlays.dismiss()
                    delete()
                }
            )
        }
    }

    private func delete() {
        Task {
            if await model.delete() { shell.open(.goals) }
        }
    }
}

/// The Connections page with its data, in the app's window.
private struct ConnectionsScreen: View {
    @State private var model: ConnectionsModel

    init(auth: AuthModel) {
        _model = State(initialValue: ConnectionsModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your connections", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                ConnectionsPage(
                    items: model.items,
                    notice: model.notice,
                    busy: model.busy,
                    onConnect: model.connect,
                    onDisconnect: model.disconnect
                )
            }
        }
        .task { await model.refresh() }
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
