import SwiftUI

/*
 * A task's menu on the Day view's strip, at the pointer on a right-click ("The day, by goal" in
 * supervibes-design, A task's menu). The rows are the goal page's task menu (TaskRows.swift) with
 * what the day adds. A task within its goal's time: check it off, then schedule it at its turn in the
 * goal's sessions, or move it to the top. A task past its goal's time: why it's dimmed, in amber, then
 * the board's Make it fit for this one task: the first day with room, the free time next to the
 * goal's session, or the top of the list and what that pushes out. Then, for either, the day, week,
 * estimate and due date, the goal, and Delete.
 */

struct DayTaskMenu: View {
    let task: CalendarTask
    let goal: CalendarGoal
    let suggestions: TaskSuggestions
    /// The goal's session time that day, for "Doesn't fit its 2 h 30 min today".
    let sessionMinutes: Int
    /// Days from today, and "YYYY-MM-DD", of the day shown.
    let day: Int
    let dayISO: String
    /// "YYYY-MM-DD".
    let today: String
    let clock: Clock
    let actions: CalendarActions
    @Environment(\.overlays) private var overlays

    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    var body: some View {
        MenuPanel(width: suggestions.isPastTime ? 288 : 264) {
            if suggestions.isPastTime {
                Text("Doesn’t fit \(goal.title)’s \(BoardDuration.text(sessionMinutes)) \(when(dayISO))")
                    .appText(.xs).foregroundStyle(Theme.amber)
                    .lineLimit(2)
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
                if let move = suggestions.move {
                    SuggestionRow(title: "Move to \(place(move.to))", detail: moveDetail(move)) {
                        CapacityRing(planned: move.protected - move.roomAfter, protected: move.protected, color: goal.color, size: 15)
                    } action: { run { go(to: move.to) } }
                }
                if let slot = suggestions.protect {
                    let start = CalendarDayMath.minutes(slot.start), end = start + slot.minutes
                    SuggestionRow(title: "Protect \(clock.formatRange(start, end)) for it", detail: "Free, next to its session") {
                        Icon.target.image(size: 16).foregroundStyle(Theme.muted)
                    } action: { run { actions.create(day, start, end, goal.id, nil, .session) } }
                }
                moveToTop
                MenuSeparator()
                MenuItem(icon: .tick, title: "Mark done") { run { actions.markTaskDone(task.id) } }
            } else {
                MenuItem(icon: .tick, title: "Mark done") { run { actions.markTaskDone(task.id) } }
                if let turn = suggestions.turn {
                    MenuSeparator()
                    SuggestionRow(title: "Schedule at \(clock.formatRange(turn.start, turn.end))",
                                  detail: "Its turn in the \(clock.format(minutes: turn.session)) session") {
                        Icon.clock.image(size: 16).foregroundStyle(Theme.muted)
                    } action: { run { actions.place(task.id, day, turn.start, turn.end - turn.start) } }
                    moveToTop
                } else if !suggestions.isFirst {
                    MenuSeparator()
                    moveToTop
                }
            }
            MenuSeparator()
            if day >= 0 {
                MenuItem(icon: .arrowForward, title: day == 0 ? "Move to tomorrow" : "Move to the next day") { run { actions.plan(task.id, day + 1) } }
            }
            SubmenuItem(icon: .calendarSmall, title: "Plan for a day") {
                DayMenu(kind: .plan, value: task.plannedFor, today: today, week: task.plannedWeek,
                        onWeek: { week in actions.changeTask(task.id, TaskPatch(plannedFor: "", plannedWeek: week)) }) { picked in
                    actions.changeTask(task.id, picked.map { TaskPatch(plannedFor: $0) } ?? TaskPatch(plannedFor: "", plannedWeek: ""))
                }
            }
            MenuItem(icon: .calendarSmall, title: "Move to this week") { run { week(thisWeek) } }
            MenuItem(icon: .arrowForward, title: "Move to next week") { run { week(nextWeek) } }
            if task.plannedFor == dayISO {
                MenuItem(icon: .close, title: "Take off this day") { run { actions.plan(task.id, nil) } }
            }
            MenuSeparator()
            SubmenuItem(icon: .clock, title: "Estimate") {
                EstimateMenu(minutes: task.minutes, shortHours: true) { actions.changeTask(task.id, TaskPatch(minutes: $0)) }
            }
            SubmenuItem(icon: .flag, title: task.dueOn == nil ? "Set due date" : "Change due date") {
                DayMenu(kind: .due, value: task.dueOn, today: today) { actions.changeTask(task.id, TaskPatch(dueOn: $0 ?? "")) }
            }
            if let openGoal = actions.openGoal {
                MenuSeparator()
                MenuItem(icon: .target, title: "Open project") { run { openGoal(goal.id) } }
            }
            MenuSeparator()
            MenuItem(icon: .delete, title: "Delete", isDestructive: true) { run { actions.deleteTask(task.id) } }
        }
    }

    /// Reorders without dragging; says what it would push past the goal's time.
    @ViewBuilder private var moveToTop: some View {
        if !suggestions.isFirst {
            SuggestionRow(title: "Move to top", detail: suggestions.pushesOut.map { "Pushes \($0) out" }) {
                Icon.arrowForward.image(size: 16).foregroundStyle(Theme.muted).rotationEffect(.degrees(-90))
            } action: { run { actions.reorder(task.id, day, 0) } }
        }
    }

    private func run(_ action: () -> Void) {
        overlays?.dismiss()
        action()
    }

    private func week(_ week: String) {
        actions.changeTask(task.id, TaskPatch(plannedFor: "", plannedWeek: week))
    }

    private func go(to destination: Fit.Destination) {
        switch destination {
        case .day(let other): actions.plan(task.id, CalendarDay.daysUntil(other, today: today))
        case .thisWeek: week(thisWeek)
        case .nextWeek: week(nextWeek)
        }
    }

    /// "Friday", "Tomorrow", "This week", "Next week".
    private func place(_ destination: Fit.Destination) -> String {
        switch destination {
        case .day(let other): dayName(other)
        case .thisWeek: "this week"
        case .nextWeek: "next week"
        }
    }

    private func moveDetail(_ move: Fit.Move) -> String {
        let first = if case .day = move.to { "First day with room" } else { "Room there" }
        return "\(first) · \(BoardDuration.text(move.protected - move.roomAfter)) / \(BoardDuration.text(move.protected)) after"
    }

    /// "today", "tomorrow", "on Friday".
    private func when(_ other: String) -> String {
        switch CalendarDay.daysUntil(other, today: today) {
        case 0: "today"
        case 1: "tomorrow"
        default: "on \(CalendarDay.weekday(other))"
        }
    }

    private func dayName(_ other: String) -> String {
        switch CalendarDay.daysUntil(other, today: today) {
        case 0: "Today"
        case 1: "Tomorrow"
        default: CalendarDay.weekday(other)
        }
    }
}

/// A menu row with a second line saying what choosing it does, and its own icon (a ring, for a
/// place a task could go).
private struct SuggestionRow<Leading: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let leading: () -> Leading
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.overlays) private var overlays

    var body: some View {
        Button(action: action) {
            HStack(alignment: detail == nil ? .center : .top, spacing: 10) {
                leading().frame(width: 16, height: 16).padding(.top, detail == nil ? 0 : 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground).lineLimit(1)
                    if let detail {
                        Text(detail).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, detail == nil ? 0 : 6)
            .frame(minHeight: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            // A submenu open elsewhere in the menu closes, as on the other rows.
            if hovering { overlays?.hoverRow(id: title, row: .zero, submenu: nil) }
        }
    }
}
