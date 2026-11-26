import SwiftUI

/*
 * Planning a goal's tasks on a board, in one row of lanes that scrolls sideways: Unplanned, today,
 * tomorrow and the day after, then this week and next week. Drag a card into a lane to plan it
 * there: a line between the cards shows where it'll land, and the card fades where it was. Its
 * right-click menu plans it without dragging. Click a card to edit it in place, as on the goal page: the cards are the same
 * rows. Each lane but Unplanned weighs its time planned against the time protected for the goal,
 * as a ring; hovering it shows the detail. Show completed lists what's been finished this week.
 * Layers: the page, then the lanes a step darker, then the cards, white.
 * Designed in supervibes-design ("Plan tasks, reworked", components/studio/frames/task-planning.tsx).
 */

/// Where a task sits on the board.
enum BoardColumn: Hashable, Sendable {
    case unplanned
    case day(String)
    case thisWeek, nextWeek

    /// How many days the board shows, starting today.
    static let dayCount = 3

    /// The board's columns, left to right.
    static func all(today: String) -> [BoardColumn] {
        [.unplanned] + (0..<dayCount).map { .day(CalendarDay.addDays(today, $0)) } + [.thisWeek, .nextWeek]
    }

    /// The column an open task sits in: a day it's planned for in the next three, or else its week
    /// (a day further out sits in its week's column, showing its day), or Unplanned.
    static func of(_ task: TaskItem, today: String) -> BoardColumn {
        let thisWeek = CalendarDay.weekStart(today)
        if let day = task.plannedFor, day >= today {
            if CalendarDay.daysUntil(day, today: today) < dayCount { return .day(day) }
            switch CalendarDay.weekStart(day) {
            case thisWeek: return .thisWeek
            case CalendarDay.addDays(thisWeek, 7): return .nextWeek
            default: return .unplanned
            }
        }
        return switch task.horizon(today: today).group {
        case .day, .thisWeek: .thisWeek
        case .nextWeek: .nextWeek
        case .later: .unplanned
        }
    }

    /// Where a task finished this week shows: on its day if that's on the board, else this week.
    static func ofDone(_ task: TaskItem, today: String) -> BoardColumn {
        if let day = task.plannedFor, day >= today, CalendarDay.daysUntil(day, today: today) < dayCount { return .day(day) }
        return .thisWeek
    }

    /// The Monday of the week an open task is meant for, if any: the week of a day it's planned
    /// for, or its week (a carried-over one counts as this week).
    static func week(of task: TaskItem, today: String) -> String? {
        if let day = task.plannedFor, day >= today { return CalendarDay.weekStart(day) }
        let thisWeek = CalendarDay.weekStart(today)
        return switch task.horizon(today: today).group {
        case .day, .thisWeek: thisWeek
        case .nextWeek: CalendarDay.addDays(thisWeek, 7)
        case .later: nil
        }
    }

    /// What dropping or adding a task here plans it for. A week or Unplanned drops its day.
    func patch(today: String) -> TaskPatch {
        let thisWeek = CalendarDay.weekStart(today)
        return switch self {
        case .day(let day): TaskPatch(plannedFor: day)
        case .thisWeek: TaskPatch(plannedFor: "", plannedWeek: thisWeek)
        case .nextWeek: TaskPatch(plannedFor: "", plannedWeek: CalendarDay.addDays(thisWeek, 7))
        case .unplanned: TaskPatch(plannedFor: "", plannedWeek: "")
        }
    }

    /// Whether a task's plan pill here would only repeat the column's title: a day column's own
    /// day, or a week column's week without a day.
    func repeatsPlan(of task: TaskItem) -> Bool {
        switch self {
        case .unplanned: false
        case .day(let day): task.plannedFor == day
        case .thisWeek, .nextWeek: task.plannedFor == nil
        }
    }
}

struct PlanningBoard: View {
    let data: BoardData
    /// Every goal, a row each, or one goal's lanes.
    var scope: BoardScope = .all
    /// What a goal's cards and lanes can do.
    var actions: (String) -> TaskActions = { _ in TaskActions() }
    /// What an over day's ring offers, to make it fit.
    var fit = BoardFitActions()
    /// For "Today 2:00 PM" and the protected time gone by; fixed in snapshots.
    var now = Date()
    /// Opens with this task open, for snapshot tests.
    var initiallyOpen: String?
    /// Opens with the pointer over this column, for previews and snapshot tests.
    var initiallyHovered: BoardColumn?
    /// Opens with this column's capacity showing, for previews and snapshot tests.
    var initialCapacity: BoardColumn?
    /// On All goals, the rows open at first, showing their cards.
    var initiallyExpanded: Set<String> = []
    /// Opens with the pointer over this suggested task, for snapshot tests.
    var initiallyHoveredFiller: String?
    /// Opens with a card being dragged over a lane, for previews and snapshot tests.
    var initialDrop: BoardDrop?
    /// Switches between All goals and a goal, from the title.
    var onScope: (BoardScope) -> Void = { _ in }
    /// "Back", when the board was opened from a goal's page.
    var onBack: (() -> Void)?

    @State private var draft: TaskDraft?
    @State private var expanded: Set<String>
    @State private var headerHeight: CGFloat = 0
    /// All goals: the column heads' row, measured so an open row can run to the window's bottom.
    @State private var columnHeadsHeight: CGFloat = 0
    @State private var titleAnchor = CGRect.zero
    /// The card being dragged, from its drag's start to its end.
    @State private var dragging: String?
    @AppStorage("planningBoard.showsCompleted") private var showsCompleted = false
    @Environment(\.overlays) private var overlays

    init(
        data: BoardData, scope: BoardScope = .all, actions: @escaping (String) -> TaskActions = { _ in TaskActions() },
        fit: BoardFitActions = BoardFitActions(), now: Date = Date(), initiallyOpen: String? = nil, initiallyHovered: BoardColumn? = nil,
        initialCapacity: BoardColumn? = nil, initiallyExpanded: Set<String> = [], initiallyHoveredFiller: String? = nil,
        initialDrop: BoardDrop? = nil, onScope: @escaping (BoardScope) -> Void = { _ in }, onBack: (() -> Void)? = nil
    ) {
        self.data = data
        self.scope = scope
        self.actions = actions
        self.fit = fit
        self.now = now
        self.initiallyOpen = initiallyOpen
        self.initiallyHovered = initiallyHovered
        self.initialCapacity = initialCapacity
        self.initiallyExpanded = initiallyExpanded
        self.initiallyHoveredFiller = initiallyHoveredFiller
        self.initialDrop = initialDrop
        self.onScope = onScope
        self.onBack = onBack
        _expanded = State(initialValue: initiallyExpanded)
        _dragging = State(initialValue: initialDrop?.task)
    }

    private var today: String { data.today }
    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }
    private var clock: Clock { data.clock ?? .device }
    /// The goal shown on its own, if one is.
    private var single: BoardGoal? {
        if case .goal(let id) = scope { return data.goal(id) }
        return nil
    }

    private static let columnWidth: CGFloat = 320
    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 24
    private static let top: CGFloat = 40
    private static let headerGap: CGFloat = 28
    private static let bottom: CGFloat = 8
    /// All goals: the goals' column, the gaps between rows and cells, and the least an open row's
    /// lanes are tall.
    private static let labelWidth: CGFloat = 232
    private static let rowGap: CGFloat = 8
    private static let minOpenRowHeight: CGFloat = 360

    var body: some View {
        let columns = BoardColumn.all(today: today)
        GeometryReader { geo in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.headerGap) {
                    header
                        .padding(.horizontal, Self.margin)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    if let goal = single {
                        // The lanes run to the bottom of the window, whatever they hold.
                        let laneHeight = max(240, geo.size.height - Self.top - headerHeight - Self.headerGap - Self.bottom)
                        lanes(goal, columns: columns, height: laneHeight)
                    } else {
                        // An open row's lanes run to the bottom of the window too; the goals below
                        // it scroll into view.
                        let openHeight = max(
                            Self.minOpenRowHeight,
                            geo.size.height - Self.top - headerHeight - Self.headerGap - columnHeadsHeight - Self.rowGap - Self.bottom
                        )
                        allGoals(columns: columns, openHeight: openHeight)
                    }
                }
                .padding(.top, Self.top)
                .padding(.bottom, single == nil ? 40 : Self.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A click outside the cards closes an open one.
                .background(Color.clear.contentShape(.rect).onTapGesture(perform: closeTask))
            }
            .scrollContentBackground(.hidden)
            // As on the goal page: soft, or macOS 26 draws a bar under the hidden title bar.
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .environment(\.shortHours, true)
        .onAppear {
            if let id = initiallyOpen, let task = data.goals.lazy.flatMap(\.tasks).first(where: { $0.id == id }) { draft = TaskDraft(task) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack { BoardBackLink(action: onBack).padding(.bottom, 20) }
            HStack(alignment: .center, spacing: 16) {
                if let goal = single {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .sm)
                } else {
                    Icon.target.image(size: 20)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 40, height: 40)
                        .background(Theme.foreground(0.08), in: .rect(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 2) {
                    ScopeTitle(title: single?.title ?? "All projects", anchor: $titleAnchor, action: showScopeMenu)
                    Text(subtitle)
                        .font(.app(14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(minHeight: 20)
                }
                Spacer(minLength: 24)
                ShowCompletedButton(isOn: $showsCompleted)
            }
        }
    }

    private var subtitle: String {
        if let goal = single { return goal.objective.map { "This week: \($0)" } ?? "No objective for this week yet." }
        let withTime = data.goals.filter { goal in goal.protectedBlocks.contains { CalendarDay.weekStart(CalendarDay.today($0.start)) == thisWeek } }.count
        switch withTime {
        case 0: return "No project has session time this week yet."
        case 1: return "1 project with session time this week."
        default: return "\(withTime) projects with session time this week."
        }
    }

    /// The title is the switch: All goals, or any one goal, each with its week's ring.
    private func showScopeMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: titleAnchor, owner: "board-scope", alignLeading: true) {
            MenuPanel(width: 300) {
                ScopeMenuRow(isChecked: scope == .all, action: { pick(.all) }) {
                    Icon.target.image(size: 14)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 24, height: 24)
                        .background(Theme.foreground(0.08), in: .rect(cornerRadius: 6))
                    Text("All projects").appText(.sm, .medium).foregroundStyle(Theme.foreground)
                }
                MenuSeparator()
                ForEach(data.goals) { goal in
                    ScopeMenuRow(isChecked: scope == .goal(goal.id), action: { pick(.goal(goal.id)) }) {
                        GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                        Text(goal.title).appText(.sm).foregroundStyle(Theme.foreground).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        let week = capacity(.thisWeek, of: goal)
                        if let week, week.protected > 0 {
                            CapacityRing(planned: week.planned, protected: week.protected, color: goal.color, size: 14)
                        }
                    }
                }
            }
        }
    }

    private func pick(_ next: BoardScope) {
        overlays?.dismiss()
        closeTask()
        onScope(next)
    }

    // MARK: One goal

    private func lanes(_ goal: BoardGoal, columns: [BoardColumn], height: CGFloat) -> some View {
        let open = Dictionary(grouping: goal.tasks) { BoardColumn.of($0, today: today) }
        let done = Dictionary(grouping: goal.done) { BoardColumn.ofDone($0, today: today) }
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(columns, id: \.self) { column in
                    self.column(column, of: goal, open: open[column] ?? [], done: showsCompleted ? done[column] ?? [] : [], compact: false)
                        .frame(width: Self.columnWidth, height: height)
                }
            }
            .padding(.horizontal, Self.margin)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: All goals

    /// The columns' headings, each saying its tasks and time across every goal, then a row per
    /// goal: folded to a line per cell, or open to its cards. Columns are as wide as a goal's own
    /// board's lanes, and the row runs off the right edge and scrolls.
    private func allGoals(columns: [BoardColumn], openHeight: CGFloat) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: Self.rowGap) {
                HStack(alignment: .bottom, spacing: Self.rowGap) {
                    Text("Project").appText(.xs, .medium).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    ForEach(columns, id: \.self) { column in
                        ColumnHead(title: title(column), subtitle: subtitle(column), tasks: totalTasks(column), time: totalTime(column))
                            .frame(width: Self.columnWidth, alignment: .leading)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeadsHeight = $0 }
                ForEach(data.goals) { goal in
                    row(goal, columns: columns, openHeight: openHeight)
                }
            }
            .padding(.horizontal, Self.margin)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ goal: BoardGoal, columns: [BoardColumn], openHeight: CGFloat) -> some View {
        let isOpen = expanded.contains(goal.id)
        let open = Dictionary(grouping: goal.tasks) { BoardColumn.of($0, today: today) }
        let done = Dictionary(grouping: goal.done) { BoardColumn.ofDone($0, today: today) }
        return HStack(alignment: .top, spacing: Self.rowGap) {
            GoalRowLabel(goal: goal, isOpen: isOpen) { toggleRow(goal.id) }
                .frame(width: Self.labelWidth, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                if isOpen {
                    self.column(column, of: goal, open: open[column] ?? [], done: showsCompleted ? done[column] ?? [] : [], compact: true)
                        .frame(width: Self.columnWidth, height: openHeight)
                } else {
                    let meant = meant(for: column, of: goal, open: open)
                    CellSummary(tasks: meant.count, time: time(column, of: goal, meant: meant), color: goal.color) { toggleRow(goal.id) }
                        .frame(width: Self.columnWidth)
                }
            }
        }
    }

    /// What a folded cell counts, as its ring does: a week's every task meant for it (its days on
    /// the board too), otherwise the column's own.
    private func meant(for column: BoardColumn, of goal: BoardGoal, open: [BoardColumn: [TaskItem]]) -> [TaskItem] {
        switch column {
        case .thisWeek: goal.tasks.filter { BoardColumn.week(of: $0, today: today) == thisWeek }
        case .nextWeek: goal.tasks.filter { BoardColumn.week(of: $0, today: today) == nextWeek }
        default: open[column] ?? []
        }
    }

    private func toggleRow(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// What a folded cell says of its time: planned against protected, Unplanned's total, planned
    /// with no time, or nothing.
    private func time(_ column: BoardColumn, of goal: BoardGoal, meant: [TaskItem]) -> PlanTime {
        guard let capacity = capacity(column, of: goal) else {
            return meant.isEmpty ? .none : .total(meant.reduce(0) { $0 + $1.minutes })
        }
        if capacity.protected > 0 { return .weighed(planned: capacity.planned, protected: capacity.protected) }
        return meant.isEmpty ? .none : .noTime(planned: capacity.planned)
    }

    /// The open tasks every goal has in a column, as its folded cells count them.
    private func totalTasks(_ column: BoardColumn) -> Int {
        data.goals.reduce(0) { sum, goal in
            sum + meant(for: column, of: goal, open: Dictionary(grouping: goal.tasks) { BoardColumn.of($0, today: today) }).count
        }
    }

    /// A column's time across every goal: Unplanned's total, or each goal's planned against its
    /// protected, added up (see PlanTime.across).
    private func totalTime(_ column: BoardColumn) -> PlanTime {
        guard column != .unplanned else {
            let minutes = data.goals.reduce(0) { sum, goal in
                sum + goal.tasks.filter { BoardColumn.of($0, today: today) == .unplanned }.reduce(0) { $0 + $1.minutes }
            }
            return totalTasks(column) == 0 ? .none : .total(minutes)
        }
        return .across(data.goals.compactMap { capacity(column, of: $0) }, hasTasks: totalTasks(column) > 0)
    }

    // MARK: Columns

    private func column(_ column: BoardColumn, of goal: BoardGoal, open: [TaskItem], done: [TaskItem], compact: Bool) -> some View {
        let actions = actions(goal.id)
        let label = compact ? "\(capacityLabel(column)) · \(goal.title)" : capacityLabel(column)
        return BoardColumnView(
            title: title(column),
            subtitle: subtitle(column),
            showsTitle: !compact,
            open: open,
            done: done,
            color: goal.color,
            capacity: capacity(column, of: goal),
            capacityLabel: label,
            fitPanel: fitPanel(column, of: goal),
            fill: fill(column, of: goal),
            fillAction: "Plan for \(relativeName(column))",
            hoveredFiller: initiallyHoveredFiller,
            fillSource: { title(BoardColumn.of($0, today: today)) },
            onFill: { task in actions.place(task, column.patch(today: today), nil) },
            clock: clock,
            emptyDetail: emptyDetail(column, of: goal),
            emptyTitle: "Nothing planned for \(relativeName(column))",
            addPlaceholder: addPlaceholder(column),
            initiallyHovered: initiallyHovered == column && !compact,
            showsCapacityInitially: initialCapacity == column && (!compact || initiallyExpanded.first == goal.id),
            onAdd: { actions.add($0, column.patch(today: today)) },
            onDrop: { id, before in drop(id, on: column, of: goal, before: before) },
            onToggleDone: actions.toggle,
            dragging: dragging,
            accepts: { id in goal.tasks.contains { $0.id == id } },
            onDragging: { dragging = $0 },
            initialInsertion: initialDrop.flatMap { drop in
                drop.column == column && goal.tasks.contains { $0.id == drop.task } ? BoardInsertion(before: drop.before) : nil
            }
        ) { task in
            card(task, in: column, actions: actions)
        }
    }

    @ViewBuilder private func card(_ task: TaskItem, in column: BoardColumn, actions: TaskActions) -> some View {
        if let draft, draft.id == task.id {
            OpenTaskRow(
                task: task,
                draft: Binding(get: { self.draft ?? draft }, set: { self.draft = $0 }),
                today: today,
                actions: actions,
                onClose: closeTask
            )
            .modifier(CardStyle(isOpen: true))
        } else {
            GoalTaskRow(
                task: task,
                horizon: task.horizon(today: today),
                clock: clock,
                today: today,
                thisWeek: thisWeek,
                nextWeek: nextWeek,
                now: now,
                isDragging: false,
                isReorderable: false,
                actions: actions,
                showsNotes: false,
                showsPlan: !column.repeatsPlan(of: task),
                onOpen: { open(task) }
            )
            .modifier(CardStyle(isOpen: false))
            .modifier(BoardDragSource(task: task) { dragging = $0 })
            // Faded where it was while it's dragged, so the line shows where it's going instead.
            .opacity(dragging == task.id ? 0.4 : 1)
            .animation(.easeOut(duration: 0.12), value: dragging == task.id)
        }
    }

    private func title(_ column: BoardColumn) -> String {
        switch column {
        case .unplanned: "Unplanned"
        case .day(let day): CalendarDay.relativeLabel(day, today: today)
        case .thisWeek: "This week"
        case .nextWeek: "Next week"
        }
    }

    private func subtitle(_ column: BoardColumn) -> String? {
        switch column {
        case .unplanned: nil
        case .day(let day): CalendarDay.format(day, today: today)
        case .thisWeek: CalendarDay.formatWeek(thisWeek)
        case .nextWeek: CalendarDay.formatWeek(nextWeek)
        }
    }

    /// "today", "tomorrow", "Sat", "this week".
    private func relativeName(_ column: BoardColumn) -> String {
        switch column {
        case .day: title(column).lowercasedIfRelative
        default: title(column).lowercased()
        }
    }

    private func addPlaceholder(_ column: BoardColumn) -> String {
        switch column {
        case .unplanned: "Add a task"
        case .day: "Add for \(relativeName(column))"
        case .thisWeek: "Add to this week"
        case .nextWeek: "Add to next week"
        }
    }

    // MARK: Filling a day

    /// A day's time left and the tasks that would fit it; nothing for weeks and Unplanned.
    private func fill(_ column: BoardColumn, of goal: BoardGoal) -> (room: Int, tasks: [TaskItem]) {
        guard case .day(let day) = column else { return (0, []) }
        return Fit.fillers(goal, day: day, today: today, now: now)
    }

    // MARK: Making a day fit

    /// What clicking a day's ring opens when more is planned than there's time for, today or later.
    private func fitPanel(_ column: BoardColumn, of goal: BoardGoal) -> (() -> AnyView)? {
        guard case .day(let day) = column, day >= today, let capacity = capacity(column, of: goal), capacity.planned > capacity.protected else {
            return nil
        }
        let dayName = title(column)
        return { [data, now, clock, fit] in
            AnyView(MakeItFitPanel(goal: goal, day: day, dayName: dayName, in: data, now: now, clock: clock, actions: fit))
        }
    }

    // MARK: Capacity

    /// A goal's time planned against its time protected: a day counts its own day, a week the
    /// whole week (its days on the board included).
    private func capacity(_ column: BoardColumn, of goal: BoardGoal) -> Capacity? {
        let blocks = goal.protectedBlocks
        switch column {
        case .unplanned:
            return nil
        case .day(let day):
            let open = goal.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }
            return .day(day, open: open, blocks: blocks, now: now)
        case .thisWeek, .nextWeek:
            let week = column == .thisWeek ? thisWeek : nextWeek
            let open = goal.tasks.filter { BoardColumn.week(of: $0, today: today) == week }.reduce(0) { $0 + $1.minutes }
            return .week(week, open: open, blocks: blocks, now: now)
        }
    }

    /// "Tomorrow · Thu, Nov 19", "Fri, Nov 20", "This week · Nov 16–22".
    private func capacityLabel(_ column: BoardColumn) -> String {
        switch column {
        case .unplanned:
            return "Unplanned"
        case .day(let day):
            let weekday = CalendarDay.date(day).map {
                $0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated))
            } ?? ""
            let date = "\(weekday), \(CalendarDay.format(day, today: today))"
            let relative = CalendarDay.relativeLabel(day, today: today)
            return relative == "Today" || relative == "Tomorrow" ? "\(relative) · \(date)" : date
        case .thisWeek, .nextWeek:
            return "\(title(column)) · \(subtitle(column) ?? "")"
        }
    }

    /// What an empty lane says under "Nothing planned for …": the protected time still ahead on a
    /// day, or how to plan into a week.
    private func emptyDetail(_ column: BoardColumn, of goal: BoardGoal) -> String {
        guard case .day = column, let capacity = capacity(column, of: goal) else { return "Drag a task here to plan it" }
        let ahead = capacity.ahead
        if ahead.count == 1, let block = ahead.first {
            return "\(BoardDuration.text(block.minutes)) protected, \(clock.range(block.start, block.end))"
        }
        if !ahead.isEmpty { return "\(BoardDuration.text(ahead.reduce(0) { $0 + $1.minutes })) protected still ahead" }
        return capacity.blocks.isEmpty ? "No time protected" : "Its protected time has gone by"
    }

    // MARK: Editing

    /// The open task and the goal it belongs to.
    private func located(_ id: String) -> (task: TaskItem, goal: BoardGoal)? {
        for goal in data.goals {
            if let task = goal.tasks.first(where: { $0.id == id }) { return (task, goal) }
        }
        return nil
    }

    private func open(_ task: TaskItem) {
        guard !task.isPending else { return }
        if let draft, draft.id != task.id { commit(draft) }
        draft = TaskDraft(task)
    }

    private func closeTask() {
        guard let current = draft else { return }
        commit(current)
        draft = nil
    }

    private func commit(_ draft: TaskDraft) {
        guard let (task, goal) = located(draft.id), let patch = draft.patch(for: task) else { return }
        actions(goal.id).edit(task, patch)
    }

    // MARK: Moving

    /// A drop in a column, before one of its cards or at its end (before nil), within a goal: a card
    /// from another goal's row can't land (its lanes refuse it). Within its own column a task only changes place, so a
    /// day it has stays.
    private func drop(_ id: String, on column: BoardColumn, of goal: BoardGoal, before: String?) {
        guard let task = goal.tasks.first(where: { $0.id == id }), before != id else { return }
        let patch = BoardColumn.of(task, today: today) == column ? TaskPatch() : column.patch(today: today)
        actions(goal.id).place(task, patch, before)
    }
}

private extension String {
    /// "Today" → "today", "Tomorrow" → "tomorrow"; weekdays keep their capital.
    var lowercasedIfRelative: String { self == "Today" || self == "Tomorrow" ? lowercased() : self }
}

/// A card on the board: white, on top of its lane.
struct CardStyle: ViewModifier {
    let isOpen: Bool

    func body(content: Content) -> some View {
        content
            .padding(isOpen ? 0 : 2)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(Theme.card).shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isOpen ? Theme.lineStrong : Theme.cardBorder))
    }
}

/// The board's title, which is its switch: the goal's title (or All goals) and a chevron, opening
/// the menu of goals.
private struct ScopeTitle: View {
    let title: String
    @Binding var anchor: CGRect
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.app(20, .semibold)).tracking(-0.4)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1).truncationMode(.tail)
                Icon.chevronDown.image(size: 16).foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 6)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .padding(.horizontal, -6)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .modifier(AnchorReader(frame: $anchor))
        .help("Show another project, or all of them")
    }
}

/// A row of the title's menu: a goal (or All goals), ticked when it's the one shown.
private struct ScopeMenuRow<Label: View>: View {
    let isChecked: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                label
                Spacer(minLength: 0)
                if isChecked { Icon.tick.image(size: 16).foregroundStyle(Theme.foreground) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A column's head on All goals: its title and date, then its tasks and its time across every goal.
private struct ColumnHead: View {
    let title: String
    let subtitle: String?
    let tasks: Int
    let time: PlanTime

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                if let subtitle { Text(subtitle).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            PlanFigures(tasks: tasks, time: time, color: "slate")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }
}

/// What a cell or a column head says about its time.
enum PlanTime: Equatable {
    /// Time protected: planned against it.
    case weighed(planned: Int, protected: Int)
    /// Unplanned's total.
    case total(Int)
    /// Planned, with no time protected for it.
    case noTime(planned: Int)
    /// Nothing to say: "—".
    case none

    /// A column head's time, from each goal's capacity in it. A goal's protected time is only for
    /// its own tasks, so one goal's spare time never makes up for another's overage: when any goal
    /// is over, the head is over by the sum of their overages, and only when none is does it say
    /// what's free (or that it just fits).
    static func across(_ each: [Capacity], hasTasks: Bool) -> PlanTime {
        guard !each.isEmpty else { return .none }
        let protected = each.reduce(0) { $0 + $1.protected }
        let over = each.reduce(0) { $0 + max(0, $1.planned - $1.protected) }
        if protected == 0 {
            let planned = each.reduce(0) { $0 + $1.planned }
            return planned > 0 || hasTasks ? .noTime(planned: planned) : .none
        }
        // Over: weighed as the protected time plus what runs past it, so it reads "X over".
        if over > 0 { return .weighed(planned: protected + over, protected: protected) }
        return .weighed(planned: each.reduce(0) { $0 + $1.planned }, protected: protected)
    }

    /// Over what's protected, or time planned with nothing protected for it.
    var isOver: Bool {
        switch self {
        case .weighed(let planned, let protected): planned > protected
        case .noTime(let planned): planned > 0
        case .total, .none: false
        }
    }
}

/// Tasks and time as icons with their figures, on one muted line: the checklist and the open tasks
/// (left out for none), then the clock and what's free, Just fits, Unplanned's total or "X, no
/// time". Over, the clock becomes the ring, and by how much is in amber; time planned with no time
/// protected is amber too, by its clock.
private struct PlanFigures: View {
    let tasks: Int
    let time: PlanTime
    /// The ring's colour key; only an over ring shows, and that's amber.
    let color: String

    var body: some View {
        HStack(spacing: 10) {
            if time == .none {
                Text("—").foregroundStyle(Theme.muted.opacity(0.4))
            } else {
                if tasks > 0 { figure(.checklist, "\(tasks)") }
                switch time {
                case .weighed(let planned, let protected) where planned > protected:
                    HStack(spacing: 4) {
                        CapacityRing(planned: planned, protected: protected, color: color, size: 12)
                        Text("\(BoardDuration.text(planned - protected)) over")
                    }
                    .appText(.xs, .medium)
                    .foregroundStyle(Theme.amber)
                case .weighed(let planned, let protected):
                    figure(.clock, planned == protected ? "Just fits" : "\(BoardDuration.text(protected - planned)) free")
                case .total(let minutes):
                    figure(.clock, BoardDuration.text(minutes))
                case .noTime(let planned) where planned > 0:
                    figure(.clock, "\(BoardDuration.text(planned)), no time")
                        .appText(.xs, .medium)
                        .foregroundStyle(Theme.amber)
                case .noTime:
                    figure(.clock, "No time")
                case .none:
                    EmptyView()
                }
            }
        }
        .appText(.xs)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(Theme.muted)
    }

    private func figure(_ icon: Icon, _ text: String) -> some View {
        HStack(spacing: 4) {
            icon.image(size: 12)
            Text(text)
        }
    }
}

/// A goal's row label on All goals: a chevron to open or fold it, its badge, title and objective.
private struct GoalRowLabel: View {
    let goal: BoardGoal
    let isOpen: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: isOpen ? .top : .center, spacing: 10) {
                (isOpen ? Icon.chevronDown : Icon.arrowRight).image(size: 12)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, isOpen ? 12 : 0)
                GoalBadge(icon: goal.icon, color: goal.color, size: .field)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                        .lineLimit(isOpen ? 2 : 1).truncationMode(.tail)
                    Text(goal.objective ?? "No objective this week").appText(.xs).foregroundStyle(Theme.muted)
                        .lineLimit(isOpen ? 3 : 1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isOpen ? "Fold" : "Show its tasks")
    }
}

/// A folded row's cell: its open tasks and its time on one quiet line, tinted amber when it's over;
/// clicking opens the row.
private struct CellSummary: View {
    let tasks: Int
    let time: PlanTime
    let color: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            PlanFigures(tasks: tasks, time: time, color: color)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .background(fill, in: .rect(cornerRadius: 12))
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if time.isOver { return isHovered ? overWashHovered : overWash }
        return isHovered ? Theme.foreground(0.07) : laneFill
    }
}

/// What's over, on All goals: amber-500 at 8% (amber-400 at 10% in dark), and a step stronger hovered.
private let overWash = Color.adaptive(light: .rgb(0xf59e0b, alpha: 0.08), dark: .rgb(0xfbbf24, alpha: 0.10))
private let overWashHovered = Color.adaptive(light: .rgb(0xf59e0b, alpha: 0.14), dark: .rgb(0xfbbf24, alpha: 0.16))

/// "← Back", to the goal's page.
private struct BoardBackLink: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text("Back").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// One switch for the whole board: finished tasks under each lane's open ones.
private struct ShowCompletedButton: View {
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Icon.tick.image(size: 14)
                Text("Show completed").appText(.sm, .medium)
            }
            .foregroundStyle(isOn || isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Theme.foreground(0.08) : Theme.card)
                    .shadow(color: .black.opacity(isOn ? 0 : 0.04), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Dragging

/// Where a dragged card would land in a lane: before this card, or at the end (nil).
struct BoardInsertion: Equatable {
    let before: String?
}

/// A card dragged onto a lane, shown as if it were there: for previews and snapshot tests.
struct BoardDrop {
    let task: String
    let column: BoardColumn
    let before: String?
}

/// Each lane's own coordinates, which its cards' frames and the pointer are measured in.
private let laneSpace = "boardLane"

/// A card that can be dragged to another lane or place, saying when its drag starts and ends so
/// the board can fade it and know whose it is.
private struct BoardDragSource: ViewModifier {
    let task: TaskItem
    let onDragging: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .draggable(task.id) {
                Text(task.title).appText(.sm).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(width: 220, alignment: .leading)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
            }
            #if os(macOS)
            .onDragSessionUpdated { session in
                switch session.phase {
                case .initial, .active: onDragging(task.id)
                default: onDragging(nil)
                }
            }
            #endif
    }
}

// MARK: - A lane

private struct BoardColumnView<Card: View>: View {
    let title: String
    let subtitle: String?
    /// False on an open row of All goals, where the columns' heads already say it: just the ring.
    var showsTitle = true
    let open: [TaskItem]
    /// Finished tasks to list, when Show completed is on.
    let done: [TaskItem]
    /// The goal's colour key.
    let color: String
    /// Nil for Unplanned, which shows its plain total.
    let capacity: Capacity?
    let capacityLabel: String
    /// Clicking the ring, for a day that's over: how to make it fit.
    var fitPanel: (() -> AnyView)?
    /// A day with time left: how much, and the tasks that would fit in it.
    var fill: (room: Int, tasks: [TaskItem]) = (0, [])
    /// "Plan for Fri", and where each would come from ("Unplanned", "This week").
    var fillAction = ""
    var fillSource: (TaskItem) -> String = { _ in "" }
    /// A suggested task under the pointer at first, for snapshot tests.
    var hoveredFiller: String?
    var onFill: (TaskItem) -> Void = { _ in }
    let clock: Clock
    let emptyDetail: String
    let emptyTitle: String
    let addPlaceholder: String
    let initiallyHovered: Bool
    let showsCapacityInitially: Bool
    let onAdd: (String) -> Void
    /// A task's id dropped here, and the card it goes before (nil: the end of the lane).
    let onDrop: (String, String?) -> Void
    let onToggleDone: (TaskItem) -> Void
    /// The card being dragged, anywhere on the board, if it's one of the board's.
    var dragging: String?
    /// Whether a dragged card can land here: only within its own goal.
    var accepts: (String) -> Bool = { _ in true }
    /// A card here starting to be dragged (its id), or the drag ending (nil).
    var onDragging: (String?) -> Void = { _ in }
    @ViewBuilder let card: (TaskItem) -> Card

    @State private var isTargeted: Bool
    @State private var isHovered: Bool
    @State private var isAdding = false
    /// Where a card dragged over the lane would land, while it's over it and that would move it.
    @State private var insertion: BoardInsertion?
    /// Each open card's frame, and the scrolling area's, in the lane's coordinates.
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var scrollFrame = CGRect.zero

    init(
        title: String, subtitle: String?, showsTitle: Bool = true, open: [TaskItem], done: [TaskItem], color: String, capacity: Capacity?,
        capacityLabel: String, fitPanel: (() -> AnyView)? = nil,
        fill: (room: Int, tasks: [TaskItem]) = (0, []), fillAction: String = "", hoveredFiller: String? = nil,
        fillSource: @escaping (TaskItem) -> String = { _ in "" }, onFill: @escaping (TaskItem) -> Void = { _ in },
        clock: Clock, emptyDetail: String, emptyTitle: String, addPlaceholder: String,
        initiallyHovered: Bool, showsCapacityInitially: Bool, onAdd: @escaping (String) -> Void,
        onDrop: @escaping (String, String?) -> Void, onToggleDone: @escaping (TaskItem) -> Void,
        dragging: String? = nil, accepts: @escaping (String) -> Bool = { _ in true },
        onDragging: @escaping (String?) -> Void = { _ in }, initialInsertion: BoardInsertion? = nil,
        @ViewBuilder card: @escaping (TaskItem) -> Card
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsTitle = showsTitle
        self.open = open
        self.done = done
        self.color = color
        self.capacity = capacity
        self.capacityLabel = capacityLabel
        self.fitPanel = fitPanel
        self.fill = fill
        self.fillAction = fillAction
        self.hoveredFiller = hoveredFiller
        self.fillSource = fillSource
        self.onFill = onFill
        self.clock = clock
        self.emptyDetail = emptyDetail
        self.emptyTitle = emptyTitle
        self.addPlaceholder = addPlaceholder
        self.initiallyHovered = initiallyHovered
        self.showsCapacityInitially = showsCapacityInitially
        self.onAdd = onAdd
        self.onDrop = onDrop
        self.onToggleDone = onToggleDone
        self.dragging = dragging
        self.accepts = accepts
        self.onDragging = onDragging
        self.card = card
        _isHovered = State(initialValue: initiallyHovered)
        _isTargeted = State(initialValue: initialInsertion != nil)
        _insertion = State(initialValue: initialInsertion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
                .padding(.horizontal, 14)
                .padding(.top, 10)
            // Cards that don't fit scroll within the lane, clipped at its bottom.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.cardGap) {
                    if open.isEmpty && done.isEmpty {
                        EmptyLane(title: emptyTitle, detail: emptyDetail)
                    }
                    ForEach(open) { task in
                        card(task)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(laneSpace)) } action: { cardFrames[task.id] = $0 }
                    }
                    if isAdding {
                        AddField(placeholder: addPlaceholder, onAdd: onAdd) { isAdding = false }
                    } else if isHovered {
                        AddButton(help: addPlaceholder) { isAdding = true }
                    }
                    if !fill.tasks.isEmpty { couldFit }
                    if !done.isEmpty { completed }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(laneSpace)) } action: { scrollFrame = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(laneSpace))
        .background(isTargeted ? Theme.foreground(0.07) : laneFill, in: .rect(cornerRadius: 14))
        .overlay(alignment: .topLeading) { dropLine }
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onHover { isHovered = $0 }
        // The whole lane takes the drop, and where the pointer is among the cards says where the
        // card goes: before the first card whose middle is below it, or else at the end.
        .dropDestination(for: String.self) { ids, session in
            let target = insertion(at: session.location.y, for: ids.first)
            isTargeted = false
            insertion = nil
            guard let id = ids.first, accepts(id), let target else { return }
            onDrop(id, target.before)
        }
        // The live drop line and the forbidden cursor use the Mac's drag-session APIs; iOS drops without them.
        #if os(macOS)
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active:
                isTargeted = canDrop
                insertion = canDrop ? insertion(at: session.location.y, for: dragging) : nil
            default:
                isTargeted = false
                insertion = nil
            }
        }
        .dropConfiguration { _ in DropConfiguration(operation: canDrop ? .move : .forbidden) }
        #endif
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    /// A card from another goal can't land here. One that isn't known (a drag the board didn't
    /// start) is let through, and its drop decides.
    private var canDrop: Bool { dragging.map(accepts) ?? true }

    /// Where a card dropped at this height would go, or nil where it would stay as it is: just
    /// before or after itself in its own lane.
    private func insertion(at y: CGFloat, for id: String?) -> BoardInsertion? {
        let before = open.first { task in cardFrames[task.id].map { $0.midY > y } ?? false }?.id
        if let id, let index = open.firstIndex(where: { $0.id == id }) {
            let next = open.indices.contains(index + 1) ? open[index + 1].id : nil
            if before == id || before == next { return nil }
        }
        return BoardInsertion(before: before)
    }

    /// The line between cards where a dragged one would land: halfway into the gap above the card
    /// it'd go before, or below the last. An empty lane has no line; its tint says it all.
    private var dropLineY: CGFloat? {
        guard let insertion, let last = open.last else { return nil }
        let half = Self.cardGap / 2
        let y: CGFloat
        if let before = insertion.before, let frame = cardFrames[before] {
            y = frame.minY - half
        } else if let frame = cardFrames[last.id] {
            y = frame.maxY + half
        } else {
            return nil
        }
        // Kept inside the scrolling area, so a line at its top or bottom edge isn't cut off.
        return min(max(y, scrollFrame.minY + 1), scrollFrame.maxY - 1)
    }

    @ViewBuilder private var dropLine: some View {
        if let y = dropLineY {
            Capsule()
                .fill(GoalPalette.color(color))
                .frame(height: 2)
                .padding(.horizontal, 6)
                .offset(y: y - 1)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.1), value: y)
        }
    }

    private static var cardGap: CGFloat { 6 }

    private var heading: some View {
        HStack(spacing: 6) {
            if showsTitle {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                    if let subtitle { Text(subtitle).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer(minLength: 4)
            }
            if let capacity {
                CapacityChip(capacity: capacity, color: color, label: capacityLabel, clock: clock, showsInitially: showsCapacityInitially, fitPanel: fitPanel)
            } else if !open.isEmpty {
                Text(BoardDuration.text(open.reduce(0) { $0 + $1.minutes })).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
        .frame(minHeight: 22)
    }

    /// "1 h 30 min left · could fit", then each task that would, dashed and quieter.
    private var couldFit: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CapacityRing(planned: 0, protected: fill.room, color: color, size: 12)
                Text("\(BoardDuration.text(fill.room)) left · could fit").appText(.xs, .medium).monospacedDigit()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 2)
            ForEach(fill.tasks) { task in
                FillerCard(task: task, source: fillSource(task), action: fillAction, initiallyHovered: hoveredFiller == task.id) { onFill(task) }
                    .modifier(BoardDragSource(task: task, onDragging: onDragging))
            }
        }
    }

    /// "✓ Completed · 3", then each finished task as one quiet line.
    private var completed: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Icon.tick.image(size: 12)
                Text("Completed · \(done.count)").appText(.xs, .medium).monospacedDigit()
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 2)
            ForEach(done) { task in
                DoneCard(task: task, color: color) { onToggleDone(task) }
            }
        }
    }
}

/// A lane's fill: a step darker than the page, so the white cards stand out on it.
let laneFill = Color.adaptive(light: .rgb(0x0f1114, alpha: 0.045), dark: .rgb(0x000000, alpha: 0.45))

/// An empty lane: a dashed area saying nothing's planned, and what time there is for it, so the
/// space reads as room to plan into rather than a blank.
private struct EmptyLane: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 4) {
            Icon.calendarSmall.image(size: 16)
                .foregroundStyle(Theme.muted)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: .circle)
                .overlay(Circle().strokeBorder(Theme.cardBorder))
                .padding(.bottom, 4)
            Text(title).font(.app(13, .medium)).foregroundStyle(Theme.foreground(0.8))
            Text(detail).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
}

/// A finished task: a filled check in the goal's colour (click to reopen), then its title, quiet.
private struct DoneCard: View {
    let task: TaskItem
    let color: String
    let onReopen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onReopen) {
                Icon.tickHeavy.image(size: 11)
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(GoalPalette.color(color), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .inactive(task.isPending)
            .help("Reopen")
            .accessibilityLabel("Reopen “\(task.title)”")
            Text(task.title).appText(.sm).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card.opacity(0.45), in: .rect(cornerRadius: 12))
        .opacity(task.isPending ? 0.6 : 1)
    }
}

/// A task that would fit a day's time left: dashed and quieter than a card, with how long it takes
/// and where it comes from. Hovered, it offers to plan it for the day; it can be dragged there too.
private struct FillerCard: View {
    let task: TaskItem
    let source: String
    /// "Plan for Fri".
    let action: String
    let onPlan: () -> Void
    @State private var isHovered: Bool

    init(task: TaskItem, source: String, action: String, initiallyHovered: Bool = false, onPlan: @escaping () -> Void) {
        self.task = task
        self.source = source
        self.action = action
        self.onPlan = onPlan
        _isHovered = State(initialValue: initiallyHovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.app(13)).foregroundStyle(Theme.foreground(0.8))
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Icon.clock.image(size: 12)
                Text("\(BoardDuration.text(task.minutes)) · \(source)").lineLimit(1)
                Spacer(minLength: 4)
                if isHovered {
                    Button(action: onPlan) {
                        HStack(spacing: 4) {
                            Icon.add.image(size: 11)
                            Text(action).appText(.xs, .medium)
                        }
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Theme.foreground, in: .rect(cornerRadius: 6))
                        .contentShape(.rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .appText(.xs)
            .foregroundStyle(Theme.muted)
            .monospacedDigit()
            .frame(minHeight: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Theme.card.opacity(0.7) : .clear, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: action, onPlan)
    }
}

/// While the pointer is over a lane: a soft + at the end of its cards, to add one.
private struct AddButton: View {
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.add.image(size: 18)
                .foregroundStyle(Theme.foreground(isHovered ? 0.9 : 0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.card.opacity(isHovered ? 0.8 : 0.6), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The add button turned into a field, in place: Return adds and stays for the next, Escape or
/// clicking away with nothing typed closes it.
private struct AddField: View {
    let placeholder: String
    let onAdd: (String) -> Void
    let onClose: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Icon.add.image(size: 14).foregroundStyle(Theme.muted)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.app(13))
                .foregroundStyle(Theme.foreground)
                .placeholder(placeholder, when: text.isEmpty, font: .app(13), color: Theme.muted.opacity(0.8))
                .accessibilityLabel(placeholder)
                .focused($isFocused)
                .onSubmit {
                    let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    text = ""
                    onAdd(String(title.prefix(TaskItem.maxTitle)))
                    isFocused = true
                }
                .onEscape {
                    text = ""
                    onClose()
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.card.opacity(0.6), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if !focused && text.trimmingCharacters(in: .whitespaces).isEmpty { onClose() }
        }
    }
}

// MARK: - Capacity

/// The ring and its number at the right of a lane's heading: the planned total (amber when over),
/// or the protected total with nothing planned. Hovered, it shows its popover.
private struct CapacityChip: View {
    let capacity: Capacity
    let color: String
    let label: String
    let clock: Clock
    var showsInitially = false
    /// For a day that's over: clicking opens how to make it fit.
    var fitPanel: (() -> AnyView)?

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero
    @State private var didShowInitially = false

    private var owner: String { "capacity#\(label)" }
    private var isShowing: Bool { overlays?.presented?.owner == owner }

    private var number: Int? {
        if capacity.planned > 0 { return capacity.planned }
        return capacity.protected > 0 ? capacity.protected : nil
    }

    var body: some View {
        HStack(spacing: 6) {
            CapacityRing(planned: capacity.planned, protected: capacity.protected, color: color)
            if let number { Text(BoardDuration.text(number)).appText(.xs).monospacedDigit() }
        }
        .foregroundStyle(capacity.isOver ? Theme.amber : isShowing ? Theme.foreground : Theme.muted)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(isShowing ? Theme.wash : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect(cornerRadius: 6))
        .modifier(AnchorReader(frame: $anchor))
        .onHover { $0 ? show() : hide() }
        .onTapGesture(perform: openFit)
        .pointerStyle(fitPanel == nil ? nil : .link)
        .onChange(of: anchor) {
            // Follows the chip as the board lays out or scrolls.
            if isShowing { return show() }
            guard showsInitially, !didShowInitially, anchor != .zero else { return }
            didShowInitially = true
            show()
        }
        .onDisappear(perform: hide)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CapacityPopover.status(capacity))
    }

    private func show() {
        guard let overlays else { return }
        // A menu or dialog that's open keeps its place.
        if let presented = overlays.presented, presented.owner?.hasPrefix("capacity#") != true { return }
        overlays.showHoverCard(anchor: anchor, owner: owner) {
            CapacityPopover(capacity: capacity, color: color, label: label, clock: clock, hint: fitPanel == nil ? nil : "Click to make it fit")
        }
    }

    private func openFit() {
        guard let fitPanel, let overlays else { return }
        hide()
        overlays.showMenu(anchor: anchor, owner: "fit#\(label)", alignLeading: true) { fitPanel() }
    }

    private func hide() {
        overlays?.dismissHoverCard(owner: owner)
    }
}

/// The detail behind a ring: total planned against total protected, and what remains or is over;
/// for a day, its protected time too.
struct CapacityPopover: View {
    let capacity: Capacity
    let color: String
    let label: String
    let clock: Clock
    /// A line at the foot, e.g. that clicking makes it fit.
    var hint: String?

    @Environment(\.colorScheme) private var colorScheme

    /// "1 h remaining", "2 h over", "Just fits", "No time protected".
    static func status(_ capacity: Capacity) -> String {
        if capacity.protected == 0 { return "No time protected" }
        if capacity.remaining < 0 { return "\(BoardDuration.text(-capacity.remaining)) over" }
        return capacity.remaining == 0 ? "Just fits" : "\(BoardDuration.text(capacity.remaining)) remaining"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).appText(.xs).foregroundStyle(Theme.muted)
            HStack(spacing: 14) {
                CapacityRing(planned: capacity.planned, protected: capacity.protected, color: color, size: 52, stroke: 9)
                VStack(alignment: .leading, spacing: 0) {
                    totals
                    Text(Self.status(capacity)).appText(.xs).foregroundStyle(capacity.isOver ? Theme.amber : Theme.muted)
                }
            }
            .monospacedDigit()
            .padding(.top, 10)

            // A day lists its blocks; a week stops after the totals.
            if capacity.isDay {
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 10)
                Text("Protected time").appText(.xs, .medium).foregroundStyle(Theme.muted).padding(.bottom, 4)
                if capacity.blocks.isEmpty {
                    Text("None on this day").font(.app(13)).foregroundStyle(Theme.muted).padding(.vertical, 4)
                }
                ForEach(capacity.blocks, id: \.self) { block in
                    HStack(spacing: 8) {
                        Circle().fill(GoalPalette.color(color).opacity(block.isPast ? 0.4 : 1)).frame(width: 8, height: 8)
                        Text(clock.range(block.start, block.end)).font(.app(13))
                            .foregroundStyle(block.isPast ? Theme.muted : Theme.foreground)
                        Spacer(minLength: 8)
                        Text(BoardDuration.text(block.minutes)).appText(.xs).foregroundStyle(Theme.muted)
                    }
                    .monospacedDigit()
                    .padding(.vertical, 4)
                }
            }
            if let hint {
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 10)
                Text(hint).appText(.xs, .medium).foregroundStyle(Theme.foreground(0.8))
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background {
            // In dark, a step lighter than the cards, with a deeper shadow.
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color(nsColor: .rgb(0x1c1e22)) : Theme.card)
                .shadow(color: .black.opacity(isDark ? 0 : 0.06), radius: 3, y: 2)
                .shadow(color: .black.opacity(isDark ? 0.7 : 0.18), radius: isDark ? 20 : 16, y: isDark ? 16 : 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colorScheme == .dark ? Theme.lineStrong : Theme.cardBorder))
    }

    /// "4 h / 2 h": the planned figure amber when over.
    private var totals: some View {
        var planned = AttributedString(BoardDuration.text(capacity.planned))
        planned.foregroundColor = capacity.isOver ? Theme.amber : Theme.foreground
        planned.font = .app(18, .semibold)
        var text = planned
        if capacity.protected > 0 {
            var rest = AttributedString(" / \(BoardDuration.text(capacity.protected))")
            rest.foregroundColor = Theme.muted
            rest.font = .app(18)
            text += rest
        }
        return Text(text).tracking(-0.18).frame(minHeight: 24)
    }
}

// MARK: - Previews

private func previewDefaults(showsCompleted: Bool) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "PlanningBoardPreview.\(showsCompleted)")!
    defaults.set(showsCompleted, forKey: "planningBoard.showsCompleted")
    return defaults
}

#Preview("All goals") {
    PlanningBoard(data: Fixtures.board, now: Fixtures.referenceNow, initiallyExpanded: ["1"])
        .frame(width: 1500, height: 1000)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}

#Preview("Planning board") {
    PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: Fixtures.referenceNow, initiallyHovered: .unplanned)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}

#Preview("Show completed on") {
    PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: Fixtures.referenceNow)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: true))
}

#Preview("Today's capacity") {
    PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: Fixtures.referenceNow, initialCapacity: .day("2026-11-18"))
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}

#Preview("This week's capacity") {
    PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: Fixtures.referenceNow, initialCapacity: .thisWeek)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}
