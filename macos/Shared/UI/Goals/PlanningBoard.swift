import SwiftUI

/*
 * Planning a goal's tasks on a board, in one row of lanes that scrolls sideways: Unplanned, today,
 * tomorrow and the day after, then this week and next week. Drag a card onto a lane to plan it
 * there, or onto another card to put it just before that one; its right-click menu does the same
 * without dragging. Click a card to edit it in place, as on the goal page: the cards are the same
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
    let detail: GoalDetail
    var actions = TaskActions()
    /// For "Today 2:00 PM" and the protected time gone by; fixed in snapshots.
    var now = Date()
    /// Opens with this task open, for snapshot tests.
    var initiallyOpen: String?
    /// Opens with the pointer over this column, for previews and snapshot tests.
    var initiallyHovered: BoardColumn?
    /// Opens with this column's capacity showing, for previews and snapshot tests.
    var initialCapacity: BoardColumn?
    var onBack: () -> Void = {}

    @State private var draft: TaskDraft?
    @State private var headerHeight: CGFloat = 0
    @AppStorage("planningBoard.showsCompleted") private var showsCompleted = false

    private var today: String { detail.today }
    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    private static let columnWidth: CGFloat = 320
    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 24
    private static let top: CGFloat = 40
    private static let headerGap: CGFloat = 28
    private static let bottom: CGFloat = 8

    var body: some View {
        let open = Dictionary(grouping: detail.tasks) { BoardColumn.of($0, today: today) }
        let done = Dictionary(grouping: detail.week.done) { BoardColumn.ofDone($0, today: today) }
        let columns = BoardColumn.all(today: today)
        GeometryReader { geo in
            // The lanes run to the bottom of the window, whatever they hold.
            let laneHeight = max(240, geo.size.height - Self.top - headerHeight - Self.headerGap - Self.bottom)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.headerGap) {
                    header
                        .padding(.horizontal, Self.margin)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: Self.gap) {
                            ForEach(columns, id: \.self) { column in
                                self.column(column, open: open[column] ?? [], done: showsCompleted ? done[column] ?? [] : [])
                                    .frame(width: Self.columnWidth, height: laneHeight)
                            }
                        }
                        .padding(.horizontal, Self.margin)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.top, Self.top)
                .padding(.bottom, Self.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A click outside the cards closes an open one.
                .background(Color.clear.contentShape(.rect).onTapGesture(perform: closeTask))
            }
            .scrollContentBackground(.hidden)
        }
        .environment(\.shortHours, true)
        .onAppear {
            if let id = initiallyOpen, let task = detail.tasks.first(where: { $0.id == id }) { draft = TaskDraft(task) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardBackLink(action: onBack).padding(.bottom, 20)
            HStack(alignment: .center, spacing: 16) {
                GoalBadge(icon: detail.goal.icon, color: detail.goal.color, size: .sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.goal.title)
                        .font(.app(20, .semibold)).tracking(-0.4)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(minHeight: 24)
                    Text(detail.week.objective.map { "This week: \($0)" } ?? "No objective for this week yet.")
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

    // MARK: Columns

    private func column(_ column: BoardColumn, open: [TaskItem], done: [TaskItem]) -> some View {
        BoardColumnView(
            title: title(column),
            subtitle: subtitle(column),
            open: open,
            done: done,
            color: detail.goal.color,
            capacity: capacity(column),
            capacityLabel: capacityLabel(column),
            clock: detail.clock ?? .device,
            emptyDetail: emptyDetail(column),
            emptyTitle: "Nothing planned for \(relativeName(column))",
            addPlaceholder: addPlaceholder(column),
            initiallyHovered: initiallyHovered == column,
            showsCapacityInitially: initialCapacity == column,
            onAdd: { actions.add($0, column.patch(today: today)) },
            onDrop: { id, before in drop(id, on: column, before: before) },
            onToggleDone: actions.toggle
        ) { task in
            card(task, in: column)
        }
    }

    @ViewBuilder private func card(_ task: TaskItem, in column: BoardColumn) -> some View {
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
                clock: detail.clock ?? .device,
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
            .draggable(task.id) {
                Text(task.title).appText(.sm).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(width: 220, alignment: .leading)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
            }
            .contextMenu {
                ForEach(moves(for: task, from: column), id: \.0) { item in
                    Button(item.0, action: item.1)
                }
            }
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

    // MARK: Capacity

    /// Time planned against time protected: a day counts its own day, a week the whole week (its
    /// days on the board included).
    private func capacity(_ column: BoardColumn) -> Capacity? {
        let blocks = detail.week.protectedBlocks
        switch column {
        case .unplanned:
            return nil
        case .day(let day):
            let open = detail.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }
            return .day(day, open: open, blocks: blocks, now: now)
        case .thisWeek, .nextWeek:
            let week = column == .thisWeek ? thisWeek : nextWeek
            let open = detail.tasks.filter { BoardColumn.week(of: $0, today: today) == week }.reduce(0) { $0 + $1.minutes }
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
    private func emptyDetail(_ column: BoardColumn) -> String {
        guard case .day = column, let capacity = capacity(column) else { return "Drag a task here to plan it" }
        let ahead = capacity.ahead
        let clock = detail.clock ?? .device
        if ahead.count == 1, let block = ahead.first {
            return "\(BoardDuration.text(block.minutes)) protected, \(clock.range(block.start, block.end))"
        }
        if !ahead.isEmpty { return "\(BoardDuration.text(ahead.reduce(0) { $0 + $1.minutes })) protected still ahead" }
        return capacity.blocks.isEmpty ? "No time protected" : "Its protected time has gone by"
    }

    // MARK: Editing

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
        guard let task = detail.tasks.first(where: { $0.id == draft.id }), let patch = draft.patch(for: task) else { return }
        actions.edit(task, patch)
    }

    // MARK: Moving

    /// A drop on a column (before nil) or on one of its cards. Within its own column a task only
    /// changes place, so a day it has stays.
    private func drop(_ id: String, on column: BoardColumn, before: String?) {
        guard let task = detail.tasks.first(where: { $0.id == id }), before != id else { return }
        let patch = BoardColumn.of(task, today: today) == column ? TaskPatch() : column.patch(today: today)
        actions.place(task, patch, before)
    }

    /// The right-click menu's moves: to each column it isn't in.
    private func moves(for task: TaskItem, from column: BoardColumn) -> [(String, () -> Void)] {
        BoardColumn.all(today: today).filter { $0 != column }.map { target in
            let name = switch target {
            case .unplanned: "Move to Unplanned"
            case .day(let day): "Plan for \(CalendarDay.relativeLabel(day, today: today).lowercasedIfRelative)"
            case .thisWeek: "Move to this week"
            case .nextWeek: "Move to next week"
            }
            return (name, { actions.place(task, target.patch(today: today), nil) })
        }
    }
}

private extension String {
    /// "Today" → "today", "Tomorrow" → "tomorrow"; weekdays keep their capital.
    var lowercasedIfRelative: String { self == "Today" || self == "Tomorrow" ? lowercased() : self }
}

/// A card on the board (and the Plan page's lanes): white, on top of its lane.
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

// MARK: - A lane

private struct BoardColumnView<Card: View>: View {
    let title: String
    let subtitle: String?
    let open: [TaskItem]
    /// Finished tasks to list, when Show completed is on.
    let done: [TaskItem]
    /// The goal's colour key.
    let color: String
    /// Nil for Unplanned, which shows its plain total.
    let capacity: Capacity?
    let capacityLabel: String
    let clock: Clock
    let emptyDetail: String
    let emptyTitle: String
    let addPlaceholder: String
    let initiallyHovered: Bool
    let showsCapacityInitially: Bool
    let onAdd: (String) -> Void
    /// A task's id dropped here, and the card it landed on (nil: the lane itself, so the end).
    let onDrop: (String, String?) -> Void
    let onToggleDone: (TaskItem) -> Void
    @ViewBuilder let card: (TaskItem) -> Card

    @State private var isTargeted = false
    @State private var isHovered: Bool
    @State private var isAdding = false

    init(
        title: String, subtitle: String?, open: [TaskItem], done: [TaskItem], color: String, capacity: Capacity?,
        capacityLabel: String, clock: Clock, emptyDetail: String, emptyTitle: String, addPlaceholder: String,
        initiallyHovered: Bool, showsCapacityInitially: Bool, onAdd: @escaping (String) -> Void,
        onDrop: @escaping (String, String?) -> Void, onToggleDone: @escaping (TaskItem) -> Void,
        @ViewBuilder card: @escaping (TaskItem) -> Card
    ) {
        self.title = title
        self.subtitle = subtitle
        self.open = open
        self.done = done
        self.color = color
        self.capacity = capacity
        self.capacityLabel = capacityLabel
        self.clock = clock
        self.emptyDetail = emptyDetail
        self.emptyTitle = emptyTitle
        self.addPlaceholder = addPlaceholder
        self.initiallyHovered = initiallyHovered
        self.showsCapacityInitially = showsCapacityInitially
        self.onAdd = onAdd
        self.onDrop = onDrop
        self.onToggleDone = onToggleDone
        self.card = card
        _isHovered = State(initialValue: initiallyHovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
                .padding(.horizontal, 14)
                .padding(.top, 10)
            // Cards that don't fit scroll within the lane, clipped at its bottom.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    if open.isEmpty && done.isEmpty {
                        EmptyLane(title: emptyTitle, detail: emptyDetail)
                    }
                    ForEach(open) { task in
                        card(task)
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first else { return false }
                                onDrop(id, task.id)
                                return true
                            }
                    }
                    if isAdding {
                        AddField(placeholder: addPlaceholder, onAdd: onAdd) { isAdding = false }
                    } else if isHovered {
                        AddButton(help: addPlaceholder) { isAdding = true }
                    }
                    if !done.isEmpty { completed }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isTargeted ? Theme.foreground(0.07) : laneFill, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .onHover { isHovered = $0 }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id, nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var heading: some View {
        HStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                if let subtitle { Text(subtitle).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if let capacity {
                CapacityChip(capacity: capacity, color: color, label: capacityLabel, clock: clock, showsInitially: showsCapacityInitially)
            } else if !open.isEmpty {
                Text(BoardDuration.text(open.reduce(0) { $0 + $1.minutes })).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
            }
        }
        .frame(minHeight: 22)
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
                .onExitCommand {
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
            CapacityPopover(capacity: capacity, color: color, label: label, clock: clock)
        }
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

#Preview("Planning board") {
    PlanningBoard(detail: Fixtures.planningDetail, now: Fixtures.referenceNow, initiallyHovered: .unplanned)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}

#Preview("Show completed on") {
    PlanningBoard(detail: Fixtures.planningDetail, now: Fixtures.referenceNow)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: true))
}

#Preview("Today's capacity") {
    PlanningBoard(detail: Fixtures.planningDetail, now: Fixtures.referenceNow, initialCapacity: .day("2026-11-18"))
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}

#Preview("This week's capacity") {
    PlanningBoard(detail: Fixtures.planningDetail, now: Fixtures.referenceNow, initialCapacity: .thisWeek)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
        .defaultAppStorage(previewDefaults(showsCompleted: false))
}
