import SwiftUI

/*
 * Dragging a task from the Day view's strip: onto the timeline to give it a time, onto the strip
 * to plan it for the day, or within its project's list to reorder it. A task with a block moves it.
 */

// MARK: - Dragging a task

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The day view's space, which a dragged task, the timeline and the strip are measured in.
    static var calendar: NamedCoordinateSpace { .named("calendar") }
}

/// A task being dragged from the strip onto the day.
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
    /// Over its own goal's open list on the strip: the place among the goal's other tasks there it
    /// would move to.
    var listIndex: Int?
}

/// An open goal's task list on the strip, for reordering it: where it is and where each task is,
/// in the calendar's space.
struct StripList: Equatable {
    var frame: CGRect = .zero
    var rows: [String: CGRect] = [:]
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
    /// The open goals' task lists on the strip, by goal.
    @ObservationIgnored var lists: [String: StripList] = [:]
    /// The timeline's geometry, at the height it's pinched to.
    @ObservationIgnored var grid = DayGrid.standard
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
            let raw = Int(((p.y - timelineFrame.minY - grid.pad) / grid.hour * 60).rounded())
            current.start = min(max(CalendarDayMath.snapDown(raw), 0), CalendarDayMath.dayMinutes - current.minutes)
        } else {
            current.start = nil
        }
        current.listIndex = listIndex(of: current, at: p)
        // Moving within its own list isn't planning it for the day.
        current.onStrip = stripFrame.contains(p) && current.listIndex == nil
        if current != placing { placing = current }
    }

    /// Over its own goal's open list: how many of the goal's other tasks there sit above the pointer.
    /// The list is drawn with the task already in that place, so the others below it have moved down
    /// a row and the count holds while the pointer stays on it.
    private func listIndex(of current: Placing, at p: CGPoint) -> Int? {
        guard let list = lists[current.goalId], list.frame.contains(p), list.rows[current.taskId] != nil else { return nil }
        return list.rows.filter { $0.key != current.taskId && $0.value.midY < p.y }.count
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
    @Environment(\.dayGrid) private var grid

    var body: some View {
        let short = grid.height(end - start) < 48
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
