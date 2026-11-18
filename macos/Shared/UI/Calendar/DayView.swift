import SwiftUI

/*
 * One day, hour by hour, matching src/app/(app)/calendar/day-calendar.tsx: the top bar, the
 * "Anytime" strip of tasks planned or due without a time, then the timeline with sleep shaded,
 * past time washed, blocks filling in as their time passes, and the now line.
 */

/// The timeline's geometry (geometry.ts).
enum DayGrid {
    /// Height of one hour.
    static let hour: CGFloat = 176
    /// Room above midnight and below the last hour so their labels aren't clipped.
    static let pad: CGFloat = 12
    /// Width of the hour-label column.
    static let gutter: CGFloat = 64
    static let height = y(CalendarDayMath.dayMinutes) + pad

    /// Top of a time (minutes after midnight).
    static func y(_ minutes: Int) -> CGFloat { pad + CGFloat(minutes) / 60 * hour }
}

struct DayView: View {
    let data: CalendarData
    /// Days from today.
    let offset: Int
    /// The calendar's clock, to the minute.
    let now: Date
    var error: String?
    var onStep: (Int) -> Void = { _ in }
    var onToday: () -> Void = {}
    /// Changing blocks; without it the day is read-only.
    var actions: CalendarActions?
    /// Opens with this block being named, for previews and snapshots.
    var editing: BlockEditing?

    private var clock: Clock { data.clock ?? .device }
    private var isToday: Bool { offset == 0 }
    private var shownDay: Date { CalendarDayMath.midnight(offset, from: now) }

    var body: some View {
        VStack(spacing: 0) {
            CalendarTopBar(
                title: shownDay.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_US"))),
                relative: Self.dayLabel(offset),
                showsToday: !isToday,
                onToday: onToday,
                onPrevious: { onStep(-1) },
                onNext: { onStep(1) }
            )

            VStack(spacing: 0) {
                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Theme.cardBorder).frame(height: 1)
                }
                let strip = data.strip(day: offset, today: now)
                if !strip.isEmpty {
                    DayStrip(items: strip, goals: data.goals, today: CalendarDay.today(now))
                }
                TimelineScroll(data: data, offset: offset, now: now, clock: clock, actions: actions, editing: editing)
            }
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .frame(maxWidth: 768)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }

    /// "Today", "Tomorrow" or "Yesterday"; nil further away.
    static func dayLabel(_ offset: Int) -> String? {
        switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: nil
        }
    }
}

// MARK: - Top bar

/// `h-14 bg-background shadow-[inset_0_-1px_0_var(--card-border)]`: the date, then Today and the arrows.
struct CalendarTopBar: View {
    let title: String
    var relative: String?
    var showsToday: Bool
    var onToday: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground).lineLimit(1)
                if let relative {
                    Text(relative).appText(.sm).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if showsToday {
                BarButton(action: onToday) { Text("Today").appText(.sm, .medium).padding(.horizontal, 12) }
            }
            HStack(spacing: 4) {
                BarButton(action: onPrevious) { Icon.arrowLeft.image(size: 16).frame(width: 32) }
                    .help("Previous day")
                    .accessibilityLabel("Previous day")
                BarButton(action: onNext) { Icon.arrowRight.image(size: 16).frame(width: 32) }
                    .help("Next day")
                    .accessibilityLabel("Next day")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }

    /// `h-8 rounded-lg border bg-card shadow`, muted until hovered.
    private struct BarButton<Label: View>: View {
        let action: () -> Void
        @ViewBuilder var label: Label
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                label
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                            .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Anytime strip

/// The top of a day: tasks meant for it without a time, and tasks due then.
struct DayStrip: View {
    let items: [StripItem]
    let goals: [CalendarGoal]
    /// Today, "YYYY-MM-DD", for "from Mon" and "Overdue since Mon".
    let today: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("Anytime").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                .frame(width: DayGrid.gutter, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, 12)
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    StripChip(item: item, color: goals.first { $0.id == item.task.goalId }?.color ?? "slate", today: today)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }
}

/// A task on the strip, tinted with its goal: why it's here (a calendar or a flag), the title, its estimate.
private struct StripChip: View {
    let item: StripItem
    let color: String
    let today: String

    var body: some View {
        let carried = item.carriedFrom.map { "from \(CalendarDay.relativeLabel($0, today: today))" }
        HStack(spacing: 6) {
            (item.due != nil ? Icon.flag : Icon.calendarSmall).image(size: 13)
                .foregroundStyle(item.due == .overdue ? Theme.danger : GoalPalette.color(color))
            Text(item.task.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            Text(TaskItem.minutesLabel(item.task.minutes)).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
            if let carried {
                Text(carried).font(.app(11, .medium)).foregroundStyle(Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: 272, alignment: .leading)
        .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 8))
        .background(Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
        .help(helpText)
    }

    private var helpText: String {
        var lines = [item.task.title]
        if let from = item.carriedFrom { lines.append("Planned from \(CalendarDay.relativeLabel(from, today: today))") }
        else if item.planned { lines.append("Planned for this day") }
        if item.due == .overdue, let due = item.task.dueOn { lines.append("Overdue since \(CalendarDay.relativeLabel(due, today: today))") }
        else if item.due == .due { lines.append("Due this day") }
        return lines.joined(separator: "\n")
    }
}

/// Lays children out in rows, wrapping when the next doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if x > 0, x + w > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].xs.append(x)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += w + spacing
            rows[rows.count - 1].width = x - spacing
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Timeline

/// The day's hours, scrolled to about an hour before now when it opens on today.
private struct TimelineScroll: View {
    let data: CalendarData
    let offset: Int
    let now: Date
    let clock: Clock
    let actions: CalendarActions?
    let editing: BlockEditing?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DayTimeline(data: data, offset: offset, now: now, clock: clock, actions: actions, editing: editing, proxy: proxy)
            }
            .onAppear { scrollToNow(proxy) }
            .onChange(of: offset) { scrollToNow(proxy) }
        }
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        // Open on the current time, with about an hour of the past above it.
        let target = max(0, CalendarDayMath.minutes(now) / 60 - 1)
        proxy.scrollTo("hour-\(offset == 0 ? target : 7)", anchor: .top)
    }
}

/// What the calendar can change, handed down from its model.
struct CalendarActions {
    var create: (_ day: Int, _ start: Int, _ end: Int, _ goalId: String, _ title: String?) -> Void
    var saveDetails: (_ blockId: String, _ goalId: String, _ title: String?) -> Void
    var move: (_ blockId: String, _ edge: BlockEdge, _ delta: Int) -> Void
    var moveToTomorrow: (_ blockId: String) -> Void
    var toggleDone: (_ blockId: String) -> Void
    var remove: (_ blockId: String) -> Void
    /// The goal a new block starts with.
    var defaultGoalId: () -> String?
}

/// A block being named or given a goal in the popover: one being drawn, or one already there.
struct BlockEditing: Equatable {
    enum Mode: Equatable {
        case create
        case edit(blockId: String, intention: Bool)
    }

    var mode: Mode
    /// Days from today.
    var day: Int
    var start: Int
    var end: Int
    var goalId: String
    var title: String?

    var key: String {
        switch mode {
        case .create: "new-\(day)-\(start)"
        case .edit(let id, _): id
        }
    }
}

/// The timeline itself: hour lines, sleep, past time, blocks and the now line. Drag on empty
/// space to protect time; drag a block to move it, or its top or bottom edge to change its
/// length; click a block to edit it.
struct DayTimeline: View {
    let data: CalendarData
    let offset: Int
    let now: Date
    let clock: Clock
    var actions: CalendarActions?
    var proxy: ScrollViewProxy?

    @State private var editing: BlockEditing?
    @State private var drawing: Drawing?
    @State private var dragging: BlockDrag?
    @State private var width: CGFloat = 0
    @Environment(\.overlays) private var overlays

    init(data: CalendarData, offset: Int, now: Date, clock: Clock, actions: CalendarActions? = nil, editing: BlockEditing? = nil, proxy: ScrollViewProxy? = nil) {
        self.data = data
        self.offset = offset
        self.now = now
        self.clock = clock
        self.actions = actions
        self.proxy = proxy
        _editing = State(initialValue: editing)
    }

    /// Time being drawn on empty space.
    private struct Drawing {
        var from: Int
        var to: Int
        var moved = false
        /// The press only closed the popover.
        var dismissing = false
    }

    /// A block being moved, or one of its edges.
    private struct BlockDrag {
        let blockId: String
        let edge: BlockEdge
        let start: Int
        let end: Int
        var delta = 0
        var moved = false

        /// Where its edges sit right now.
        var at: (start: Int, end: Int) {
            (start + (edge == .end ? 0 : delta), end + (edge == .start ? 0 : delta))
        }
    }

    var body: some View {
        let nowMinutes = CalendarDayMath.minutes(now)
        let isToday = offset == 0
        // Earlier days are all behind you; later days haven't started.
        let pastUntil: Int? = offset < 0 ? CalendarDayMath.dayMinutes : isToday ? nowMinutes : nil
        let segments = data.blocks.flatMap { DaySegment.of($0, today: now) }.filter { $0.day == offset }

        ZStack(alignment: .topLeading) {
            // Hour lines and labels
            ForEach(0...24, id: \.self) { hour in
                let nearNow = isToday && abs(hour * 60 - nowMinutes) < 14
                ZStack(alignment: .topLeading) {
                    Text(hour < 24 ? clock.formatHour(hour) : "")
                        .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: DayGrid.gutter - 8, height: 14, alignment: .trailing)
                        .offset(y: -7)
                        .opacity(nearNow ? 0 : 1)
                    Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.leading, DayGrid.gutter)
                }
                .offset(y: DayGrid.y(hour * 60))
                .id("hour-\(hour)")
                .allowsHitTesting(false)
            }

            // Sleep
            ForEach(CalendarDayMath.sleepSpans(sleepStart: data.sleepStart, wakeTime: data.wakeTime), id: \.lowerBound) { span in
                SleepShade(showsLabel: span.upperBound - span.lowerBound >= 45)
                    .frame(height: DayGrid.y(span.upperBound) - DayGrid.y(span.lowerBound))
                    .padding(.leading, DayGrid.gutter)
                    .offset(y: DayGrid.y(span.lowerBound))
            }

            // Time that's already gone
            if let pastUntil {
                Rectangle().fill(Theme.foreground(0.03))
                    .frame(height: DayGrid.y(pastUntil) - DayGrid.pad)
                    .padding(.leading, DayGrid.gutter)
                    .offset(y: DayGrid.pad)
                    .allowsHitTesting(false)
            }

            // Empty space: drag (or click) to protect time.
            if actions != nil {
                Color.clear
                    .contentShape(.rect)
                    .padding(.leading, DayGrid.gutter)
                    .gesture(drawGesture)
            }

            // Intentions and protected time
            ForEach(segments) { segment in
                if let block = data.blocks.first(where: { $0.id == segment.blockId }) {
                    let moving = dragging.flatMap { $0.blockId == block.id && $0.moved ? $0.at : nil }
                    let start = moving?.start ?? segment.start
                    let end = moving?.end ?? segment.end
                    let midnight = CalendarDayMath.midnight(segment.day, from: now)
                    let from = midnight.addingTimeInterval(Double(start) * 60)
                    let to = midnight.addingTimeInterval(Double(end) * 60)
                    let elapsed = to > from ? now.timeIntervalSince(from) / to.timeIntervalSince(from) : 0
                    TimelineBlock(
                        block: block,
                        goal: data.goal(block.goalId),
                        start: start,
                        end: end,
                        clock: clock,
                        elapsed: min(max(elapsed, 0), 1),
                        isInteractive: actions != nil && !block.isPending,
                        isDragging: moving != nil,
                        isMenuOpen: overlays?.presented?.owner == block.id,
                        onDrag: { edge, dy in dragBlock(segment, edge: edge, dy: dy) },
                        onDragEnd: { edge in endBlockDrag(block, segment, edge: edge) },
                        onMenu: { anchor in showMenu(block, segment, anchor: anchor) }
                    )
                    .frame(height: max(DayGrid.y(end) - DayGrid.y(start) - 2, 14))
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: DayGrid.y(start) + 1)
                    .zIndex(moving != nil ? 1 : 0)
                }
            }

            // The block being drawn
            if let draft {
                DraftBlock(label: clock.formatRange(draft.start, draft.end))
                    .frame(height: DayGrid.y(draft.end) - DayGrid.y(draft.start) - 2)
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: DayGrid.y(draft.start) + 1)
                    .zIndex(2)
            }

            // Now
            if isToday {
                NowLine(label: clock.format(minutes: nowMinutes)).offset(y: DayGrid.y(nowMinutes))
                    .zIndex(3)
            }

            if let editing, editing.day == offset, isShown(editing) {
                popover(editing)
                    .zIndex(4)
            }
        }
        .frame(height: DayGrid.height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: offset) { editing = nil }
    }

    // MARK: Drawing

    /// The draft while creating: live while dragging, then held while the popover is open.
    private var draft: (start: Int, end: Int)? {
        if let drawing, drawing.moved, !drawing.dismissing {
            let start = CalendarDayMath.snapDown(min(drawing.from, drawing.to))
            return (start, max(start + CalendarDayMath.step, CalendarDayMath.snapUp(max(drawing.from, drawing.to))))
        }
        if let editing, editing.mode == .create, editing.day == offset { return (editing.start, editing.end) }
        return nil
    }

    private static func minutes(at y: CGFloat) -> Int {
        let raw = Int(((y - DayGrid.pad) / DayGrid.hour * 60).rounded())
        return min(max(raw, 0), CalendarDayMath.dayMinutes)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drawing == nil {
                    // A press elsewhere while the popover is open only closes it.
                    if editing != nil {
                        editing = nil
                        drawing = Drawing(from: 0, to: 0, dismissing: true)
                        return
                    }
                    let m = Self.minutes(at: value.startLocation.y)
                    drawing = Drawing(from: m, to: m)
                }
                guard var current = drawing, !current.dismissing else { return }
                current.to = Self.minutes(at: value.location.y)
                current.moved = current.moved || abs(value.translation.height) > 4
                drawing = current
            }
            .onEnded { _ in
                guard let current = drawing else { return }
                drawing = nil
                guard !current.dismissing, let actions else { return }
                let step = CalendarDayMath.step
                var start: Int
                var end: Int
                if !current.moved {
                    // A click: an hour from there.
                    start = CalendarDayMath.snapDown(current.from)
                    end = min(CalendarDayMath.dayMinutes, start + 60)
                    if end - start < step { start = end - step }
                } else {
                    start = CalendarDayMath.snapDown(min(current.from, current.to))
                    end = max(start + step, CalendarDayMath.snapUp(max(current.from, current.to)))
                }
                open(BlockEditing(mode: .create, day: offset, start: start, end: end, goalId: actions.defaultGoalId() ?? "", title: nil))
            }
    }

    // MARK: Moving

    private func dragBlock(_ segment: DaySegment, edge: BlockEdge, dy: CGFloat) {
        if editing != nil, dragging == nil { editing = nil }
        var current = dragging ?? BlockDrag(blockId: segment.blockId, edge: edge, start: segment.start, end: segment.end)
        let step = CalendarDayMath.step
        current.moved = current.moved || abs(dy) > 4
        let raw = Int((dy / DayGrid.hour * 60 / CGFloat(step)).rounded()) * step
        // Keep it within the day, and at least 15 minutes long when changing its length.
        let bounds: (Int, Int) = switch edge {
        case .start: (-current.start, current.end - step - current.start)
        case .end: (current.start + step - current.end, CalendarDayMath.dayMinutes - current.end)
        case .move: (-current.start, CalendarDayMath.dayMinutes - current.end)
        }
        current.delta = min(max(raw, bounds.0), bounds.1)
        dragging = current
    }

    private func endBlockDrag(_ block: CalendarBlock, _ segment: DaySegment, edge: BlockEdge) {
        guard let current = dragging else { return }
        dragging = nil
        if !current.moved {
            // A click on the block: edit it.
            if edge == .move { edit(block, segment) }
            return
        }
        if current.delta != 0 { actions?.move(block.id, current.edge, current.delta) }
    }

    // MARK: Editing

    private func edit(_ block: CalendarBlock, _ segment: DaySegment) {
        open(BlockEditing(
            mode: .edit(blockId: block.id, intention: block.isIntention),
            day: segment.day,
            start: segment.start,
            end: segment.end,
            goalId: block.goalId,
            title: block.title
        ))
    }

    private func open(_ value: BlockEditing) {
        editing = value
        // Bring it into view.
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) { proxy?.scrollTo(Self.popoverID) }
        }
    }

    private static let popoverID = "block-popover"

    /// A block's popover shows while the block is there.
    private func isShown(_ editing: BlockEditing) -> Bool {
        if case .edit(let id, _) = editing.mode { return data.blocks.contains { $0.id == id } }
        return true
    }

    private func showMenu(_ block: CalendarBlock, _ segment: DaySegment, anchor: CGRect) {
        guard let overlays, let actions else { return }
        editing = nil
        overlays.showMenu(anchor: anchor, owner: block.id) {
            MenuPanel {
                MenuItem(icon: .edit, title: "Edit") {
                    overlays.dismiss()
                    edit(block, segment)
                }
                if block.taskId != nil {
                    MenuItem(icon: block.taskDone ? .reopen : .tick, title: block.taskDone ? "Reopen task" : "Mark done") {
                        overlays.dismiss()
                        actions.toggleDone(block.id)
                    }
                }
                MenuItem(icon: .arrowForward, title: "Move to tomorrow") {
                    overlays.dismiss()
                    actions.moveToTomorrow(block.id)
                }
                MenuItem(icon: .delete, title: "Remove", isDestructive: true) {
                    overlays.dismiss()
                    actions.remove(block.id)
                }
            }
        }
    }

    /// Below the block, or above it near the end of the day.
    @ViewBuilder private func popover(_ editing: BlockEditing) -> some View {
        let intention = if case .edit(_, let intention) = editing.mode { intention } else { false }
        let weekday = CalendarDayMath.midnight(editing.day, from: now)
            .formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        let above = DayGrid.y(editing.end) + 8 + BlockPopover.estimatedHeight > DayGrid.height
        BlockPopover(
            goals: data.goals,
            goalId: editing.goalId,
            title: editing.title ?? "",
            intention: intention,
            timeLabel: "\(weekday) · \(clock.formatRange(editing.start, editing.end))",
            onSave: { goalId, title in save(editing, goalId: goalId, title: title) },
            onCancel: { self.editing = nil }
        )
        .id(editing.key)
        .frame(width: max(min(320, width - DayGrid.gutter - 24), 240))
        .alignmentGuide(.top) { d in above ? d.height - (DayGrid.y(editing.start) - 8) : -(DayGrid.y(editing.end) + 8) }
        .alignmentGuide(.leading) { _ in -(DayGrid.gutter + 12) }
        .id(Self.popoverID)
    }

    private func save(_ value: BlockEditing, goalId: String, title: String?) {
        editing = nil
        switch value.mode {
        case .create: actions?.create(value.day, value.start, value.end, goalId, title)
        case .edit(let id, _): actions?.saveDetails(id, goalId, title)
        }
    }
}

/// A block on the timeline you can move, resize, click to edit, or open ⋯ on.
private struct TimelineBlock: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let start: Int
    let end: Int
    let clock: Clock
    let elapsed: Double
    let isInteractive: Bool
    let isDragging: Bool
    let isMenuOpen: Bool
    let onDrag: (BlockEdge, CGFloat) -> Void
    let onDragEnd: (BlockEdge) -> Void
    let onMenu: (CGRect) -> Void

    @State private var isHovered = false
    @State private var moreFrame: CGRect = .zero

    var body: some View {
        BlockCardView(block: block, goal: goal, start: start, end: end, clock: clock, elapsed: elapsed, isHovered: isHovered || isMenuOpen)
            .overlay {
                if isInteractive {
                    VStack(spacing: 0) {
                        // Drag the top or bottom edge to change the length.
                        Color.clear.frame(height: 6).contentShape(.rect)
                            .pointerStyle(.frameResize(position: .top))
                            .gesture(drag(.start))
                        Spacer(minLength: 0)
                        Capsule().fill(Theme.foreground(0.2)).frame(width: 24, height: 4)
                            .opacity(isHovered && !isDragging ? 1 : 0)
                            .padding(.top, 2).padding(.bottom, 2)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .frame(height: 8)
                            .contentShape(.rect)
                            .pointerStyle(.frameResize(position: .bottom))
                            .gesture(drag(.end))
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isInteractive, !isDragging {
                    SmallMoreButton(isActive: isMenuOpen) { onMenu(moreFrame) }
                        .modifier(AnchorReader(frame: $moreFrame))
                        .padding(6)
                        .opacity(isHovered || isMenuOpen ? 1 : 0)
                }
            }
            .shadow(color: isDragging ? Color(nsColor: .rgb(0x0f1114, alpha: 0.14)) : .clear, radius: 8, y: 4)
            .contentShape(.rect(cornerRadius: 8))
            .gesture(drag(.move), including: isInteractive ? .all : .subviews)
            .pointerStyle(isDragging ? .grabActive : nil)
            .onHover { isHovered = $0 }
    }

    /// Translation in the window's space, since the block itself moves as it's dragged.
    private func drag(_ edge: BlockEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { onDrag(edge, $0.translation.height) }
            .onEnded { _ in onDragEnd(edge) }
    }
}

/// The block being drawn: a dashed outline with its time.
private struct DraftBlock: View {
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.foreground(0.04))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground(0.4), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            .overlay(alignment: .topLeading) {
                Text(label).font(.app(11, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                    .padding(.leading, 12).padding(.top, 6)
            }
            .allowsHitTesting(false)
    }
}

/// Sleep: a fine diagonal hatch, with "Sleep" in the corner when there's room.
private struct SleepShade: View {
    let showsLabel: Bool

    var body: some View {
        Hatch(color: Theme.foreground(0.06), spacing: 7)
            .overlay(alignment: .topLeading) {
                if showsLabel {
                    HStack(spacing: 4) {
                        Icon.moon.image(size: 12)
                        Text("Sleep").font(.app(11, .medium))
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 12)
                    .padding(.top, 8)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Diagonal lines ("/"), 1pt wide, like the web's `repeating-linear-gradient(135deg, …)`.
struct Hatch: View {
    let color: Color
    var spacing: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step = spacing * 2.squareRoot()
            var c: CGFloat = 0
            while c < size.width + size.height {
                path.move(to: CGPoint(x: c, y: 0))
                path.addLine(to: CGPoint(x: c - size.height, y: size.height))
                c += step
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

/// The current time: a red line across the day, a dot at its start, and the time in the gutter.
private struct NowLine: View {
    let label: String

    var body: some View {
        ZStack(alignment: .leading) {
            Text(label).font(.app(11, .semibold)).monospacedDigit()
                .foregroundStyle(Color(nsColor: .rgb(0xef4444)))
                .frame(width: DayGrid.gutter - 8, alignment: .trailing)
            Rectangle().fill(Color(nsColor: .rgb(0xef4444))).frame(height: 2)
                .padding(.leading, DayGrid.gutter)
            Circle().fill(Color(nsColor: .rgb(0xef4444))).frame(width: 10, height: 10)
                .offset(x: DayGrid.gutter - 5)
        }
        .frame(height: 14)
        .offset(y: -7)
        .allowsHitTesting(false)
    }
}

// MARK: - A block

/// An intention or protected time on the timeline: filled in up to now, an outline after.
struct BlockCardView: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let start: Int
    let end: Int
    let clock: Clock
    /// How much of it has happened, 0 to 1.
    let elapsed: Double
    /// Hovered, or its menu is open: the ⋯ takes the recap dot's place.
    var isHovered = false

    /// Height a block needs for its title and time on two lines; shorter ones get a single line.
    private static let twoLines: CGFloat = 48

    private var color: String { goal?.color ?? "slate" }
    private var title: String { block.title ?? goal?.title ?? "Protected time" }
    private var time: String { clock.formatRange(start, end) }
    private var isShort: Bool { CGFloat(end - start) / 60 * DayGrid.hour < Self.twoLines }

    var body: some View {
        GeometryReader { geometry in
            let filled = geometry.size.height * elapsed
            ZStack(alignment: .topLeading) {
                // The block, drawn filled: solid for an intention, hatched for protected time.
                Rectangle().fill(block.isIntention
                    ? GoalPalette.mix(color, light: 0.18, dark: 0.24)
                    : GoalPalette.mix(color, light: 0.10, dark: 0.13))
                if !block.isIntention {
                    Hatch(color: GoalPalette.color(color).opacity(0.26))
                }
                // A veil in the card colour over the part that hasn't happened yet.
                Rectangle().fill(Theme.card.opacity(0.72))
                    .frame(height: max(geometry.size.height - filled, 0))
                    .offset(y: filled)
                // The bar down the left edge: solid where time has passed, a soft tint ahead.
                VStack(spacing: 0) {
                    Rectangle().fill(GoalPalette.color(color)).frame(height: filled)
                    Rectangle().fill(GoalPalette.mix(color, light: 0.40, dark: 0.40))
                }
                .frame(width: 3)

                label

                if block.recapWaiting {
                    Circle().fill(GoalPalette.color(color)).frame(width: 6, height: 6)
                        .opacity(isHovered ? 0 : block.hasRecapDraft ? 1 : 0.6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .help(block.hasRecapDraft ? "Recap to review" : "Drafting recap")
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(GoalPalette.color(color).opacity(0.22)))
        }
        .opacity(block.isPending ? 0.6 : 1)
        .help("\(title) · \(time)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.isIntention ? (block.taskDone ? "Done" : "Intention") : "Protected time"): \(title), \(time)")
    }

    @ViewBuilder private var label: some View {
        let titleText = Text(title)
            .strikethrough(block.taskDone, color: Theme.foreground(0.25))
            .foregroundStyle(block.taskDone ? Theme.muted : Theme.foreground)
        let tick = Icon.tickHeavy.image(size: 9).foregroundStyle(Theme.background)
            .frame(width: 14, height: 14).background(Theme.foreground, in: .circle)

        if isShort {
            HStack(spacing: 8) {
                if block.taskDone { tick }
                titleText.font(.app(13, .medium)).lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 32)
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    if block.taskDone { tick.padding(.top, 3) }
                    titleText.font(.app(14, .medium)).lineLimit(2)
                }
                Text(time).font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 32)
        }
    }
}

extension GoalPalette {
    /// `color-mix(in oklab, var(--goal) N%, var(--card))`: the goal's colour mixed into the card's,
    /// at its own share in light and dark mode.
    static func mix(_ key: String, light: Double, dark: Double) -> Color {
        let info = colorInfo(key)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let goal = NSColor(hex: isDark ? info.dark : info.light) ?? .gray
            let card: NSColor = isDark ? .rgb(0x131417) : .rgb(0xffffff)
            return card.blended(withFraction: isDark ? dark : light, of: goal) ?? goal
        })
    }
}
