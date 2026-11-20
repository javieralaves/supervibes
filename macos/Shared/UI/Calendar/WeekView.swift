import SwiftUI

/*
 * The week at a glance, Monday to Sunday, as week-view.tsx: seven days side by side with what's
 * planned for each without a time, then their blocks, filled in where time has passed. Drag on a
 * day's empty time (or click it) to protect time; drag a block to another time or day, or its top
 * or bottom edge to change its length; click a block to open it, or a day to step into it.
 */

/// The week's geometry: hours a little shorter than the day's, so blocks stay readable as the grid
/// scrolls. Pinching changes how tall an hour is (`HourGrid`).
enum WeekGrid {
    /// Height of one hour, before any pinching.
    static let hour: CGFloat = 150
    /// Pinching in stops at twice that.
    static let maxHour = hour * 2
    static let pad: CGFloat = 8
    static let gutter: CGFloat = 52
    static let standard = HourGrid(hour: hour, pad: pad)
    /// Planned-for-the-day tasks shown per day before "+N more".
    static let maxAnytime = 3
    /// How wide the popover is beside a day.
    static let popoverWidth: CGFloat = 300
}

struct WeekView: View {
    let data: CalendarData
    /// The week's Monday, in days from today.
    let monday: Int
    let now: Date
    let clock: Clock
    var actions: CalendarActions?
    /// Time drawn and waiting to be named.
    @Binding var creating: BlockEditing?
    var selectedId: String?
    /// How tall an hour is, kept between visits; without it the grid keeps its own.
    var storedHour: Binding<CGFloat>?
    var onOpenBlock: (String) -> Void = { _ in }
    var onOpenDay: (Int) -> Void = { _ in }
    /// The grid scrolls; snapshots lay all of it out instead.
    var scrolls = true

    @State private var width: CGFloat = 0
    @State private var drawing: Drawing?
    @State private var dragging: WeekDrag?
    @State private var position = ScrollPosition()
    @State private var scrollY: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// The week it last opened on its focus, so it does so once the scroll view has a size.
    @State private var focusedMonday: Int?
    @State private var ownHour = WeekGrid.hour
    /// The hour height mid-pinch, saved when it ends.
    @State private var pinchHour: CGFloat?
    /// Where a pinch last scrolled to, applied again once the content has its new height.
    @State private var pinchY: CGFloat?
    @Environment(\.overlays) private var overlays

    private var days: [Int] { Array(monday...(monday + 6)) }
    private var columnWidth: CGFloat { max((width - WeekGrid.gutter) / 7, 1) }
    private var thisWeek: Bool { monday <= 0 && monday + 6 >= 0 }

    private var range: ClosedRange<CGFloat> { HourGrid.range(viewport: viewport, pad: WeekGrid.pad, most: WeekGrid.maxHour) }

    /// The grid at the height it's pinched to; laid out whole (snapshots), at the usual height.
    private var grid: HourGrid {
        guard scrolls else { return WeekGrid.standard }
        let hour = pinchHour ?? storedHour?.wrappedValue ?? ownHour
        return HourGrid(hour: min(max(hour, range.lowerBound), range.upperBound), pad: WeekGrid.pad)
    }

    /// Time being drawn on one day.
    private struct Drawing {
        let day: Int
        var from: Int
        var to: Int
        var moved = false
        /// The press only closed the popover.
        var dismissing = false

        /// A click makes an hour; a drag covers what it passed, at least a step.
        var span: (start: Int, end: Int) {
            let step = CalendarDayMath.step
            if !moved {
                var start = CalendarDayMath.snapDown(from)
                let end = min(CalendarDayMath.dayMinutes, start + 60)
                if end - start < step { start = end - step }
                return (start, end)
            }
            let start = CalendarDayMath.snapDown(min(from, to))
            return (start, max(start + step, CalendarDayMath.snapUp(max(from, to))))
        }
    }

    /// A block, or one of its edges, being dragged: how far in minutes and (moving it) days.
    private struct WeekDrag {
        let blockId: String
        let day: Int
        let edge: BlockEdge
        let start: Int
        let end: Int
        var delta = 0
        var dayDelta = 0
        var moved = false
    }

    var body: some View {
        let strips = days.map { data.strip(day: $0, today: now) }
        VStack(spacing: 0) {
            header(strips: strips)
            if scrolls {
                ScrollView {
                    hours
                        .modifier(HourPinch(
                            grid: grid, range: range, scrollY: scrollY, viewport: viewport,
                            onChange: { hour, y in
                                pinchHour = hour
                                pinchY = y
                                position.scrollTo(y: y)
                            },
                            onEnd: {
                                guard let pinchHour else { return }
                                if let storedHour { storedHour.wrappedValue = pinchHour } else { ownHour = pinchHour }
                                self.pinchHour = nil
                            }
                        ))
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentOffset.y, $0.containerSize.height] } action: { _, value in
                    scrollY = value[0]
                    viewport = value[1]
                    if let y = pinchY {
                        // The scroll may have been held to the old height; once the new one is in, go there.
                        pinchY = nil
                        if abs(scrollY - y) > 0.5 { position.scrollTo(y: y) }
                    }
                    if focusedMonday != monday { scrollToFocus() }
                }
                .onChange(of: monday) { scrollToFocus() }
            } else {
                hours
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Open on the current time (or waking up, on other weeks), with about an hour above it. By
    /// position, as the day does: the hour lines are placed with `.offset`, which layout doesn't see.
    private func scrollToFocus() {
        guard viewport > 0 else { return }
        focusedMonday = monday
        let focus = thisWeek ? CalendarDayMath.minutes(now) : data.wakeTime
        position.scrollTo(y: grid.scrollY(keeping: CGFloat(max(0, focus / 60 - 1) * 60), at: WeekGrid.pad, viewport: viewport))
    }

    // MARK: Header

    /// Day names, then each day's tasks planned without a time.
    private func header(strips: [[StripItem]]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: WeekGrid.gutter, height: 1)
                ForEach(days, id: \.self) { day in
                    DayHeader(date: CalendarDayMath.midnight(day, from: now), isToday: day == 0) { onOpenDay(day) }
                }
            }
            if strips.contains(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 0) {
                    Text("Anytime").font(.app(10, .medium)).foregroundStyle(Theme.muted)
                        .frame(width: WeekGrid.gutter - 8, alignment: .trailing)
                        .padding(.trailing, 8)
                        .padding(.top, 6)
                    ForEach(Array(zip(days, strips)), id: \.0) { day, items in
                        AnytimeDay(items: items, goals: data.goals) { onOpenDay(day) }
                    }
                }
            }
        }
        .overlay {
            // The days' dividers, drawn once so they run the header's full height whatever each day holds.
            GeometryReader { geometry in
                let column = (geometry.size.width - WeekGrid.gutter) / 7
                ForEach(0..<7, id: \.self) { index in
                    Rectangle().fill(Theme.cardBorder).frame(width: 1)
                        .offset(x: WeekGrid.gutter + column * CGFloat(index))
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }

    // MARK: Grid

    /// The hours, the days' columns, their blocks and the now line.
    private var hours: some View {
        let grid = self.grid
        let nowMinutes = CalendarDayMath.minutes(now)
        let segments = data.blocks.flatMap { DaySegment.of($0, today: now) }
            .filter { $0.day >= monday && $0.day <= monday + 6 }

        return ZStack(alignment: .topLeading) {
            // Hour lines and labels
            ForEach(0...24, id: \.self) { hour in
                ZStack(alignment: .topLeading) {
                    if hour > 0, hour < 24 {
                        Text(clock.formatHour(hour)).font(.app(10)).monospacedDigit().foregroundStyle(Theme.muted)
                            .frame(width: WeekGrid.gutter - 8, height: 12, alignment: .trailing)
                            .offset(y: -6)
                    }
                    Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.leading, WeekGrid.gutter)
                }
                .offset(y: grid.y(hour * 60))
                .allowsHitTesting(false)
            }

            // The days: sleep, time that's gone, and empty time to draw on
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    column(day, nowMinutes: nowMinutes)
                }
            }
            .padding(.leading, WeekGrid.gutter)

            // Blocks, in one layer over the days so one can be dragged from day to day
            ForEach(segments) { segment in
                if let block = data.blocks.first(where: { $0.id == segment.blockId }) {
                    blockView(block, segment)
                }
            }

            // Time being drawn, or drawn and waiting to be named
            if let draft {
                DraftOutline(label: clock.formatRange(draft.start, draft.end))
                    .frame(width: columnWidth - 4, height: grid.y(draft.end) - grid.y(draft.start) - 2)
                    .offset(x: x(of: draft.day) + 2, y: grid.y(draft.start) + 1)
                    .zIndex(2)
            }

            // Now
            if thisWeek {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(nsColor: .rgb(0xef4444))).frame(height: 2)
                    Circle().fill(Color(nsColor: .rgb(0xef4444))).frame(width: 8, height: 8).offset(x: -4)
                }
                .frame(width: columnWidth, height: 8)
                .offset(x: x(of: 0), y: grid.y(nowMinutes) - 4)
                .allowsHitTesting(false)
                .zIndex(3)
            }

            if let creating, creating.mode == .create, creating.day >= monday, creating.day <= monday + 6 {
                popover(creating).zIndex(4)
            }
        }
        .frame(height: grid.height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func x(of day: Int) -> CGFloat { WeekGrid.gutter + columnWidth * CGFloat(day - monday) }

    private var draft: (day: Int, start: Int, end: Int)? {
        if let drawing, drawing.moved, !drawing.dismissing {
            let span = drawing.span
            return (drawing.day, span.start, span.end)
        }
        if let creating, creating.mode == .create { return (creating.day, creating.start, creating.end) }
        return nil
    }

    private func column(_ day: Int, nowMinutes: Int) -> some View {
        // Whole days behind you, and today up to now, are washed slightly: time that's gone.
        let pastUntil: Int? = day < 0 ? CalendarDayMath.dayMinutes : day == 0 ? nowMinutes : nil
        return ZStack(alignment: .topLeading) {
            ForEach(CalendarDayMath.sleepSpans(sleepStart: data.sleepStart, wakeTime: data.wakeTime), id: \.lowerBound) { span in
                Hatch(color: Theme.foreground(0.06), spacing: 7)
                    .frame(height: grid.y(span.upperBound) - grid.y(span.lowerBound))
                    .offset(y: grid.y(span.lowerBound))
            }
            if let pastUntil {
                Rectangle().fill(Theme.foreground(0.03))
                    .frame(height: grid.y(pastUntil) - WeekGrid.pad)
                    .offset(y: WeekGrid.pad)
            }
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if actions != nil {
                Color.clear.contentShape(.rect).gesture(drawGesture(day))
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.cardBorder).frame(width: 1) }
    }

    // MARK: Drawing

    private func drawGesture(_ day: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drawing == nil {
                    // A press elsewhere while the popover is open only closes it.
                    if creating != nil {
                        creating = nil
                        drawing = Drawing(day: day, from: 0, to: 0, dismissing: true)
                        return
                    }
                    let m = grid.minutes(at: value.startLocation.y)
                    drawing = Drawing(day: day, from: m, to: m)
                }
                guard var current = drawing, !current.dismissing else { return }
                current.to = grid.minutes(at: value.location.y)
                current.moved = current.moved || abs(value.translation.height) > 4
                drawing = current
            }
            .onEnded { _ in
                guard let current = drawing else { return }
                drawing = nil
                guard !current.dismissing, let actions else { return }
                let span = current.span
                creating = BlockEditing(mode: .create, day: current.day, start: span.start, end: span.end,
                                        goalId: actions.defaultGoalId() ?? "", title: nil)
            }
    }

    /// Beside its day: to the right, or to the left on the weekend so it stays in view. Its top
    /// lines up with the drawn time's, or its bottom near the end of the day.
    private func popover(_ editing: BlockEditing) -> some View {
        let index = editing.day - monday
        let left = index < 5
            ? WeekGrid.gutter + columnWidth * CGFloat(index + 1) + 6
            : WeekGrid.gutter + columnWidth * CGFloat(index) - WeekGrid.popoverWidth - 6
        let top = grid.y(editing.start)
        let bottom = grid.y(editing.end)
        let above = top + BlockPopover.estimatedHeight > grid.height
        let weekday = CalendarDayMath.midnight(editing.day, from: now)
            .formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        return BlockPopover(
            goals: data.goals,
            goalId: editing.goalId,
            title: "",
            intention: false,
            timeLabel: "\(weekday) · \(clock.formatRange(editing.start, editing.end))",
            onSave: { goalId, title in
                creating = nil
                actions?.create(editing.day, editing.start, editing.end, goalId, title)
            },
            onCancel: { creating = nil }
        )
        .id(editing.key)
        .frame(width: WeekGrid.popoverWidth)
        .alignmentGuide(.top) { d in above ? d.height - bottom : -top }
        .alignmentGuide(.leading) { _ in -left }
    }

    // MARK: Blocks

    private func blockView(_ block: CalendarBlock, _ segment: DaySegment) -> some View {
        let drag = dragging.flatMap { $0.blockId == block.id && $0.day == segment.day && $0.moved ? $0 : nil }
        let day = segment.day + (drag?.dayDelta ?? 0)
        let start = segment.start + (drag.map { $0.edge == .end ? 0 : $0.delta } ?? 0)
        let end = segment.end + (drag.map { $0.edge == .start ? 0 : $0.delta } ?? 0)
        let midnight = CalendarDayMath.midnight(day, from: now)
        let from = midnight.addingTimeInterval(Double(start) * 60)
        let to = midnight.addingTimeInterval(Double(end) * 60)
        let elapsed = to > from ? min(max(now.timeIntervalSince(from) / to.timeIntervalSince(from), 0), 1) : 0
        // Only the day a block starts on has its top edge, and the day it ends on its bottom; only a
        // block within one day moves as a whole.
        let segmentStart = CalendarDayMath.midnight(segment.day, from: now).addingTimeInterval(Double(segment.start) * 60)
        let segmentEnd = CalendarDayMath.midnight(segment.day, from: now).addingTimeInterval(Double(segment.end) * 60)
        let startsHere = segmentStart == block.startsAt
        let endsHere = segmentEnd == block.endsAt
        let height = max(grid.y(end) - grid.y(start) - 2, 6)

        return WeekBlock(
            block: block,
            goal: data.goal(block.goalId),
            start: start,
            end: end,
            clock: clock,
            elapsed: elapsed,
            isInteractive: actions != nil && !block.isPending,
            isSelected: block.id == selectedId,
            isDragging: drag != nil,
            canMove: startsHere && endsHere,
            canResizeStart: startsHere,
            canResizeEnd: endsHere,
            onDrag: { edge, translation in dragBlock(segment, edge: edge, translation: translation) },
            onDragEnd: { edge in endDrag(block, edge: edge) },
            onOpen: { onOpenBlock(block.id) }
        )
        .frame(width: columnWidth - 4, height: height)
        .contextPanel(owner: block.id, isEnabled: actions != nil && !block.isPending) {
            if let actions {
                BlockMenu(block: block, day: day, actions: actions, editTitle: "Open", onEdit: { onOpenBlock(block.id) })
            }
        }
        .offset(x: x(of: day) + 2, y: grid.y(start) + 1)
        .zIndex(drag != nil ? 1 : 0)
    }

    private func dragBlock(_ segment: DaySegment, edge: BlockEdge, translation: CGSize) {
        if creating != nil, dragging == nil { creating = nil }
        var current = dragging ?? WeekDrag(blockId: segment.blockId, day: segment.day, edge: edge, start: segment.start, end: segment.end)
        let step = CalendarDayMath.step
        current.moved = current.moved || edge != .move || hypot(translation.width, translation.height) > 4
        let raw = Int((translation.height / grid.hour * 60 / CGFloat(step)).rounded()) * step
        // Snapped, kept within its day, and at least a step long when changing its length.
        let bounds: (Int, Int) = switch edge {
        case .start: (-current.start, current.end - step - current.start)
        case .end: (current.start + step - current.end, CalendarDayMath.dayMinutes - current.end)
        case .move: (-current.start, CalendarDayMath.dayMinutes - current.end)
        }
        current.delta = min(max(raw, bounds.0), bounds.1)
        if edge == .move {
            let days = Int((translation.width / columnWidth).rounded())
            current.dayDelta = min(max(days, monday - current.day), monday + 6 - current.day)
        }
        dragging = current
    }

    private func endDrag(_ block: CalendarBlock, edge: BlockEdge) {
        guard let current = dragging else { return }
        dragging = nil
        // Pressed and let go without moving: a click, which opens the block.
        guard current.moved else {
            if edge == .move { onOpenBlock(block.id) }
            return
        }
        if current.delta != 0 || current.dayDelta != 0 {
            actions?.move(block.id, current.edge, current.delta, current.dayDelta)
        }
    }
}

/// A day's name and date over its column; today's date in a dark pill. Click to step into the day.
private struct DayHeader: View {
    let date: Date
    let isToday: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let en = Locale(identifier: "en_US")
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(en)))
                    .appText(.sm, isToday ? .semibold : .regular)
                    .foregroundStyle(isToday ? Theme.foreground : Theme.muted)
                let number = Text(date.formatted(.dateTime.day().locale(en))).monospacedDigit()
                if isToday {
                    number.appText(.xs, .semibold).foregroundStyle(Theme.background)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Theme.foreground, in: .capsule)
                } else {
                    number.appText(.sm).foregroundStyle(Theme.foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(isHovered ? Theme.wash : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open this day")
    }
}

/// A day's tasks planned without a time, and due then, under its name. Click to step into the day.
private struct AnytimeDay: View {
    let items: [StripItem]
    let goals: [CalendarGoal]
    let onOpen: () -> Void

    var body: some View {
        let shown = items.prefix(WeekGrid.maxAnytime)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown)) { item in
                let color = goals.first { $0.id == item.task.goalId }?.color ?? "slate"
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        (item.due != nil ? Icon.flag : Icon.calendarSmall).image(size: 10)
                            .foregroundStyle(item.due == .overdue ? Theme.danger : GoalPalette.color(color))
                        Text(item.task.title).font(.app(11, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 4))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(item.task.title)
            }
            if items.count > shown.count {
                Button("+\(items.count - shown.count) more", action: onOpen)
                    .buttonStyle(.plain)
                    .font(.app(11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A block in the week: the day's card, smaller. Drag to move it, its edges to change its length,
/// or click to open it.
private struct WeekBlock: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let start: Int
    let end: Int
    let clock: Clock
    let elapsed: Double
    let isInteractive: Bool
    let isSelected: Bool
    let isDragging: Bool
    let canMove: Bool
    let canResizeStart: Bool
    let canResizeEnd: Bool
    let onDrag: (BlockEdge, CGSize) -> Void
    let onDragEnd: (BlockEdge) -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        BlockCardView(block: block, goal: goal, start: start, end: end, clock: clock, elapsed: elapsed, compact: true)
            .overlay {
                if isInteractive {
                    VStack(spacing: 0) {
                        if canResizeStart {
                            Color.clear.frame(height: 6).contentShape(.rect)
                                .pointerStyle(.frameResize(position: .top))
                                .gesture(drag(.start))
                        }
                        Spacer(minLength: 0)
                        if canResizeEnd {
                            Capsule().fill(Theme.foreground(0.2)).frame(width: 24, height: 4)
                                .opacity(isHovered || isDragging ? 1 : 0)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .frame(height: 8)
                                .contentShape(.rect)
                                .pointerStyle(.frameResize(position: .bottom))
                                .gesture(drag(.end))
                        }
                    }
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(GoalPalette.color(goal?.color ?? "slate").opacity(0.6), lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: isDragging ? Color(nsColor: .rgb(0x0f1114, alpha: 0.35)) : .clear, radius: 10, y: 8)
            .contentShape(.rect(cornerRadius: 6))
            .modifier(BodyGesture(enabled: isInteractive, canMove: canMove, drag: drag(.move), onOpen: onOpen))
            .pointerStyle(isDragging ? .grabActive : nil)
            .onHover { isHovered = $0 }
    }

    /// Translation in the window's space, since the block itself moves as it's dragged.
    private func drag(_ edge: BlockEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { onDrag(edge, $0.translation) }
            .onEnded { _ in onDragEnd(edge) }
    }
}

/// Pressing a block's body: drag it (a press that doesn't move opens it), or, for one that crosses
/// midnight and can't move as a whole, just open it.
private struct BodyGesture<G: Gesture>: ViewModifier {
    let enabled: Bool
    let canMove: Bool
    let drag: G
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if canMove {
            content.gesture(drag)
        } else {
            content.onTapGesture(perform: onOpen)
        }
    }
}

/// Time being drawn: a dashed outline with its time.
private struct DraftOutline: View {
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.foreground(0.04))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.foreground(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            .overlay(alignment: .topLeading) {
                Text(label).font(.app(11, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .padding(.leading, 8).padding(.top, 4)
            }
            .allowsHitTesting(false)
    }
}

#Preview("Week") {
    @Previewable @State var showsOverview = true
    DayView(data: Fixtures.calendar, offset: 0, now: Fixtures.referenceNow, isWeek: true, onSetWeek: { _ in },
            showsOverview: showsOverview, onToggleOverview: { showsOverview.toggle() })
        .background(Theme.background)
        .frame(width: 1400, height: 760)
}
