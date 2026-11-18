import SwiftUI

/*
 * Open tasks across goals, beside the day, as task-panel.tsx. Drag one onto the timeline to give it
 * a time, or onto the day's strip to plan it for the day. Tasks planned for the shown day lead their
 * goal; scheduled ones sit at the end, faded, with their time, and dragging one moves its block.
 */

// MARK: - Dragging a task

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The day view's space, which a dragged task, the timeline and the strip are measured in.
    static var calendar: NamedCoordinateSpace { .named("calendar") }
}

/// A task being dragged from the panel or the strip onto the day.
struct Placing: Equatable {
    let taskId: String
    let goalId: String
    let title: String
    /// How long it lands: its block's length when it has one, else its estimate.
    let minutes: Int
    /// Past the few points that tell a drag from a click.
    var moved = false
    /// The pointer, in the calendar's space.
    var location: CGPoint = .zero
    /// Where it would land on the shown day, or nil while the pointer is off the timeline.
    var start: Int?
    /// Over the shown day's strip, to plan it for the day without a time.
    var onStrip = false
}

/// The drag in progress, and where the timeline and strip are, so the drop can be worked out.
@MainActor
@Observable
final class TaskDragState {
    private(set) var placing: Placing?

    /// The timeline's content, its visible part, and the strip, in the calendar's space.
    @ObservationIgnored var timelineFrame: CGRect = .zero
    @ObservationIgnored var viewportFrame: CGRect = .zero
    @ObservationIgnored var stripFrame: CGRect = .zero
    /// Called with the drag when it's let go past the threshold.
    @ObservationIgnored var onDrop: (Placing) -> Void = { _ in }

    func drag(_ task: PanelTask, to location: CGPoint, translation: CGSize) {
        var current = placing ?? Placing(taskId: task.id, goalId: task.task.goalId, title: task.task.title, minutes: task.minutes)
        current.location = location
        current.moved = current.moved || hypot(translation.width, translation.height) > 4
        placing = current
        update()
    }

    func end() {
        guard let current = placing else { return }
        placing = nil
        if current.moved { onDrop(current) }
    }

    /// Where it lands, worked out again (also as the timeline scrolls under a still pointer).
    func update() {
        guard var current = placing, current.moved else { return }
        let p = current.location
        if p.x >= timelineFrame.minX + DayGrid.gutter, p.x <= viewportFrame.maxX, p.y >= viewportFrame.minY, p.y <= viewportFrame.maxY {
            let raw = Int(((p.y - timelineFrame.minY - DayGrid.pad) / DayGrid.hour * 60).rounded())
            current.start = min(max(CalendarDayMath.snapDown(raw), 0), CalendarDayMath.dayMinutes - current.minutes)
        } else {
            current.start = nil
        }
        current.onStrip = stripFrame.contains(p)
        if current != placing { placing = current }
    }
}

extension EnvironmentValues {
    @Entry var taskDrag: TaskDragState? = nil
}

/// Makes a task draggable onto the day.
struct TaskDragSource: ViewModifier {
    let task: PanelTask
    @Environment(\.taskDrag) private var drag

    func body(content: Content) -> some View {
        if let drag, !task.isPending {
            content.gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .calendar)
                    .onChanged { drag.drag(task, to: $0.location, translation: $0.translation) }
                    .onEnded { _ in drag.end() }
            )
        } else {
            content
        }
    }
}

/// The task under the pointer while it's dragged outside the timeline.
struct DragChip: View {
    let title: String
    let color: String

    var body: some View {
        HStack(spacing: 6) {
            Icon.circle.image(size: 13).foregroundStyle(GoalPalette.color(color))
            Text(title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.14)), radius: 8, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// Where a dragged task would land: an outline in its goal's colour, with the time.
struct DropPreview: View {
    let title: String
    let color: String
    let start: Int
    let end: Int
    let clock: Clock

    var body: some View {
        let short = CGFloat(end - start) / 60 * DayGrid.hour < 48
        RoundedRectangle(cornerRadius: 8)
            .fill(GoalPalette.mix(color, light: 0.03, dark: 0.03))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(GoalPalette.color(color).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .overlay(alignment: .topLeading) {
                if short {
                    // Unlike a card, the time stays visible even on one line: it's what you're choosing.
                    HStack(spacing: 8) {
                        Text(clock.formatRange(start, end)).appText(.xs, .medium).monospacedDigit().foregroundStyle(Theme.foreground)
                        Text(title).font(.app(13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Icon.circle.image(size: 13).foregroundStyle(GoalPalette.color(color)).padding(.top, 3)
                            Text(title).font(.app(14, .medium)).foregroundStyle(Theme.foreground).lineLimit(2)
                        }
                        Text(clock.formatRange(start, end)).font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 12)
                    .padding(.trailing, 32)
                }
            }
            .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.12)), radius: 8, y: 6)
            .allowsHitTesting(false)
    }
}

// MARK: - The panel

struct TaskPanel: View {
    let groups: [PanelGroup]
    let clock: Clock
    let now: Date
    @Environment(\.taskDrag) private var drag

    private var today: String { CalendarDay.today(now) }
    private var all: [PanelTask] { groups.flatMap(\.tasks) }
    /// A task is planned once it has a day or a time.
    private func isPlanned(_ t: PanelTask) -> Bool { t.task.plannedFor != nil || t.block != nil }

    var body: some View {
        let count = all.count
        let planned = all.filter(isPlanned).count
        let forToday = all.filter { $0.task.plannedFor == today || ($0.block.map { Calendar.current.isDate($0.startsAt, inSameDayAs: now) } ?? false) }.count
        let overdue = all.filter { ($0.task.dueOn.map { $0 < today }) ?? false }.count
        let dueToday = all.filter { $0.task.dueOn == today }.count

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Icon.checklist.image(size: 16).foregroundStyle(Theme.foreground(0.75))
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.background)
                                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.06)), radius: 1, y: 1)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
                    Text("Tasks").font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 0)
                }
                let figure = HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)").font(.app(22, .semibold)).tracking(-0.44).monospacedDigit().foregroundStyle(Theme.foreground)
                    Text(count == 1 ? "open task" : "open tasks").appText(.xs).foregroundStyle(Theme.muted)
                }
                .fixedSize()
                let pills = HStack(spacing: 6) {
                    if forToday > 0 {
                        Pill(icon: .calendarSmall, text: "\(forToday) today", tone: .neutral)
                    }
                    if overdue > 0 {
                        Pill(icon: .flag, text: "\(overdue) overdue", tone: .danger)
                    } else if dueToday > 0 {
                        Pill(icon: .flag, text: "\(dueToday) due", tone: .neutral)
                    }
                }
                // Side by side when they fit; the pills go under the figure when they don't.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        figure
                        Spacer(minLength: 0)
                        pills
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        figure
                        pills
                    }
                }
                .padding(.top, 16)
                GoalSplitBar(parts: groups.map { ($0.goal.id, $0.goal.color, $0.tasks.count, $0.tasks.filter(isPlanned).count) })
                    .padding(.top, 12)
                    .accessibilityLabel("\(planned) of \(count) open tasks planned")
                Text(planned == 0 ? "None planned yet" : "\(planned) of \(count) planned for a day or time")
                    .font(.app(11)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            }
            .padding(16)
            .background {
                RadialGradient(colors: [Theme.foreground(0.05), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if count == 0 {
                        Text("No open tasks. Add tasks to a goal and they show up here.")
                            .appText(.sm).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 8) {
                                    GoalBadge(icon: group.goal.icon, color: group.goal.color, size: .xs)
                                    Text(group.goal.title).font(.app(13, .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.top, 2)
                                .padding(.bottom, 4)
                                ForEach(group.tasks) { task in
                                    PanelRow(
                                        task: task,
                                        color: group.goal.color,
                                        clock: clock,
                                        now: now,
                                        isDragging: drag?.placing.map { $0.moved && $0.taskId == task.id } ?? false
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

/// `rounded-full px-2 py-0.5 text-[11px] font-medium`, with a small icon.
private struct Pill: View {
    enum Tone { case neutral, danger }
    let icon: Icon
    let text: String
    let tone: Tone

    var body: some View {
        let red = Color.adaptive(light: .rgb(0xdc2626), dark: .rgb(0xf87171))
        HStack(spacing: 4) {
            icon.image(size: 11)
            Text(text).font(.app(11, .medium))
        }
        .foregroundStyle(tone == .danger ? red : Theme.foreground(0.8))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(tone == .danger ? Color(nsColor: .rgb(0xef4444)).opacity(0.1) : Theme.foreground(0.06), in: .capsule)
    }
}

/// One bar split by goal: each goal's part as wide as its share, light for what's still to come
/// and solid for the part that's done.
struct GoalSplitBar: View {
    /// Goal, colour, how many, and how many of those count as done.
    let parts: [(id: String, color: String, value: Int, filled: Int)]

    var body: some View {
        let shown = parts.filter { $0.value > 0 }
        GeometryReader { geometry in
            let gaps = CGFloat(max(shown.count - 1, 0)) * 3
            let total = CGFloat(shown.reduce(0) { $0 + $1.value })
            HStack(spacing: 3) {
                if shown.isEmpty {
                    Capsule().fill(Theme.foreground(0.06))
                } else {
                    ForEach(shown, id: \.id) { part in
                        let width = max(6, (geometry.size.width - gaps) * CGFloat(part.value) / total)
                        let light = Color(nsColor: NSColor(hex: GoalPalette.colorInfo(part.color).light) ?? .gray)
                        Capsule().fill(light.opacity(0.3))
                            .overlay(alignment: .leading) {
                                Rectangle().fill(light).frame(width: width * min(1, CGFloat(part.filled) / CGFloat(part.value)))
                            }
                            .clipShape(.capsule)
                            .frame(width: width)
                    }
                }
            }
        }
        .frame(height: 8)
    }
}

/// A task in the panel: a circle in its goal's colour, the title, then its estimate, time or day, and due date.
private struct PanelRow: View {
    let task: PanelTask
    let color: String
    let clock: Clock
    let now: Date
    let isDragging: Bool
    @State private var isHovered = false

    var body: some View {
        let today = CalendarDay.today(now)
        let scheduled = task.block.map { scheduleLabel($0.startsAt) }
        // A time says when already; without one, the day it's planned for.
        let planned = scheduled == nil ? task.task.plannedFor.map { CalendarDay.relativeLabel($0, today: today) } : nil
        let missed = scheduled == nil && (task.task.plannedFor.map { $0 < today } ?? false)
        let overdue = task.task.dueOn.map { $0 < today } ?? false
        let due = task.task.dueOn.map { "\(overdue ? "Overdue" : "Due") \(CalendarDay.relativeLabel($0, today: today))" }

        HStack(alignment: .top, spacing: 8) {
            Icon.circle.image(size: 13).foregroundStyle(GoalPalette.color(color))
                .frame(width: 24)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.task.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                subline(scheduled: scheduled, planned: planned, missed: missed, due: due, overdue: overdue)
                    .appText(.xs).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered || isDragging ? Theme.foreground(0.04) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .opacity(task.isPending || isDragging ? 0.5 : task.block != nil ? 0.6 : 1)
        .onHover { isHovered = $0 }
        .pointerStyle(task.isPending ? nil : .grabIdle)
        .modifier(TaskDragSource(task: task))
        .help(scheduled != nil ? "Drag to move it to another time" : "Drag onto the calendar to schedule it")
    }

    private func subline(scheduled: String?, planned: String?, missed: Bool, due: String?, overdue: Bool) -> Text {
        let amber = Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24))
        let red = Color.adaptive(light: .rgb(0xdc2626), dark: .rgb(0xf87171))
        var text = Text(TaskItem.minutesLabel(task.task.minutes)).foregroundStyle(Theme.muted)
        if let scheduled { text = Text("\(text)\(Text(" · \(scheduled)").foregroundStyle(Theme.muted))") }
        if let planned {
            text = Text("\(text)\(Text(" · ").foregroundStyle(Theme.muted))\(Text(planned).foregroundStyle(missed ? amber : Theme.muted))")
        }
        if let due {
            text = Text("\(text)\(Text(" · ").foregroundStyle(Theme.muted))\(Text(due).foregroundStyle(overdue ? red : Theme.muted))")
        }
        return text
    }

    /// "Today 2:00 PM", "Tomorrow 9:30 AM" or "Thu 14:00".
    private func scheduleLabel(_ date: Date) -> String {
        let time = clock.format(minutes: CalendarDayMath.minutes(date))
        let day = switch CalendarDayMath.dayOffset(date, from: now) {
        case 0: "Today"
        case 1: "Tomorrow"
        default: date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US")))
        }
        return "\(day) \(time)"
    }
}
