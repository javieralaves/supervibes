import SwiftUI

/*
 * The Day view's Anytime strip, a row per goal ("The day, by goal" in supervibes-design). Each row is
 * a goal with tasks on the day: its icon, title and how many, then the gap between its tasks and its
 * session time and its ring, as the planning board counts them (DayGoalRow). Rows run over first.
 * Click one to open it: its tasks follow as a plain list, the ones its time doesn't reach dimmed, and
 * the Day view rings its sessions on the timeline. Drag a task onto the timeline to give it a time;
 * drop one from the task panel anywhere on the strip to plan it for the day.
 */

struct GoalStrip: View {
    let rows: [DayGoalRow]
    /// Each task's next block, for dragging it.
    var blocks: [String: CalendarBlock] = [:]
    /// Today, "YYYY-MM-DD", for "from Mon".
    let today: String
    /// "Today" or "Friday", for the drop hint.
    var dayName = ""
    /// The goals open on this day.
    @Binding var open: Set<String>
    @Environment(\.taskDrag) private var drag

    /// Lines the strip's first row up with "Anytime".
    private static let padding: CGFloat = 6

    var body: some View {
        let placing = drag?.placing.flatMap { $0.moved ? $0 : nil }
        let dropping = placing?.onStrip ?? false
        HStack(alignment: .top, spacing: 0) {
            Text("Anytime").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                .frame(width: DayGrid.gutter, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, Self.padding + 9)
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text(placing != nil ? "Drop to plan it for \(dayName)" : "Drag a task here to plan it for the day, without a time.")
                        .appText(.xs).foregroundStyle(dropping ? Theme.foreground : Theme.muted)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 32)
                }
                ForEach(rows) { row in
                    GoalStripRow(
                        row: row, blocks: blocks, today: today, isOpen: open.contains(row.id),
                        draggingId: placing?.taskId
                    ) {
                        if open.contains(row.id) { open.remove(row.id) } else { open.insert(row.id) }
                    }
                }
                if dropping, !rows.isEmpty {
                    Text("Drop to plan it for \(dayName)").appText(.xs).foregroundStyle(Theme.foreground)
                        .padding(.leading, 32)
                        .frame(minHeight: 28)
                }
            }
            .padding(.vertical, Self.padding)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        // Its full height, however much is open: the timeline below takes what's left.
        .fixedSize(horizontal: false, vertical: true)
        .background(dropping ? Theme.foreground(0.05) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .calendar) } action: { drag?.stripFrame = $0 }
        .onDisappear { drag?.stripFrame = .zero }
    }
}

/// A goal's row, and its tasks while it's open.
private struct GoalStripRow: View {
    let row: DayGoalRow
    let blocks: [String: CalendarBlock]
    let today: String
    let isOpen: Bool
    /// The task being dragged, if it's one of these.
    let draggingId: String?
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    (isOpen ? Icon.chevronDown : Icon.arrowRight).image(size: 12).foregroundStyle(Theme.muted)
                    GoalIconImage(name: row.goal.icon, size: 15).foregroundStyle(GoalPalette.color(row.goal.color))
                    // The title, then how many tasks right after it.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(row.goal.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground)
                            .lineLimit(1).truncationMode(.tail)
                        Text("\(row.items.count)").font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Text(row.gapLabel).font(.app(13)).monospacedDigit()
                        .foregroundStyle(row.isOver ? Theme.amber : Theme.muted)
                        .lineLimit(1)
                    CapacityRing(planned: row.capacity.planned, protected: row.capacity.protected, color: row.goal.color, size: 16)
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Hide its tasks" : "Show its tasks")
            .accessibilityLabel("\(row.goal.title), \(row.items.count) \(row.items.count == 1 ? "task" : "tasks"), \(row.gapLabel)")
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(row.items) { item in
                        GoalStripTask(
                            item: item, block: blocks[item.task.id], color: row.goal.color, today: today,
                            isPastTime: row.pastTime.contains(item.task.id), isDragging: draggingId == item.task.id
                        )
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background((isOpen || isHovered) ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}

/// A task under an open goal: an empty circle under the goal's icon, the title lined up with the
/// goal's, a flag when it's due (red once overdue), "from Mon" when it carried over, and its estimate
/// on the right. Past the goal's time, dimmed. Drag it onto the timeline to give it a time.
private struct GoalStripTask: View {
    let item: StripItem
    let block: CalendarBlock?
    let color: String
    let today: String
    let isPastTime: Bool
    let isDragging: Bool

    private var isPending: Bool { block?.isPending ?? item.task.isPending }

    var body: some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(Theme.foreground(0.3), lineWidth: 1.5)
                .frame(width: 13, height: 13)
                .frame(width: 15)
            HStack(spacing: 6) {
                Text(item.task.title).font(.app(13)).foregroundStyle(Theme.foreground(0.85))
                    .lineLimit(1).truncationMode(.tail)
                if item.due != nil {
                    Icon.flag.image(size: 12)
                        .foregroundStyle(item.due == .overdue ? Theme.danger : GoalPalette.color(color))
                }
                if let from = item.carriedFrom {
                    Text("from \(CalendarDay.relativeLabel(from, today: today))").font(.app(11, .medium)).foregroundStyle(Theme.amber)
                }
            }
            Spacer(minLength: 8)
            Text(BoardDuration.text(item.task.minutes)).font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .padding(.leading, 26)
        .padding(.trailing, 8)
        .frame(height: 28)
        .opacity(isPastTime ? 0.4 : 1)
        .opacity(isDragging || isPending ? 0.5 : 1)
        .contentShape(.rect)
        .pointerStyle(isPending ? nil : .grabIdle)
        .modifier(TaskDragSource(task: PanelTask(task: item.task, block: block)))
        .help(helpText)
    }

    private var helpText: String {
        var lines = [item.task.title]
        if let from = item.carriedFrom { lines.append("Planned from \(CalendarDay.relativeLabel(from, today: today))") }
        if item.due == .overdue, let due = item.task.dueOn { lines.append("Overdue since \(CalendarDay.relativeLabel(due, today: today))") }
        else if item.due == .due { lines.append("Due this day") }
        if isPastTime { lines.append("Past the goal's time today") }
        lines.append("Drag onto the timeline to give it a time")
        return lines.joined(separator: "\n")
    }
}

#Preview("By goal") {
    @Previewable @State var open: Set<String> = []
    GoalStrip(rows: Fixtures.dayByGoal.goalRows(day: 0, now: Fixtures.referenceNow), today: "2026-11-18", dayName: "Today", open: $open)
        .frame(width: 768)
        .background(Theme.card)
}

#Preview("One goal open") {
    @Previewable @State var open: Set<String> = ["superfocus"]
    GoalStrip(rows: Fixtures.dayByGoal.goalRows(day: 0, now: Fixtures.referenceNow), today: "2026-11-18", dayName: "Today", open: $open)
        .frame(width: 768)
        .background(Theme.card)
}
