import SwiftUI

/*
 * Planning a goal's tasks on a board: the next three days on top, then this week, next week and
 * Later. Drag a card onto a column to plan it there (a day, a week, or not yet), or onto another
 * card to put it just before that one; its right-click menu does the same without dragging. The
 * header weighs this week's open estimates against the time protected for the goal this week.
 */

/// Where a task sits on the board.
enum BoardColumn: Hashable, Sendable {
    case day(String)
    case thisWeek, nextWeek, later

    /// How many days the board shows, starting today.
    static let dayCount = 3

    /// The column an open task sits in: a day it's planned for in the next three, or else its week
    /// (a day further out sits in its week's column, showing its day), or Later.
    static func of(_ task: TaskItem, today: String) -> BoardColumn {
        let thisWeek = CalendarDay.weekStart(today)
        if let day = task.plannedFor, day >= today {
            if CalendarDay.daysUntil(day, today: today) < dayCount { return .day(day) }
            switch CalendarDay.weekStart(day) {
            case thisWeek: return .thisWeek
            case CalendarDay.addDays(thisWeek, 7): return .nextWeek
            default: return .later
            }
        }
        return switch task.horizon(today: today).group {
        case .day, .thisWeek: .thisWeek
        case .nextWeek: .nextWeek
        case .later: .later
        }
    }

    /// Where a task finished this week shows: on its day if that's on the board, else this week.
    static func ofDone(_ task: TaskItem, today: String) -> BoardColumn {
        if let day = task.plannedFor, day >= today, CalendarDay.daysUntil(day, today: today) < dayCount { return .day(day) }
        return .thisWeek
    }

    /// What dropping a task here plans it for. A week or Later drops its day.
    func patch(today: String) -> TaskPatch {
        let thisWeek = CalendarDay.weekStart(today)
        return switch self {
        case .day(let day): TaskPatch(plannedFor: day)
        case .thisWeek: TaskPatch(plannedFor: "", plannedWeek: thisWeek)
        case .nextWeek: TaskPatch(plannedFor: "", plannedWeek: CalendarDay.addDays(thisWeek, 7))
        case .later: TaskPatch(plannedFor: "", plannedWeek: "")
        }
    }
}

struct PlanningBoard: View {
    let detail: GoalDetail
    var actions = TaskActions()
    var onBack: () -> Void = {}

    private var today: String { detail.today }
    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }
    private var days: [String] { (0..<BoardColumn.dayCount).map { CalendarDay.addDays(today, $0) } }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                BoardLabel("Planned for a day").padding(.top, 28)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(days, id: \.self) { day in
                        column(.day(day), open: open[.day(day)] ?? [], done: done[.day(day)] ?? [])
                    }
                }
                BoardLabel("Planned for a week, or not yet").padding(.top, 24)
                HStack(alignment: .top, spacing: 12) {
                    column(.thisWeek, open: open[.thisWeek] ?? [], done: done[.thisWeek] ?? [])
                    column(.nextWeek, open: open[.nextWeek] ?? [], done: [])
                    column(.later, open: open[.later] ?? [], done: [])
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardBackLink(title: detail.goal.title, action: onBack).padding(.bottom, 24)
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
            today: today,
            showsDay: !isDay(column),
            addPlaceholder: addPlaceholder(column),
            onAdd: { actions.add($0, week(column)) },
            onDrop: { id, before in drop(id, on: column, before: before) },
            menu: { task in moves(for: task, from: column) },
            onToggle: actions.toggle
        )
    }

    private func isDay(_ column: BoardColumn) -> Bool {
        if case .day = column { return true }
        return false
    }

    private func title(_ column: BoardColumn) -> String {
        switch column {
        case .day(let day): CalendarDay.relativeLabel(day, today: today)
        case .thisWeek: "This week"
        case .nextWeek: "Next week"
        case .later: "Later"
        }
    }

    private func subtitle(_ column: BoardColumn) -> String {
        switch column {
        case .day(let day): CalendarDay.format(day, today: today)
        case .thisWeek: CalendarDay.formatWeek(thisWeek)
        case .nextWeek: CalendarDay.formatWeek(nextWeek)
        case .later: "Not decided"
        }
    }

    private func addPlaceholder(_ column: BoardColumn) -> String? {
        switch column {
        case .day: nil
        case .thisWeek: "Add to this week"
        case .nextWeek: "Add to next week"
        case .later: "Add for later"
        }
    }

    private func week(_ column: BoardColumn) -> String? {
        switch column {
        case .thisWeek: thisWeek
        case .nextWeek: nextWeek
        default: nil
        }
    }

    /// A drop on a column (before nil) or on one of its cards. Within its own column a task only
    /// changes place, so a day it has stays.
    private func drop(_ id: String, on column: BoardColumn, before: String?) {
        guard let task = detail.tasks.first(where: { $0.id == id }), before != id else { return }
        let patch = BoardColumn.of(task, today: today) == column ? TaskPatch() : column.patch(today: today)
        actions.place(task, patch, before)
    }

    /// The right-click menu's moves: to each column it isn't in.
    private func moves(for task: TaskItem, from column: BoardColumn) -> [(String, () -> Void)] {
        let targets = days.map { BoardColumn.day($0) } + [.thisWeek, .nextWeek, .later]
        return targets.filter { $0 != column }.map { target in
            let name = switch target {
            case .day(let day): "Plan for \(CalendarDay.relativeLabel(day, today: today).lowercasedFirstIfRelative)"
            case .thisWeek: "Move to this week"
            case .nextWeek: "Move to next week"
            case .later: "Move to Later"
            }
            return (name, { actions.place(task, target.patch(today: today), nil) })
        }
    }
}

private extension String {
    /// "Today" → "today", "Tomorrow" → "tomorrow"; weekdays keep their capital.
    var lowercasedFirstIfRelative: String { self == "Today" || self == "Tomorrow" ? lowercased() : self }
}

/// `text-xs font-medium text-muted`, above a row of columns.
private struct BoardLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).appText(.xs, .medium).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.bottom, 8)
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

private struct BoardColumnView: View {
    let title: String
    let subtitle: String
    let open: [TaskItem]
    let done: [TaskItem]
    let today: String
    /// Cards show their planned day (in a week's column, where the column doesn't say it).
    let showsDay: Bool
    let addPlaceholder: String?
    let onAdd: (String) -> Void
    /// A task's id dropped here, and the card it landed on (nil: the column itself, so the end).
    let onDrop: (String, String?) -> Void
    let menu: (TaskItem) -> [(String, () -> Void)]
    let onToggle: (TaskItem) -> Void

    @State private var isTargeted = false
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                Text(subtitle).appText(.xs).foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                if !open.isEmpty {
                    Text(WeekLoad.duration(open.reduce(0) { $0 + $1.minutes })).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            ForEach(open) { task in
                BoardCard(task: task, today: today, showsDay: showsDay, onToggle: { onToggle(task) })
                    .draggable(task.id) {
                        BoardCard(task: task, today: today, showsDay: showsDay, onToggle: {}).frame(width: 240)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first else { return false }
                        onDrop(id, task.id)
                        return true
                    }
                    .contextMenu {
                        ForEach(Array(menu(task).enumerated()), id: \.offset) { _, item in
                            Button(item.0, action: item.1)
                        }
                    }
            }
            ForEach(done) { task in
                BoardCard(task: task, today: today, showsDay: showsDay, onToggle: { onToggle(task) })
            }
            if open.isEmpty, done.isEmpty {
                Text("Drop a task here").appText(.xs).foregroundStyle(Theme.muted.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.foreground(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            if let addPlaceholder { addField(addPlaceholder) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
        .background(isTargeted ? Theme.wash : Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isTargeted ? Theme.lineStrong : Theme.cardBorder))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onDrop(id, nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private func addField(_ placeholder: String) -> some View {
        HStack(spacing: 8) {
            Icon.add.image(size: 14).foregroundStyle(Theme.muted)
            TextField("", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.app(13))
                .foregroundStyle(Theme.foreground)
                .placeholder(placeholder, when: newTitle.isEmpty, font: .app(13), color: Theme.muted.opacity(0.8))
                .accessibilityLabel(placeholder)
                .onSubmit {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    newTitle = ""
                    onAdd(String(title.prefix(TaskItem.maxTitle)))
                }
                .onExitCommand { newTitle = "" }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 32)
    }
}

// MARK: - A card

private struct BoardCard: View {
    let task: TaskItem
    let today: String
    let showsDay: Bool
    let onToggle: () -> Void

    private static let amber = Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24))

    var body: some View {
        let horizon = task.horizon(today: today)
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Icon.tickBold.image(size: 10)
                    .foregroundStyle(task.done ? Theme.foreground : .clear)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(Theme.foreground(0.3), lineWidth: 1.5))
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .inactive(task.isPending)
            .accessibilityLabel(task.done ? "Reopen" : "Mark as done")
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).appText(.sm).foregroundStyle(Theme.foreground)
                    .strikethrough(task.done, color: Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.done {
                    HStack(spacing: 6) {
                        meta(.clock, TaskItem.minutesLabel(task.minutes))
                        if showsDay, let day = task.plannedFor {
                            meta(.calendarSmall, CalendarDay.relativeLabel(day, today: today), tone: horizon.slipped ? Self.amber : Theme.muted)
                        }
                        if let due = task.dueOn {
                            let (text, tone) = TaskDayKind.due.describe(due, today: today)
                            meta(.flag, text, tone: tone)
                        }
                        if horizon.carriedWeeks > 0 {
                            meta(.refresh, horizon.carriedWeeks == 1 ? "Carried" : "Carried ×\(horizon.carriedWeeks)", tone: Self.amber)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
        .opacity(task.done ? 0.55 : task.isPending ? 0.6 : 1)
        .contentShape(.rect(cornerRadius: 10))
    }

    private func meta(_ icon: Icon, _ text: String, tone: Color = Theme.muted) -> some View {
        HStack(spacing: 3) {
            icon.image(size: 11)
            Text(text).font(.app(11, .medium)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(tone)
    }
}

#Preview("Planning board") {
    PlanningBoard(detail: Fixtures.planningDetail)
        .frame(width: 1100, height: 900)
        .background(Theme.background)
}
