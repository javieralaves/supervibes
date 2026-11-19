import SwiftUI

/*
 * Planning a goal's tasks on a board, edge to edge in one row: Unplanned, today, tomorrow and the
 * day after, then this week and next week. Drag a card onto a column to plan it there, or onto
 * another card to put it just before that one; its right-click menu does the same without
 * dragging. Click a card to edit it in place, as on the goal page: the cards are the same rows.
 * The header weighs this week's open estimates against the time protected for the goal.
 * Layers: the page, then the columns a step lighter, then the cards, white.
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
}

struct PlanningBoard: View {
    let detail: GoalDetail
    var actions = TaskActions()
    /// For "Today 2:00 PM"; fixed in snapshots.
    var now = Date()
    /// Opens with this task open, for snapshot tests.
    var initiallyOpen: String?
    var onBack: () -> Void = {}

    @State private var draft: TaskDraft?

    private var today: String { detail.today }
    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    /// Below this a column gets too narrow for its cards, so the row scrolls sideways instead.
    private static let minColumnWidth: CGFloat = 220
    private static let gap: CGFloat = 10
    private static let margin: CGFloat = 24

    /// Open estimates meant for this week: its days (on the board or not) and the week itself.
    private var minutesThisWeek: Int {
        detail.tasks.filter { task in
            if let day = task.plannedFor, day >= today { return CalendarDay.weekStart(day) == thisWeek }
            return task.horizon(today: today).group == .thisWeek
        }
        .reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        let open = Dictionary(grouping: detail.tasks) { BoardColumn.of($0, today: today) }
        let done = Dictionary(grouping: detail.week.done) { BoardColumn.ofDone($0, today: today) }
        let columns = BoardColumn.all(today: today)
        GeometryReader { geo in
            let available = geo.size.width - 2 * Self.margin - CGFloat(columns.count - 1) * Self.gap
            let width = max(Self.minColumnWidth, available / CGFloat(columns.count))
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 28) {
                    header.padding(.horizontal, Self.margin)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: Self.gap) {
                            ForEach(columns, id: \.self) { column in
                                self.column(column, open: open[column] ?? [], done: done[column] ?? [])
                                    .frame(width: width)
                            }
                        }
                        .padding(.horizontal, Self.margin)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(width * CGFloat(columns.count) <= available + 0.5)
                }
                .padding(.top, 40)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .leading)
                // A click outside the cards closes an open one.
                .background(Color.clear.contentShape(.rect).onTapGesture(perform: closeTask))
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            if let id = initiallyOpen, let task = detail.tasks.first(where: { $0.id == id }) { draft = TaskDraft(task) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardBackLink(title: detail.goal.title, action: onBack).padding(.bottom, 20)
            HStack(alignment: .top, spacing: 16) {
                GoalBadge(icon: detail.goal.icon, color: detail.goal.color, size: .sm)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan tasks").appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                    if let objective = detail.week.objective {
                        Text("This week: \(objective)").appText(.sm).foregroundStyle(Theme.muted).lineLimit(2)
                    } else {
                        Text("No objective for this week yet.").appText(.sm).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 24)
                WeekLoad(planned: minutesThisWeek, protected: detail.week.protectedMinutes)
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
            addPlaceholder: addPlaceholder(column),
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

    private func addPlaceholder(_ column: BoardColumn) -> String {
        switch column {
        case .unplanned: "Add a task"
        case .day(let day): "Add for \(CalendarDay.relativeLabel(day, today: today).lowercasedIfRelative)"
        case .thisWeek: "Add to this week"
        case .nextWeek: "Add to next week"
        }
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

/// A card on the board: white, on top of its column.
private struct CardStyle: ViewModifier {
    let isOpen: Bool

    func body(content: Content) -> some View {
        content
            .padding(isOpen ? 0 : 2)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isOpen ? Theme.lineStrong : Theme.cardBorder))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

/// "← Goal title", back to the goal's page.
private struct BoardBackLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text(title).appText(.sm, .medium).lineLimit(1)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// This week's open estimates against the time protected for the goal: amber once there's more
/// planned than time for it.
private struct WeekLoad: View {
    let planned: Int
    let protected: Int

    private var isOver: Bool { planned > protected }
    private static let amber = Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24))

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                Text(Self.duration(planned)).appText(.sm, .medium).foregroundStyle(isOver ? Self.amber : Theme.foreground)
                Text("planned this week").appText(.sm).foregroundStyle(Theme.muted)
            }
            Text(protected > 0 ? "\(Self.duration(protected)) of time protected" : "No time protected yet")
                .appText(.xs).foregroundStyle(Theme.muted)
            GeometryReader { geo in
                let share = protected > 0 ? min(1, Double(planned) / Double(protected)) : (planned > 0 ? 1 : 0)
                Capsule().fill(Theme.wash)
                    .overlay(alignment: .leading) {
                        Capsule().fill(isOver ? Self.amber : Theme.foreground(0.6)).frame(width: geo.size.width * share)
                    }
            }
            .frame(width: 200, height: 4)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    /// "5 hr 30 min", "45 min", "2 hr".
    static func duration(_ minutes: Int) -> String {
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

// MARK: - A column

private struct BoardColumnView<Card: View>: View {
    let title: String
    let subtitle: String?
    let open: [TaskItem]
    let done: [TaskItem]
    let addPlaceholder: String
    let onAdd: (String) -> Void
    /// A task's id dropped here, and the card it landed on (nil: the column itself, so the end).
    let onDrop: (String, String?) -> Void
    let onToggleDone: (TaskItem) -> Void
    @ViewBuilder let card: (TaskItem) -> Card

    @State private var isTargeted = false
    @State private var showsDone = false
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                if let subtitle { Text(subtitle).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1) }
                Spacer(minLength: 4)
                if !open.isEmpty {
                    Text(WeekLoad.duration(open.reduce(0) { $0 + $1.minutes })).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 2)

            ForEach(open) { task in
                card(task)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        onDrop(id, task.id)
                        return true
                    }
            }
            addField
            if !done.isEmpty { doneList }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        .background(Theme.card.opacity(isTargeted ? 0.85 : 0.5), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isTargeted ? Theme.lineStrong : Theme.cardBorder))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id, nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Icon.add.image(size: 14).foregroundStyle(Theme.muted)
            TextField("", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.app(13))
                .foregroundStyle(Theme.foreground)
                .placeholder(addPlaceholder, when: newTitle.isEmpty, font: .app(13), color: Theme.muted.opacity(0.8))
                .accessibilityLabel(addPlaceholder)
                .onSubmit {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    newTitle = ""
                    onAdd(String(title.prefix(TaskItem.maxTitle)))
                }
                .onExitCommand { newTitle = "" }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
    }

    /// "3 done", folded until clicked; then each finished task, struck through, to reopen.
    private var doneList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(.easeOut(duration: 0.15)) { showsDone.toggle() } } label: {
                HStack(spacing: 6) {
                    Icon.tick.image(size: 12)
                    Text("\(done.count) done").appText(.xs, .medium).monospacedDigit()
                    Icon.chevronDown.image(size: 11).rotationEffect(.degrees(showsDone ? 0 : -90))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsDone ? "Hide finished tasks" : "Show \(done.count) finished tasks")

            if showsDone {
                ForEach(done) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Checkbox(isDone: true, isDisabled: task.isPending) { onToggleDone(task) }
                            .help("Reopen")
                        Text(task.title).appText(.sm).foregroundStyle(Theme.muted)
                            .strikethrough(true, color: Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 2)
    }
}

#Preview("Planning board") {
    PlanningBoard(detail: Fixtures.planningDetail, now: Fixtures.referenceNow)
        .frame(width: 1500, height: 900)
        .background(Theme.background)
}
