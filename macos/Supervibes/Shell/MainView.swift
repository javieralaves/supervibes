import AppKit
import SwiftUI

/// What the app's window shows beside the rail.
enum Route: Hashable {
    case goals
    /// A goal's own page.
    case goal(String)
    case settings
    case connections
    case calendar
}

/// The main window: sign-in while signed out; otherwise the native rail beside the app's window,
/// which shows the screen for the route.
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
                onSelect: { shell.open($0) },
                onAccount: { shell.isAccountMenuOpen.toggle() }
            )
            .zIndex(1)

            AppWindowFrame {
                ZStack {
                    switch shell.route {
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
                    case .calendar:
                        CalendarScreen(auth: auth, shell: shell)
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

/// The home page with its goals, in the app's window.
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
                    onOpen: { shell.openGoal($0.id) },
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
                        onSaveWeek: model.saveWeek,
                        onBackgroundTap: model.backgroundTapped
                    ) {
                        TasksSection(
                            tasks: detail.tasks,
                            suggestions: detail.suggestions,
                            hasRead: detail.read != nil,
                            reading: detail.readPending || model.requestingRead,
                            clock: detail.clock ?? .device,
                            today: detail.today,
                            error: model.taskError,
                            closeSignal: model.closeSignal,
                            actions: model.taskActions
                        )
                        SourcesSection(
                            sources: detail.sources,
                            options: detail.connectionOptions,
                            goal: detail.goal,
                            actions: SourceActions(
                                save: { await model.saveSource($0, $1, $2) },
                                delete: { model.deleteSource($0) },
                                openConnections: { shell.open(.connections) }
                            )
                        )
                        NotesSection(
                            notes: detail.notes,
                            author: detail.author,
                            clock: detail.clock ?? .device,
                            error: model.noteError,
                            actions: model.noteActions
                        )
                    }
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

/// The calendar with its data, in the app's window.
private struct CalendarScreen: View {
    @State private var model: CalendarModel
    /// The task panel beside the day: closed unless opened, remembered.
    @AppStorage("sv-calendar-task-panel") private var showsTasks = false
    /// Day or week, remembered; the week needs a wide window, and below that it's always the day.
    @AppStorage("sv-calendar-view") private var view = "day"
    /// The week's overview: open unless closed, remembered.
    @AppStorage("sv-calendar-week-panel") private var weekPanel = "on"
    @State private var selectedId: String?
    @State private var width: CGFloat = 0
    let shell: ShellModel

    private var isWeek: Bool { view == "week" && width >= 1024 }

    init(auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: CalendarModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your calendar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                DayView(
                    data: model.data,
                    offset: model.offset,
                    now: model.now,
                    error: model.error,
                    onStep: model.step,
                    onToday: model.goToToday,
                    actions: CalendarActions(
                        create: model.create(day:start:end:goalId:title:),
                        saveDetails: model.saveDetails(_:goalId:title:),
                        move: model.move(_:edge:delta:days:),
                        moveToTomorrow: model.moveToTomorrow,
                        toggleDone: model.toggleDone,
                        remove: model.remove,
                        place: model.place(_:day:start:minutes:),
                        plan: model.plan(_:day:),
                        defaultGoalId: { model.defaultGoalId }
                    ),
                    showsTasks: showsTasks,
                    onToggleTasks: { showsTasks.toggle() },
                    selectedId: $selectedId,
                    panel: BlockPanelActions(
                        setDescription: model.setDescription,
                        prepareAgenda: model.prepareAgenda(_:when:),
                        prepareRecap: model.prepareRecap,
                        postRecap: model.postRecap(_:body:keep:markTaskDone:),
                        discardRecap: model.discardRecap,
                        setTaskDone: model.setTaskDone,
                        toggleDone: model.toggleDone,
                        openGoal: { shell.openGoal($0) }
                    ),
                    isWeek: isWeek,
                    onSetWeek: { view = $0 ? "week" : "day" },
                    showsOverview: weekPanel != "off",
                    onToggleOverview: { weekPanel = weekPanel == "off" ? "on" : "off" },
                    setObjective: model.setObjective(_:weekStart:_:)
                )
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.escape) {
                    // Esc closes the block panel.
                    guard selectedId != nil else { return .ignored }
                    selectedId = nil
                    return .handled
                }
                .onKeyPress(.leftArrow) { model.step(isWeek ? -7 : -1); return .handled }
                .onKeyPress(.rightArrow) { model.step(isWeek ? 7 : 1); return .handled }
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await model.start() }
        .onDisappear { model.stop() }
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
