import AppKit
import SwiftUI

/// What the app's window shows beside the rail.
enum Route: Hashable {
    /// Life, the home page: the goals, then the areas they sit in.
    case life
    /// A goal's own page.
    case goal(String)
    /// An area's own page.
    case area(String)
    /// Starting a season, a full page per step.
    case startSeason
    /// A season's own page.
    case season(String)
    /// A quest's own page.
    case quest(String)
    case settings
    case connections
    /// Planning a day across goals.
    case plan
    case calendar
}

/// The main window: sign-in while signed out; otherwise the native rail beside the app's window,
/// which shows the screen for the route.
struct MainView: View {
    let auth: AuthModel
    @Bindable var shell: ShellModel
    let notifier: SessionNotifier
    let routineRunner: SessionRoutineRunner
    let eventFeed: EventFeed

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
                    case .life:
                        ZStack {
                            Backdrop()
                            LifeScreen(auth: auth, shell: shell)
                        }
                    case .area(let id):
                        ZStack {
                            Backdrop()
                            AreaScreen(id: id, auth: auth, shell: shell)
                        }
                        .id(id)
                    case .startSeason:
                        ZStack {
                            Backdrop()
                            SeasonSetupScreen(auth: auth, shell: shell)
                        }
                    case .season(let id):
                        ZStack {
                            Backdrop()
                            SeasonScreen(id: id, auth: auth, shell: shell)
                        }
                        .id(id)
                    case .quest(let id):
                        ZStack {
                            Backdrop()
                            QuestScreen(id: id, auth: auth, shell: shell)
                        }
                        .id(id)
                    case .goal(let id):
                        ZStack {
                            Backdrop()
                            GoalScreen(id: id, auth: auth, shell: shell)
                        }
                        .id(id)
                    case .settings:
                        ZStack {
                            Backdrop()
                            SettingsScreen(auth: auth, notifier: notifier, routineRunner: routineRunner, eventFeed: eventFeed)
                        }
                    case .connections:
                        ZStack {
                            Backdrop()
                            ConnectionsScreen(auth: auth)
                        }
                    case .plan:
                        PlanScreen(auth: auth, shell: shell)
                    case .calendar:
                        CalendarScreen(auth: auth, shell: shell, eventFeed: eventFeed)
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

/// Life, the home page with the goals and areas, in the app's window.
private struct LifeScreen: View {
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
                LifeHome(
                    firstName: shell.account?.firstName ?? "there",
                    goals: model.goals,
                    today: model.today,
                    weeks: model.weeks,
                    areas: model.areas,
                    max: model.max,
                    error: model.error,
                    onOpen: { shell.openGoal($0.id) },
                    onOpenArea: { shell.openArea($0.id) },
                    onNew: newGoal,
                    actions: GoalCardActions(
                        plan: { shell.openPlan(.goal($0.id)) },
                        setObjective: { shell.openGoal($0.id, then: .setObjective) },
                        updateStatus: { shell.openGoal($0.id, then: .updateStatus) },
                        edit: edit,
                        delete: confirmDelete
                    ),
                    areaActions: AreaEditActions(
                        create: { await model.createArea($0) },
                        update: { model.updateArea($0, $1) },
                        remove: { model.deleteArea($0) }
                    ),
                    areaError: model.areaError,
                    seasons: model.seasons,
                    onStartSeason: { shell.openStartSeason() },
                    onOpenSeason: { shell.openSeason($0.id) },
                    onOpenQuest: { shell.openQuest($0.id) }
                )
            }
        }
        .task { await model.refresh() }
    }

    private func edit(_ goal: Goal) {
        guard let overlays else { return }
        overlays.showDialog {
            GoalDialog(
                input: GoalInput(editing: goal),
                mode: .edit,
                today: model.today,
                areas: model.areas,
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    model.update(goal, saved)
                },
                onDelete: {
                    overlays.dismiss()
                    model.delete(goal)
                }
            )
        }
    }

    private func confirmDelete(_ goal: Goal) {
        guard let overlays else { return }
        overlays.showDialog {
            deleteGoalDialog(goal.kind, onCancel: { overlays.dismiss() }) {
                overlays.dismiss()
                model.delete(goal)
            }
        }
    }

    private func newGoal(_ input: GoalInput) {
        guard let overlays else { return }
        overlays.showDialog {
            GoalDialog(
                input: input,
                today: model.today,
                areas: model.areas,
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    model.create(saved)
                }
            )
        }
    }
}

/// A season's own page, with its data, in the app's window.
private struct SeasonScreen: View {
    let shell: ShellModel
    @State private var model: SeasonPageModel
    @Environment(\.overlays) private var overlays

    init(id: String, auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: SeasonPageModel(id: id, auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView {
                    Label("This season is gone", systemImage: "square.dashed")
                } actions: {
                    Button("Life") { shell.open(.life) }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load the season", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                if let data = model.data {
                    SeasonPage(
                        data: data,
                        reading: model.reading,
                        readError: model.readError,
                        actions: SeasonPageActions(
                            back: { shell.open(.life) },
                            openQuest: { shell.openQuest($0.id) },
                            openGoal: { shell.openGoal($0.id) },
                            openArea: { shell.openArea($0) },
                            read: { Task { await model.read() } },
                            editSeason: data.season.state == .active ? { edit(data.season) } : nil
                        )
                    )
                }
            }
        }
        .task { await model.refresh() }
    }

    private func edit(_ season: Season) {
        guard let overlays else { return }
        overlays.showDialog {
            SeasonDialog(
                input: SeasonInput(editing: season),
                lockStart: true,
                onCancel: { overlays.dismiss() },
                onSave: { input in
                    Task {
                        if await model.update(input) { overlays.dismiss() }
                    }
                }
            )
        }
    }
}

/// A quest's own page, with its data, in the app's window.
private struct QuestScreen: View {
    let shell: ShellModel
    @State private var model: QuestPageModel

    init(id: String, auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: QuestPageModel(id: id, auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView {
                    Label("This quest is gone", systemImage: "square.dashed")
                } actions: {
                    Button("Life") { shell.open(.life) }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load the quest", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                if let data = model.data {
                    QuestPage(
                        data: data,
                        reading: model.reading,
                        readError: model.readError,
                        actions: SeasonPageActions(
                            back: { shell.openSeason(data.season.id) },
                            openGoal: { shell.openGoal($0.id) },
                            openArea: { shell.openArea($0) },
                            read: { Task { await model.read() } },
                            toggleGoal: data.season.state == .active ? { goal in Task { await model.toggle(goal) } } : nil
                        )
                    )
                }
            }
        }
        .task { await model.refresh() }
    }
}

/// Starting a season, with its data, in the app's window.
private struct SeasonSetupScreen: View {
    let shell: ShellModel
    @State private var model: SeasonSetupModel
    @Environment(\.overlays) private var overlays

    init(auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: SeasonSetupModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't start a season", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Life") { shell.open(.life) }
                    Button("Try Again") { Task { await model.start() } }
                }
            case .loaded:
                if let state = model.state {
                    SeasonSetupView(state: state, actions: actions(state))
                }
            }
        }
        .task { await model.start() }
    }

    private func actions(_ state: SeasonSetupState) -> SeasonSetupActions {
        SeasonSetupActions(
            close: { shell.open(.life) },
            back: { model.back() },
            togglePick: { model.togglePick($0) },
            addCustom: { model.addCustom($0) },
            continueAreas: { Task { await model.continueAreas() } },
            read: { area, now, want in Task { await model.read(areaId: area, now: now, want: want) } },
            editQuest: { await model.editQuest($0, title: $1, fromText: $2) },
            next: { Task { await model.next() } },
            choose: { id, chosen in Task { await model.choose(id, chosen) } },
            toggleLink: { model.toggleLink(quest: $0, goal: $1) },
            addSuggestion: { model.addSuggestion(quest: $0, $1) },
            removeSuggestion: { model.removeSuggestion(quest: $0, $1) },
            findSuggestions: { id in Task { await model.findSuggestions(id) } },
            newGoal: { quest, kind in newGoal(quest: quest, kind: kind, state: state) },
            editSeason: { editSeason(state.season) },
            start: {
                Task {
                    if await model.startSeason() { shell.open(.life) }
                }
            }
        )
    }

    /// A project or practice of the person's own for a quest, started in its area.
    private func newGoal(quest id: String, kind: GoalKind, state: SeasonSetupState) {
        guard let overlays, let quest = state.season.quests.first(where: { $0.id == id }) else { return }
        var input = GoalInput(kind: kind)
        input.areaId = quest.areaId
        overlays.showDialog {
            GoalDialog(
                input: input,
                today: state.today,
                areas: state.areas,
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    Task { await model.createGoal(quest: id, saved) }
                }
            )
        }
    }

    private func editSeason(_ season: Season) {
        guard let overlays else { return }
        overlays.showDialog {
            SeasonDialog(
                input: SeasonInput(editing: season),
                onCancel: { overlays.dismiss() },
                onSave: { input in
                    Task {
                        if await model.updateSeason(input) { overlays.dismiss() }
                    }
                }
            )
        }
    }
}

/// Asks before deleting a project or a practice, saying what goes with it.
@MainActor private func deleteGoalDialog(_ kind: GoalKind, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) -> ConfirmDialog {
    ConfirmDialog(
        title: "Delete this \(kind.noun)?",
        message: kind == .practice
            ? "Its sessions go too: its blocks on the calendar and the ones you logged. Your connected apps aren’t affected."
            : "Its sources and progress read will be removed too. Your connected apps aren’t affected.",
        confirmTitle: "Delete \(kind.noun)",
        onCancel: onCancel,
        onConfirm: onConfirm
    )
}

/// An area's own page with its data, in the app's window.
private struct AreaScreen: View {
    let shell: ShellModel
    @State private var model: AreaPageModel
    @Environment(\.overlays) private var overlays

    init(id: String, auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: AreaPageModel(id: id, auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .gone:
                ContentUnavailableView {
                    Label("This area is gone", systemImage: "square.dashed")
                } description: {
                    Text("It may have been removed.")
                } actions: {
                    Button("Life") { shell.open(.life) }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load this area", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                if let detail = model.detail {
                    AreaPage(
                        detail: detail,
                        otherGoals: model.otherGoals,
                        error: model.error,
                        onBack: { shell.open(.life) },
                        onOpenGoal: { shell.openGoal($0.id) },
                        onOpenQuest: { shell.openQuest($0.id) },
                        actions: AreaPageActions(
                            save: { await model.save($0) },
                            remove: { Task { if await model.remove() { shell.open(.life) } } },
                            takeOut: { model.takeOut($0) },
                            moveIn: { model.moveIn($0) },
                            newGoal: { newGoal($0, today: detail.today) },
                            nameGap: { Task { await model.nameGap() } },
                            writeGap: { await model.writeGap($0) }
                        ),
                        reading: model.reading,
                        readError: model.readError,
                        onRead: { Task { await model.read() } },
                        namingGap: model.namingGap,
                        gapError: model.gapError
                    )
                }
            }
        }
        .task { await model.refresh() }
    }

    /// A new project or practice, started in this area.
    private func newGoal(_ kind: GoalKind, today: String) {
        guard let overlays else { return }
        overlays.showDialog {
            GoalDialog(
                input: GoalInput(kind: kind),
                today: today,
                onCancel: { overlays.dismiss() },
                onSave: { saved in
                    overlays.dismiss()
                    model.createGoal(saved)
                }
            )
        }
    }
}

/// A goal's own page with its data, in the app's window.
private struct GoalScreen: View {
    let shell: ShellModel
    @State private var model: GoalPageModel
    /// Opened from "Set this week's objective" on a goal card: the cursor goes in the objective.
    @State private var focusesObjective = false
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
                    Button("Life") { shell.open(.life) }
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
                if let detail = model.detail, detail.goal.isPractice {
                    PracticePage(
                        detail: detail,
                        headerError: model.headerError,
                        practiceError: model.practiceError,
                        onBack: { shell.open(.life) },
                        onOpenArea: { shell.openArea($0) },
                        areas: model.areas,
                        onSetArea: { areaId in Task { await model.setArea(areaId) } },
                        onNewArea: newArea,
                        onLogOne: model.logSession,
                        onPause: model.pause(until:),
                        onResume: model.resume,
                        onPlanDay: model.planSession,
                        onOpenCalendar: { shell.open(.calendar) },
                        onTickSession: model.tickSession,
                        onEdit: { edit(detail.goal) },
                        onDelete: confirmDelete
                    ) {
                        // Its sources feed its sessions' recaps; its activity holds them and any notes.
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
                } else if let detail = model.detail {
                    GoalPage(
                        detail: detail,
                        requestingRead: model.requestingRead,
                        readError: model.readError,
                        headerError: model.headerError,
                        weekState: model.weekState,
                        focusesObjective: focusesObjective,
                        onBack: { shell.open(.life) },
                        onOpenArea: { shell.openArea($0) },
                        areas: model.areas,
                        onSetArea: { areaId in Task { await model.setArea(areaId) } },
                        onNewArea: newArea,
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
                            actions: pageTaskActions
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
        .task {
            await model.refresh()
            // Asked for from a goal card's menu on the home page.
            guard let intent = shell.goalIntent else { return }
            shell.goalIntent = nil
            switch intent {
            case .updateStatus: if model.detail?.canRead == true { model.updateStatus() }
            case .setObjective: focusesObjective = true
            }
        }
        .onDisappear { model.stop() }
    }

    /// A new area from the goal's area menu, made and the goal placed in it.
    private func newArea() {
        guard let overlays else { return }
        overlays.showDialog {
            NewAreaDialog(onCancel: { overlays.dismiss() }) { input in
                let problem = await model.createArea(input)
                if problem == nil { overlays.dismiss() }
                return problem
            }
        }
    }

    /// The page's task actions, with "Plan tasks" opening the board on this goal.
    private var pageTaskActions: TaskActions {
        var actions = model.taskActions
        let id = model.id
        actions.plan = { [shell] in shell.openPlan(.goal(id), from: id) }
        return actions
    }

    private func edit(_ goal: Goal) {
        guard let overlays else { return }
        overlays.showDialog {
            GoalDialog(
                input: GoalInput(editing: goal),
                mode: .edit,
                today: model.detail?.today ?? CalendarDay.today(),
                areas: model.areas,
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
            deleteGoalDialog(model.detail?.goal.kind ?? .project, onCancel: { overlays.dismiss() }) {
                overlays.dismiss()
                delete()
            }
        }
    }

    private func delete() {
        Task {
            if await model.delete() { shell.open(.life) }
        }
    }
}

/// The calendar with its data, in the app's window.
private struct CalendarScreen: View {
    @State private var model: CalendarModel
    /// The task panel beside the day: closed unless opened, remembered.
    @AppStorage("sv-calendar-task-panel") private var showsTasks = false
    /// The count Next N days last showed, for the switch's button.
    @AppStorage(CalendarSpan.dayCountKey) private var dayCount = 3
    /// The week's overview: open unless closed, remembered.
    @AppStorage("sv-calendar-week-panel") private var weekPanel = "on"
    /// How tall an hour is in the day and in the week, as last pinched, remembered.
    @AppStorage("sv-calendar-day-hour") private var dayHour = Double(DayGrid.hour)
    @AppStorage("sv-calendar-week-hour") private var weekHour = Double(WeekGrid.hour)
    @State private var selectedId: String?
    @State private var width: CGFloat = 0
    /// Calendar import's events panel beside the days.
    @State private var showsEvents = false
    /// The event under the pointer in the events panel, previewed on the grid.
    @State private var eventPreview: EventPreview?
    /// The event just imported from the panel, whose row offers Undo.
    @State private var justImported: String?
    let shell: ShellModel
    let eventFeed: EventFeed

    /// The view showing: the one picked, though below the width the multi-day views need, the day.
    private var span: CalendarSpan { width >= 1024 ? model.window.span : .day }

    init(auth: AuthModel, shell: ShellModel, eventFeed: EventFeed) {
        self.shell = shell
        self.eventFeed = eventFeed
        // Opens on the view picked in Settings; the switch changes it for this visit.
        _model = State(initialValue: CalendarModel(auth: auth, span: .opening()))
    }

    private func setSpan(_ span: CalendarSpan) {
        if let n = span.dayCount { dayCount = n }
        model.setSpan(span)
    }

    // MARK: Calendar import

    /// The events button's action, while events can be listed; nil hides the button.
    private var eventsToggle: (() -> Void)? {
        guard eventFeed.isActive else { return nil }
        return { toggleEvents() }
    }

    private func toggleEvents() {
        showsEvents.toggle()
        // Opening it closes a block's panel, which would otherwise stand in its place.
        if showsEvents { selectedId = nil }
        eventPreview = nil
        justImported = nil
    }

    /// Imported blocks whose events changed since, by block. Reading them also lets baselines the
    /// blocks already match catch up, without asking.
    private var importChanges: [String: ImportChange] {
        guard eventFeed.isActive else { return [:] }
        return model.importChanges(events: eventFeed.events, isReading: eventFeed.isReading(calendarNamed:))
    }

    /// The changes as the events panel lists them, soonest block first.
    private func pendingChanges(_ changes: [String: ImportChange]) -> [PendingChange] {
        let clock = model.data.clock ?? .device
        return changes.compactMap { blockId, change -> PendingChange? in
            guard let block = model.data.blocks.first(where: { $0.id == blockId }), let source = block.source else { return nil }
            return PendingChange(
                block: block, change: change,
                copy: ImportChangeCopy(change, block: block, source: source, clock: clock, now: model.now),
                color: model.data.goal(block.goalId)?.color ?? "slate"
            )
        }
        .sorted { $0.block.startsAt < $1.block.startsAt }
    }

    /// "Events from Google · synced 9:40 AM".
    private var eventsHelp: String {
        guard let read = eventFeed.lastRead else { return "Events from Google" }
        return "Events from Google · synced \((model.data.clock ?? .device).format(minutes: CalendarDayMath.minutes(read)))"
    }

    /// The days shown, from today on (a week ahead in Day), with their events.
    private var eventDays: [EventDay] {
        let start = span.isMultiDay ? model.window.first : model.offset
        let count = span.isMultiDay ? span.count : 7
        let last = start + count - 1
        guard last >= 0 else { return [] }
        let byDay = Dictionary(grouping: eventFeed.events) { CalendarDayMath.dayOffset($0.start, from: model.now) }
        let en = Locale(identifier: "en_US")
        return (max(start, 0)...last).compactMap { day in
            guard let events = byDay[day], !events.isEmpty else { return nil }
            let label = DayView.dayLabel(day)
                ?? CalendarDayMath.midnight(day, from: model.now).formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(en))
            return EventDay(day: day, label: label, events: events)
        }
    }

    private var eventsPanel: some View {
        let goals = model.data.goals
        return EventsPanel(
            days: eventDays,
            goals: goals,
            imported: Dictionary(model.data.blocks.compactMap { block in block.source.map { ($0.key, block.goalId) } }, uniquingKeysWith: { first, _ in first }),
            defaultGoalId: eventFeed.settings.goal(among: goals.map(\.id)),
            lastRead: eventFeed.lastRead,
            clock: model.data.clock ?? .device,
            justImported: justImported,
            onHover: { event, goalId in
                eventPreview = event.map { event in
                    EventPreview(event: event, color: goals.first { $0.id == goalId }?.color ?? "slate", now: model.now)
                }
            },
            onImport: { event, goalId in
                model.importEvent(event, goalId: goalId, kind: eventFeed.settings.kind)
                justImported = event.key
                eventPreview = nil
            },
            onUndo: { event in
                if let block = model.importedBlock(event.key), !block.isPending { model.remove(block.id) }
                justImported = nil
            },
            onSync: eventFeed.syncNow,
            onClose: toggleEvents,
            changes: pendingChanges(importChanges),
            onTake: { model.takeChange($0.block.id, $0.change) },
            onKeep: { model.keepBlock($0.block.id, $0.change) },
            onTakeAll: {
                for (blockId, change) in importChanges { model.takeChange(blockId, change) }
            },
            onOpenBlock: { selectedId = $0 }
        )
    }

    /// ← → a page (a day, N days, a week); with ⌥, a day in the multi-day views too.
    private func arrow(_ direction: Int, _ modifiers: EventModifiers) -> KeyPress.Result {
        if !span.isMultiDay {
            model.step(direction)
        } else {
            model.scroll(direction * (modifiers.contains(.option) ? 1 : span.count))
        }
        return .handled
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
                    first: model.window.first,
                    firstRange: model.window.firstRange,
                    onScroll: model.scroll,
                    actions: CalendarActions(
                        create: model.create(day:start:end:goalId:title:kind:),
                        saveDetails: model.saveDetails(_:goalId:title:),
                        setReserved: model.setReserved,
                        setKind: model.setKind,
                        move: model.move(_:edge:delta:days:),
                        moveToTomorrow: model.moveToTomorrow,
                        toggleDone: model.toggleDone,
                        remove: model.remove,
                        place: model.place(_:day:start:minutes:),
                        plan: model.plan(_:day:),
                        reorder: model.reorder(_:day:to:),
                        markTaskDone: model.markTaskDone,
                        deleteTask: model.deleteTask,
                        changeTask: model.changeTask,
                        giveTime: { model.giveTime($0, minutes: $1, to: $2) },
                        defaultGoalId: { model.defaultGoalId },
                        openGoal: { shell.openGoal($0) },
                        practices: PracticeActions(
                            logToday: model.logPractice,
                            plan: { model.planPractice($0, day: $1) },
                            setDone: model.setPracticeSessionDone,
                            remove: model.removePracticeSession
                        )
                    ),
                    showsTasks: showsTasks,
                    onToggleTasks: { showsTasks.toggle() },
                    selectedId: $selectedId,
                    panel: BlockPanelActions(
                        setReserved: model.setReserved,
                        setMissed: model.setMissed,
                        setDescription: model.setDescription,
                        prepareAgenda: model.prepareAgenda(_:when:),
                        suggestFocus: model.suggestFocus(_:when:instead:),
                        prepareRecap: model.prepareRecap,
                        postRecap: model.postRecap(_:body:keep:markTaskDone:),
                        discardRecap: model.discardRecap,
                        setTaskDone: model.setTaskDone,
                        toggleDone: model.toggleDone,
                        openGoal: { shell.openGoal($0) },
                        takeChange: model.takeChange,
                        keepBlock: model.keepBlock
                    ),
                    span: span,
                    dayCount: CalendarSpan.dayCounts.contains(dayCount) ? dayCount : 3,
                    onSetSpan: setSpan,
                    showsOverview: weekPanel != "off",
                    onToggleOverview: { weekPanel = weekPanel == "off" ? "on" : "off" },
                    setObjective: model.setObjective(_:weekStart:_:),
                    dayHour: Binding(get: { CGFloat(dayHour) }, set: { dayHour = Double($0) }),
                    weekHour: Binding(get: { CGFloat(weekHour) }, set: { weekHour = Double($0) }),
                    eventsPanel: AnyView(eventsPanel),
                    showsEvents: showsEvents,
                    onToggleEvents: eventsToggle,
                    eventChanges: importChanges.count,
                    eventsHelp: eventsHelp,
                    eventPreview: eventPreview,
                    importChanges: importChanges
                )
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.escape) {
                    // Esc closes the block panel, then the events panel.
                    if selectedId != nil {
                        selectedId = nil
                        return .handled
                    }
                    guard showsEvents else { return .ignored }
                    toggleEvents()
                    return .handled
                }
                .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                    arrow(press.key == .leftArrow ? -1 : 1, press.modifiers)
                }
                .focusedSceneValue(\.calendarCommands, CalendarCommands(
                    span: span,
                    dayCount: CalendarSpan.dayCounts.contains(dayCount) ? dayCount : 3,
                    canShowDays: width >= 1024,
                    setSpan: setSpan,
                    today: model.goToToday
                ))
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { await model.start() }
        .onDisappear { model.stop() }
        // A notice was clicked: show its block once it's loaded.
        .onChange(of: PendingSelection(load: model.load, blockId: shell.pendingBlockId), initial: true) { _, pending in
            guard pending.load == .loaded, let id = pending.blockId else { return }
            shell.pendingBlockId = nil
            if model.show(id) {
                selectedId = id
            } else {
                // Added since the calendar last loaded.
                Task {
                    await model.refresh()
                    if model.show(id) { selectedId = id }
                }
            }
        }
    }
}

/// Plan on the rail: the planning board, on every goal, or on one when opened from its page or its
/// card's menu.
private struct PlanScreen: View {
    @State private var model: PlanBoardModel
    let shell: ShellModel

    init(auth: AuthModel, shell: ShellModel) {
        self.shell = shell
        _model = State(initialValue: PlanBoardModel(auth: auth))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your plan", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                if let data = model.data {
                    PlanningBoard(
                        data: data,
                        scope: scope(in: data),
                        actions: model.actions(for:),
                        fit: BoardFitActions(
                            move: { model.move($0, of: $1) },
                            protect: { model.protect($0, for: $1) },
                            give: { model.give($0, to: $1) }
                        ),
                        onScope: { shell.planScope = $0 },
                        onBack: shell.planOrigin.map { id in { shell.openGoal(id) } }
                    )
                    .overlay(alignment: .bottom) {
                        if let error = model.taskError {
                            Text(error).appText(.sm).foregroundStyle(Theme.danger)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.card, in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
                                .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
        .background { ZStack { Theme.background; Backdrop() } }
        .task { await model.refresh() }
    }

    /// The goal asked for, or All goals when it's gone.
    private func scope(in data: BoardData) -> BoardScope {
        if case .goal(let id) = shell.planScope, data.goal(id) == nil { return .all }
        return shell.planScope
    }
}

/// What the calendar waits on to select a block from a notice.
private struct PendingSelection: Equatable {
    let load: CalendarModel.Load
    let blockId: String?
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
    /// What the Calendar opens on, kept on this Mac.
    @State private var calendarSpan = CalendarSpan.opening()
    let notifier: SessionNotifier
    let routineRunner: SessionRoutineRunner
    let eventFeed: EventFeed

    init(auth: AuthModel, notifier: SessionNotifier, routineRunner: SessionRoutineRunner, eventFeed: EventFeed) {
        _model = State(initialValue: SettingsModel(auth: auth))
        self.notifier = notifier
        self.routineRunner = routineRunner
        self.eventFeed = eventFeed
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
                    calendar: CalendarViewCard(span: calendarSpan) { span in
                        calendarSpan = span
                        CalendarSpan.setOpening(span)
                    },
                    events: CalendarEventsCard(
                        settings: eventFeed.settings,
                        access: eventFeed.access,
                        calendars: eventFeed.calendars,
                        goals: model.goals,
                        onChange: eventFeed.change,
                        onAllow: eventFeed.requestAccess,
                        onOpenSystemSettings: eventFeed.openSystemSettings
                    ),
                    notices: NoticesCard(
                        settings: notifier.settings,
                        permission: notifier.permission,
                        onChange: notifier.change,
                        onOpenSystemSettings: notifier.openSystemSettings
                    ),
                    routine: SessionRoutineCard(
                        routine: routineRunner.routine,
                        shortcuts: routineRunner.shortcuts,
                        openApps: routineRunner.openApps,
                        onChange: routineRunner.change,
                        onAddFocusShortcut: routineRunner.addFocusShortcut,
                        onChooseApp: routineRunner.chooseApp,
                        onOpenShortcuts: routineRunner.openShortcutsApp,
                        onOpenFocusSettings: routineRunner.openFocusSettings
                    ),
                    onChange: model.changed
                )
            }
        }
        .task { await model.refresh() }
        .task { routineRunner.refreshOptions() }
    }
}
