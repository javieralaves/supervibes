import SwiftUI
import UniformTypeIdentifiers

/// What first run's week can do, wired to FirstRunWeekModel in the app and to nothing in previews and tests.
struct WeekActions {
    var back: () -> Void = {}
    var start: () -> Void = {}
    var select: (WeekSelection?) -> Void = { _ in }
    /// An event (by key), and every other of its series this week, as time for a project or practice.
    var link: (String, String) -> Void = { _, _ in }
    /// A series' blocks as reserved time, or back to sessions.
    var setSeriesReserved: (String, Bool) -> Void = { _, _ in }
    /// A series as time to fill.
    var markOpen: (String) -> Void = { _ in }
    /// A series as just an event: no longer time to fill, and no longer any project's.
    var markPlain: (String) -> Void = { _ in }
    /// A project or practice dropped on a day (0 is the week's first), at minutes from midnight.
    var drop: (String, Int, Int) -> Void = { _, _, _ in }
    /// Time drawn on a day and given to a project or practice: day, start, end, goal, title, kind.
    var create: (Int, Int, Int, String, String?, NewBlockKind) -> Void = { _, _, _, _, _, _ in }
    /// A block moved or one of its edges dragged: block, edge, minutes, days.
    var move: (String, BlockEdge, Int, Int) -> Void = { _, _, _, _ in }
    var setReserved: (String, Bool) -> Void = { _, _ in }
    var remove: (String) -> Void = { _ in }
    /// On to the guide's next part.
    var next: () -> Void = {}
    var allowCalendar: () -> Void = {}
}

/// Route 1's week, full window: one line with the title and the way on, then the plate beside the week. Guided a part
/// at a time with tips where each thing first comes up.
struct FirstRunWeek: View {
    let plan: WeekPlan
    var selection: WeekSelection?
    /// The first practice dropped, while its tip shows.
    var practiceTip: WeekSelection?
    var actions = WeekActions()
    /// Where the plate's sections sit, from its top, for the tips that point at them.
    @State private var marks = PlateMarks()
    /// What's being dragged from the plate, while it is: the project or practice it gives time.
    @State private var carried: String?

    var body: some View {
        VStack(spacing: 0) {
            FirstRunSteps(current: plan.steps.count - 1, steps: plan.steps)
            HStack(spacing: 12) {
                Text("Your week ahead").font(.app(22, .semibold)).tracking(-0.55).foregroundStyle(Theme.foreground)
                Text(plan.label).font(.app(14)).foregroundStyle(Theme.muted).padding(.top, 2)
                Spacer()
                HStack(spacing: 6) {
                    Icon.calendarSmall.image(size: 14)
                    Text("Nothing changes in your Google Calendar").font(.app(12.5))
                }
                .foregroundStyle(Theme.muted)
                .padding(.trailing, 6)
                FlowButton(title: "Back", action: actions.back)
                FlowButton(title: "Start your week", primary: true, action: actions.start)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            HStack(alignment: .top, spacing: 12) {
                PlateColumn(plan: plan, marks: $marks, carried: $carried)
                PlanGrid(plan: plan, selection: selection, practiceTip: practiceTip, marks: marks, carried: carried, actions: actions)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
    }
}

/// Where the plate's sections start, from the plate's top (and so the week's, beside it): the middle of each one's
/// first row.
struct PlateMarks: Hashable {
    var quests: CGFloat?
    var projects: CGFloat?
    var practices: CGFloat?
}

// MARK: - The plate

/// The plate beside the week: what to drag in, and the time each has so far: hours for a project, a count for a
/// practice. With a season, its quests come first, numbered, and each project or practice is marked with the quest
/// it moves; what waits for next season is left off, and counted at the end.
private struct PlateColumn: View {
    let plan: WeekPlan
    @Binding var marks: PlateMarks
    @Binding var carried: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !plan.quests.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your quests").font(.app(12, .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.bottom, 2)
                    ForEach(Array(plan.quests.enumerated()), id: \.element.id) { index, quest in
                        QuestRow(quest: quest, meta: plan.meta(quest), carried: $carried)
                            .modifier(MarkReader(isOn: index == 0) { marks.quests = $0 })
                    }
                }
            }
            section("Projects", plan.projects, mark: { marks.projects = $0 }) { plan.meta($0) }
            section("Practices", plan.practices, mark: { marks.practices = $0 }) { plan.meta($0) }
            if !plan.waiting.isEmpty {
                Text("\(plan.waiting.count) waiting for next season").font(.app(11.5)).foregroundStyle(Theme.muted).padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .padding(.top, 4)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .coordinateSpace(.named(PlateColumn.space))
    }

    static let space = "plate"

    @ViewBuilder
    private func section(
        _ title: String, _ goals: [CalendarGoal], mark: @escaping (CGFloat) -> Void, meta: @escaping (CalendarGoal) -> String
    ) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(12, .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.bottom, 2)
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    PlateRow(goal: goal, meta: meta(goal), quest: plan.quest(for: goal.id)?.number, carried: $carried)
                        .modifier(MarkReader(isOn: index == 0, report: mark))
                }
            }
        }
    }
}

/// Reports the middle of a row, from the plate's top, when it's the first of its section.
private struct MarkReader: ViewModifier {
    let isOn: Bool
    let report: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if isOn {
            content.onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(PlateColumn.space)).midY } action: { report($0) }
        } else {
            content
        }
    }
}

private struct PlateRow: View {
    let goal: CalendarGoal
    let meta: String
    /// The number of the quest it moves.
    var quest: Int?
    @Binding var carried: String?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                .scaleEffect(28.0 / 24.0)
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottomTrailing) {
                    if let quest {
                        QuestMark(number: quest, size: 14)
                            .padding(2).background(Theme.card, in: .circle)
                            .offset(x: 5, y: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.title).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(meta).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        // Picked up by hand, so the week knows what's coming while it's carried and can show where it would land.
        .onDrag {
            carried = goal.id
            return NSItemProvider(object: goal.id as NSString)
        } preview: {
            HStack(spacing: 8) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                Text(goal.title).font(.app(12, .medium)).foregroundStyle(Theme.foreground)
            }
            .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        }
    }
}

/// A quest on the plate: its number, its name, and its project's hours or practice's count. Dragging it gives its
/// project or practice time.
private struct QuestRow: View {
    let quest: WeekQuest
    let meta: String
    @Binding var carried: String?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            QuestMark(number: quest.number)
            VStack(alignment: .leading, spacing: 1) {
                Text(quest.title).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(meta).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .onDrag {
            let id = quest.goalIds.first ?? ""
            carried = id
            return NSItemProvider(object: id as NSString)
        } preview: {
            HStack(spacing: 8) {
                QuestMark(number: quest.number, size: 22)
                Text(quest.title).font(.app(12, .medium)).foregroundStyle(Theme.foreground)
            }
            .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        }
    }
}

/// A quest's mark: its number, in ink, round.
struct QuestMark: View {
    let number: Int
    var size: CGFloat = 28

    var body: some View {
        Text("\(number)")
            .font(.app(size * 0.45, .semibold)).monospacedDigit()
            .foregroundStyle(Theme.background)
            .frame(width: size, height: size)
            .background(Theme.foreground, in: .circle)
    }
}

// MARK: - The week

/// The week: the whole day for each of its seven, scrolling, with the days pinned over it. Events and blocks sit on it;
/// time can be drawn on it to make a block, blocks made here can be moved and their edges dragged, and what's carried
/// from the plate shows where it would land before it's let go.
private struct PlanGrid: View {
    let plan: WeekPlan
    let selection: WeekSelection?
    let practiceTip: WeekSelection?
    let marks: PlateMarks
    /// What's being dragged from the plate, while it is.
    let carried: String?
    let actions: WeekActions

    nonisolated static let gutter: CGFloat = 52
    nonisolated static let header: CGFloat = 40
    /// An hour's height: roomy, as the calendar's.
    nonisolated static let hour: CGFloat = 56
    /// Room above midnight and below the next, so their labels aren't cut.
    nonisolated static let pad: CGFloat = 10
    nonisolated static let popoverWidth: CGFloat = 284

    @State private var width: CGFloat = 0
    @State private var position: ScrollPosition
    @State private var scrollY: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// Where what's carried is, over the week, while it's over it.
    @State private var hover: CGPoint?
    /// Something carried is over the week (from entering until it's let go or leaves). Updates after a drop are
    /// ignored, so the outline doesn't come back once it's landed.
    @State private var isCarriedOver = false
    @State private var drawing: Drawing?
    /// Time drawn, while its new block's card is open.
    @State private var creating: Drawn?
    @State private var dragging: BlockDrag?
    /// Opened on the focus hour once the hours had a size.
    @State private var focused = false
    @Environment(\.staticRendering) private var staticRendering

    init(plan: WeekPlan, selection: WeekSelection?, practiceTip: WeekSelection?, marks: PlateMarks, carried: String?, actions: WeekActions) {
        self.plan = plan
        self.selection = selection
        self.practiceTip = practiceTip
        self.marks = marks
        self.carried = carried
        self.actions = actions
        _position = State(initialValue: ScrollPosition(y: Self.focusY(plan)))
    }

    /// Opens an hour above the time it is (today), not before 7:00; on another week, at 8:00.
    private static func focusY(_ plan: WeekPlan) -> CGFloat {
        let hour = plan.now.flatMap { now in plan.dayIndex(now).map { _ in CalendarDayMath.minutes(now) / 60 - 1 } } ?? 8
        // A little above the hour's line, so its label shows.
        return pad + CGFloat(min(max(hour, 7), 15)) * Self.hour - 14
    }

    var body: some View {
        let layout = Layout(width: width)
        VStack(spacing: 0) {
            dayHeaders(layout)
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            if staticRendering {
                // Snapshots draw the hours as they open, from the focus hour, without a scroll view to settle.
                Color.clear
                    .overlay(alignment: .topLeading) {
                        content(layout).frame(width: max(width, 1), height: layout.contentHeight, alignment: .topLeading)
                            .offset(y: -Self.focusY(plan))
                    }
                    .clipped()
            } else {
                ScrollView {
                    content(layout).frame(width: max(width, 1), height: layout.contentHeight, alignment: .topLeading)
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: [CGFloat].self) { [$0.contentOffset.y, $0.containerSize.height] } action: { _, value in
                    scrollY = value[0]
                    viewport = value[1]
                    // Open on the focus hour once there's a size to scroll in (by position: the hours are placed with
                    // offsets, which layout doesn't see).
                    if !focused, viewport > 0 {
                        focused = true
                        position.scrollTo(y: Self.focusY(plan))
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay(alignment: .topLeading) { pinnedTips(layout) }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    struct Layout {
        let width: CGFloat
        var column: CGFloat { max(1, (width - PlanGrid.gutter) / 7) }
        var contentHeight: CGFloat { PlanGrid.pad * 2 + 24 * PlanGrid.hour }

        func x(_ day: Int) -> CGFloat { PlanGrid.gutter + column * CGFloat(day) }
        func y(_ minutes: Int) -> CGFloat { PlanGrid.pad + CGFloat(minutes) / 60 * PlanGrid.hour }

        /// Where something from `start` to `end` minutes on a day sits, inset a little within its column.
        func frame(day: Int, start: Int, end: Int) -> CGRect {
            let to = min(max(end, start + 15), CalendarDayMath.dayMinutes)
            return CGRect(x: x(day) + 4, y: y(start) + 1.5, width: column - 8, height: max(18, y(to) - y(start) - 3))
        }

        func frame(day: Int, start: Date, end: Date) -> CGRect {
            let from = CalendarDayMath.minutes(start)
            let length = Int(end.timeIntervalSince(start) / 60)
            return frame(day: day, start: from, end: from + length)
        }

        /// Minutes from midnight at a point on the week, to the quarter hour.
        func minutes(at y: CGFloat) -> Int {
            let raw = Double((y - PlanGrid.pad) / PlanGrid.hour) * 60
            return min(max(Int((raw / 15).rounded()) * 15, 0), CalendarDayMath.dayMinutes)
        }

        /// Minutes at a point, as is, for drawing (snapped once the span is known).
        func rawMinutes(at y: CGFloat) -> Int {
            min(max(Int(Double((y - PlanGrid.pad) / PlanGrid.hour) * 60), 0), CalendarDayMath.dayMinutes)
        }

        func day(at x: CGFloat) -> Int { min(max(Int((x - PlanGrid.gutter) / column), 0), 6) }
    }

    // MARK: Days and hours

    private func dayHeaders(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                let isToday = plan.now.map { plan.dayIndex($0) == index } ?? false
                HStack(spacing: 6) {
                    Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).locale(WeekPlan.locale)))
                        .foregroundStyle(isToday ? Theme.foreground : Theme.muted)
                        .fontWeight(isToday ? .semibold : .medium)
                    Text(day.formatted(.dateTime.day().locale(WeekPlan.locale))).monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                }
                .font(.app(12.5, .medium))
                .padding(.leading, 10)
                .frame(width: layout.column, height: Self.header, alignment: .leading)
                .offset(x: layout.x(index))
            }
            ForEach(0..<7, id: \.self) { day in
                Rectangle().fill(Theme.cardBorder).frame(width: 1, height: Self.header).offset(x: layout.x(day))
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.header, maxHeight: Self.header, alignment: .topLeading)
    }

    private func content(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            hourLines(layout)
            ForEach(0..<7, id: \.self) { day in
                dayColumn(day, layout: layout)
            }
            dropTarget(layout)
            draft(layout)
            nowLine(layout)
            overlays(layout)
        }
        .coordinateSpace(.named(Self.space))
        // One drop area over the whole week, the day worked out from where it's let go; it follows what's carried, to
        // show where it would land.
        .onDrop(of: [.text], delegate: WeekDrop(
            onEnter: { point in
                isCarriedOver = true
                hover = point
            },
            onMove: { point in if isCarriedOver { hover = point } },
            onLeave: {
                isCarriedOver = false
                hover = nil
            },
            onDrop: { point, provider in
                // Where the outline showed, so it lands where it said it would (the drop's own point can round to
                // the next quarter hour).
                let shown = hover ?? point
                isCarriedOver = false
                hover = nil
                // And once more after this turn, in case a last update arrives as the drop finishes.
                Task { @MainActor in hover = nil }
                return drop(at: shown, provider: provider, layout: layout)
            }
        ))
    }

    static let space = "planGrid"

    private func hourLines(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                if hour > 0 && hour < 24 {
                    Rectangle().fill(Theme.foreground(0.045)).frame(width: max(0, layout.width - Self.gutter), height: 1)
                        .offset(x: Self.gutter, y: layout.y(hour * 60))
                }
                Text(String(format: "%d:00", hour % 24)).font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(width: Self.gutter - 10, alignment: .trailing)
                    .offset(y: layout.y(hour * 60) - 7)
                    .opacity(hour == 0 || hour == 24 ? 0 : 1)
            }
            ForEach(0..<7, id: \.self) { day in
                Rectangle().fill(Theme.cardBorder).frame(width: 1, height: layout.contentHeight).offset(x: layout.x(day))
            }
        }
    }

    private func dayColumn(_ day: Int, layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            // Empty time: pressed and dragged, it's drawn as a new block.
            Color.clear.contentShape(.rect).gesture(drawGesture(day, layout: layout))
            ForEach(plan.events.filter { plan.dayIndex($0.start) == day && !isAllDay($0) && !isFilled($0) }) { event in
                let frame = layout.frame(day: day, start: event.start, end: event.end)
                EventBlock(event: event, isOpen: plan.isOpen(event), isActive: selection == .event(event.key), height: frame.height)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX - layout.x(day), y: frame.minY)
                    .onTapGesture { select(.event(event.key)) }
            }
            ForEach(plan.blocks.filter { plan.dayIndex($0.startsAt) == day }) { block in
                if let goal = plan.goal(block.goalId) {
                    goalBlock(block, goal: goal, day: day, layout: layout)
                }
            }
        }
        .frame(width: layout.column, height: layout.contentHeight)
        .offset(x: layout.x(day))
    }

    /// A block, where a drag of it or its edges would put it; made here (not from an event), it can be moved and
    /// lengthened.
    private func goalBlock(_ block: CalendarBlock, goal: CalendarGoal, day: Int, layout: Layout) -> some View {
        let start = CalendarDayMath.minutes(block.startsAt)
        let end = start + Int(block.endsAt.timeIntervalSince(block.startsAt) / 60)
        let drag = dragging.flatMap { $0.blockId == block.id && $0.moved ? $0 : nil }
        let shownDay = day + (drag?.dayDelta ?? 0)
        let shownStart = start + (drag.map { $0.edge == .end ? 0 : $0.delta } ?? 0)
        let shownEnd = end + (drag.map { $0.edge == .start ? 0 : $0.delta } ?? 0)
        let frame = layout.frame(day: shownDay, start: shownStart, end: shownEnd)
        let canChange = block.source == nil && !block.isPending
        return GoalBlock(
            block: block, goal: goal, count: goal.isPractice ? "\(plan.ordinal(of: block)) of \(goal.perWeek ?? 1) this week" : nil,
            quest: plan.quest(for: goal.id)?.number, isActive: isSelected(block), height: frame.height,
            times: drag != nil ? "\(clock(shownStart))–\(clock(shownEnd))" : nil
        )
        .frame(width: frame.width, height: frame.height)
        .shadow(color: .black.opacity(drag != nil ? 0.18 : 0), radius: 10, y: 6)
        .overlay(alignment: .top) { if canChange { edge(.start, block: block, day: day, start: start, end: end, layout: layout) } }
        .overlay(alignment: .bottom) { if canChange { edge(.end, block: block, day: day, start: start, end: end, layout: layout) } }
        .gesture(canChange ? blockGesture(.move, block: block, day: day, start: start, end: end, layout: layout) : nil)
        .onTapGesture { if !canChange { select(.block(block.id)) } }
        .offset(x: frame.minX - layout.x(day), y: frame.minY)
        .zIndex(drag != nil ? 2 : 0)
    }

    /// A block's top or bottom edge, a few points tall, that lengthens or shortens it.
    private func edge(_ edge: BlockEdge, block: CalendarBlock, day: Int, start: Int, end: Int, layout: Layout) -> some View {
        Color.clear
            .frame(height: 7)
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: edge == .start ? .top : .bottom))
            .gesture(blockGesture(edge, block: block, day: day, start: start, end: end, layout: layout))
    }

    private func blockGesture(_ edge: BlockEdge, block: CalendarBlock, day: Int, start: Int, end: Int, layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                var current = dragging ?? BlockDrag(blockId: block.id, day: day, edge: edge, start: start, end: end)
                let step = CalendarDayMath.step
                current.moved = current.moved || hypot(value.translation.width, value.translation.height) > 4
                guard current.moved else { return dragging = current }
                if selection != nil { actions.select(nil) }
                creating = nil
                let raw = Int((value.translation.height / Self.hour * 60 / CGFloat(step)).rounded()) * step
                let bounds: (Int, Int) = switch edge {
                case .start: (-current.start, current.end - step - current.start)
                case .end: (current.start + step - current.end, CalendarDayMath.dayMinutes - current.end)
                case .move: (-current.start, CalendarDayMath.dayMinutes - current.end)
                }
                current.delta = min(max(raw, bounds.0), bounds.1)
                if edge == .move {
                    let days = Int((value.translation.width / layout.column).rounded())
                    current.dayDelta = min(max(days, -current.day), 6 - current.day)
                }
                dragging = current
            }
            .onEnded { _ in
                guard let current = dragging else { return }
                dragging = nil
                // Pressed and let go without moving: a click, which opens it.
                guard current.moved else { return select(.block(block.id)) }
                if current.delta != 0 || current.dayDelta != 0 {
                    actions.move(block.id, current.edge, current.delta, current.dayDelta)
                }
            }
    }

    // MARK: Drawing a block

    private func drawGesture(_ day: Int, layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drawing == nil {
                    // A press elsewhere while something's open only closes it.
                    if creating != nil || selection != nil {
                        creating = nil
                        actions.select(nil)
                        drawing = Drawing(day: day, from: 0, to: 0, dismissing: true)
                        return
                    }
                    let m = layout.rawMinutes(at: value.startLocation.y)
                    drawing = Drawing(day: day, from: m, to: m)
                }
                guard var current = drawing, !current.dismissing else { return }
                current.to = layout.rawMinutes(at: value.location.y)
                current.moved = current.moved || abs(value.translation.height) > 4
                drawing = current
            }
            .onEnded { _ in
                guard let current = drawing else { return }
                drawing = nil
                guard !current.dismissing, !plan.activeGoals.isEmpty else { return }
                let span = current.span
                creating = Drawn(day: current.day, start: span.start, end: span.end)
            }
    }

    /// The time being drawn, or drawn and waiting for its card: outlined in ink, with its times.
    @ViewBuilder
    private func draft(_ layout: Layout) -> some View {
        if let span = drawing.flatMap({ $0.dismissing ? nil : Drawn(day: $0.day, start: $0.span.start, end: $0.span.end) }) ?? creating {
            let frame = layout.frame(day: span.day, start: span.start, end: span.end)
            Outline(label: "\(clock(span.start))–\(clock(span.end))", color: nil)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
    }

    // MARK: Dropping from the plate

    /// How long what's carried would be: two hours for a project, a practice's own length (an hour at least half).
    private func length(of goalId: String?) -> Int {
        guard let goal = goalId.flatMap(plan.goal) else { return 60 }
        return goal.isPractice ? max(goal.minMinutes ?? 60, 30) : 120
    }

    /// Where it would land, while it's carried over the week: its day washed, and its time outlined in its colour.
    @ViewBuilder
    private func dropTarget(_ layout: Layout) -> some View {
        if let hover, hover.x >= Self.gutter {
            let day = layout.day(at: hover.x)
            let start = min(layout.minutes(at: hover.y), CalendarDayMath.dayMinutes - 15)
            let end = min(start + length(of: carried), CalendarDayMath.dayMinutes)
            let frame = layout.frame(day: day, start: start, end: end)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.foreground(0.025))
                    .frame(width: layout.column, height: layout.contentHeight)
                    .offset(x: layout.x(day))
                Outline(label: "\(clock(start))–\(clock(end))", color: carried.flatMap(plan.goal)?.color)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.08), value: start)
        }
    }

    private func drop(at point: CGPoint, provider: NSItemProvider?, layout: Layout) -> Bool {
        guard point.x >= Self.gutter else { return false }
        let day = layout.day(at: point.x)
        let start = min(layout.minutes(at: point.y), CalendarDayMath.dayMinutes - 15)
        if let id = carried, plan.goal(id) != nil {
            actions.drop(id, day, start)
            return true
        }
        guard let provider else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            Task { @MainActor in if plan.goal(id) != nil { actions.drop(id, day, start) } }
        }
        return true
    }

    // MARK: Now

    /// The time it is, across today: a red line with a dot at its start, and the time in the gutter, as on the
    /// calendar.
    @ViewBuilder
    private func nowLine(_ layout: Layout) -> some View {
        if let now = plan.now, let day = plan.dayIndex(now) {
            let minutes = CalendarDayMath.minutes(now)
            let red = Color(nsColor: .rgb(0xef4444))
            ZStack(alignment: .topLeading) {
                Text(WeekPlan.clock(now)).font(.app(10.5, .semibold)).monospacedDigit().foregroundStyle(red)
                    .frame(width: Self.gutter - 6, alignment: .trailing)
                    .background(Theme.card)
                    .offset(y: -7)
                Rectangle().fill(red).frame(width: layout.column, height: 2)
                    .offset(x: layout.x(day), y: -1)
                Circle().fill(red).frame(width: 9, height: 9)
                    .offset(x: layout.x(day) - 4.5, y: -4.5)
            }
            .offset(y: layout.y(minutes))
            .allowsHitTesting(false)
        }
    }

    private func isAllDay(_ event: ExternalEvent) -> Bool { event.end.timeIntervalSince(event.start) >= 20 * 3600 }

    /// Time to fill that a block now sits in: filled, so it's no longer drawn.
    private func isFilled(_ event: ExternalEvent) -> Bool {
        plan.isOpen(event) && plan.blocks.contains { $0.startsAt < event.end && $0.endsAt > event.start }
    }

    private func isSelected(_ block: CalendarBlock) -> Bool {
        switch selection {
        case .block(let id): id == block.id
        case .placed(let goalId, let startsAt): goalId == block.goalId && startsAt == block.startsAt
        default: false
        }
    }

    private func select(_ selection: WeekSelection) {
        creating = nil
        actions.select(selection)
    }

    private func clock(_ minutes: Int) -> String { String(format: "%d:%02d", (minutes / 60) % 24, minutes % 60) }

    // MARK: Popovers and tips

    /// Keeps something `height` tall that wants to start at `y` within what's showing of the week.
    private func inView(_ y: CGFloat, height: CGFloat) -> CGFloat {
        if staticRendering { return max(Self.focusY(plan) + 8, y) }
        guard viewport > 0 else { return y }
        return max(scrollY + 8, min(y, scrollY + viewport - height - 12))
    }

    @ViewBuilder
    private func overlays(_ layout: Layout) -> some View {
        if let creating {
            let frame = layout.frame(day: creating.day, start: creating.start, end: creating.end)
            let right = frame.maxX + 10 + Self.popoverWidth < layout.width
            let x = right ? frame.maxX + 10 : frame.minX - 10 - Self.popoverWidth
            NewBlockPopover(
                goals: plan.activeGoals, tasks: [], goalId: plan.quests.first?.goalIds.first ?? plan.activeGoals.first?.id ?? "",
                timeLabel: newLabel(creating),
                onAdd: { goalId, title, kind in
                    self.creating = nil
                    actions.create(creating.day, creating.start, creating.end, goalId, title, kind)
                },
                onCancel: { self.creating = nil }
            )
            .id("\(creating.day)-\(creating.start)-\(creating.end)")
            .frame(width: Self.popoverWidth)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: x, y: inView(frame.minY - 8, height: NewBlockPopover.estimatedHeight))
        } else if let (frame, popover, height) = popover(layout) {
            let right = frame.maxX + 10 + Self.popoverWidth < layout.width
            let x = right ? frame.maxX + 10 : frame.minX - 10 - Self.popoverWidth
            popover
                .frame(width: Self.popoverWidth)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: x, y: inView(frame.minY - 8, height: height))
        }
        blockTips(layout)
    }

    /// "Tue 1 · 14:00–15:00", for a new block's card.
    private func newLabel(_ drawn: Drawn) -> String {
        let day = plan.days[min(max(drawn.day, 0), plan.days.count - 1)]
        let name = day.formatted(.dateTime.weekday(.abbreviated).day().locale(WeekPlan.locale))
        return "\(name) · \(clock(drawn.start))–\(clock(drawn.end))"
    }

    /// The popover for what's selected, where it points, and about how tall it is, so it can be kept on the week.
    private func popover(_ layout: Layout) -> (CGRect, AnyView, CGFloat)? {
        switch selection {
        case .event(let key):
            guard let event = plan.events.first(where: { $0.key == key }), let day = plan.dayIndex(event.start) else { return nil }
            let frame = layout.frame(day: day, start: event.start, end: event.end)
            let series = WeekPlan.series(event.key)
            return (frame, AnyView(EventQuestion(
                title: event.title,
                when: plan.when(event.title, start: event.start, end: event.end, key: event.key, repeats: event.repeats),
                answer: plan.isOpen(event) ? .open : .event,
                goals: plan.activeGoals,
                onLink: { actions.link(event.key, $0) },
                onReserved: { actions.setSeriesReserved(series, $0) },
                onOpen: { actions.markOpen(series) },
                onPlain: { actions.markPlain(series) },
                onClose: { actions.select(nil) }
            )), 300)
        case .block, .placed:
            guard let block = plan.blocks.first(where: isSelected), let day = plan.dayIndex(block.startsAt), let goal = plan.goal(block.goalId) else { return nil }
            let frame = layout.frame(day: day, start: block.startsAt, end: block.endsAt)
            if let source = block.source {
                let series = WeekPlan.series(source.key)
                return (frame, AnyView(EventQuestion(
                    title: source.snapshot.title,
                    when: plan.when(source.snapshot.title, start: source.snapshot.startsAt, end: source.snapshot.endsAt, key: source.key, repeats: source.key.contains("|")),
                    answer: .goal(goal.id, reserved: block.reserved),
                    goals: plan.activeGoals,
                    onLink: { actions.link(source.key, $0) },
                    onReserved: { actions.setSeriesReserved(series, $0) },
                    onOpen: { actions.markOpen(series) },
                    onPlain: { actions.markPlain(series) },
                    onClose: { actions.select(nil) }
                )), goal.isPractice ? 360 : 480)
            }
            return (frame, AnyView(BlockQuestion(
                block: block, goal: goal,
                onReserved: { actions.setReserved(block.id, $0) },
                onRemove: { actions.remove(block.id) },
                onClose: { actions.select(nil) }
            )), goal.isPractice ? 140 : 300)
        case nil:
            return nil
        }
    }

    /// The tips that point at something on the week, scrolling with it: the first practice dropped, and the first
    /// event, while the calendar is being looked at.
    @ViewBuilder
    private func blockTips(_ layout: Layout) -> some View {
        if selection == nil, creating == nil {
            if let practiceTip, let block = plan.blocks.first(where: { matches($0, practiceTip) }),
               let day = plan.dayIndex(block.startsAt), let goal = plan.goal(block.goalId) {
                let frame = layout.frame(day: day, start: block.startsAt, end: block.endsAt)
                let right = frame.maxX + 240 < layout.width
                WeekTip(kicker: "Your practices", nib: right ? .left : .right, onNext: actions.next) {
                    Text("\(Text("That’s \(plan.ordinal(of: block)) of \(goal.perWeek ?? 1) \(goal.title) this week.").fontWeight(.semibold)) Every time you put a practice on your week counts toward it.")
                }
                .offset(x: right ? frame.maxX + 12 : frame.minX - 232, y: frame.minY - 4)
            } else if plan.stage == .calendar, plan.calendar == .ready, let first = firstEvent, let day = plan.dayIndex(first.start) {
                let frame = layout.frame(day: day, start: first.start, end: first.end)
                let right = frame.maxX + 240 < layout.width
                WeekTip(kicker: "Your calendar", nib: right ? .left : .right, onNext: actions.next) {
                    Text("These are from your Google Calendar. Click any of them to say if it’s time for one of your projects or practices.")
                }
                .offset(x: right ? frame.maxX + 12 : frame.minX - 232, y: frame.minY - 4)
            }
        }
    }

    /// The tips that point at the plate, beside it at the height of the section they're about, and the calendar's
    /// card; these stay put while the week scrolls.
    @ViewBuilder
    private func pinnedTips(_ layout: Layout) -> some View {
        if selection == nil, creating == nil, practiceTip == nil {
            switch plan.stage {
            case .calendar:
                if plan.calendar != .ready {
                    CalendarAccessCard(state: plan.calendar, onAllow: actions.allowCalendar, onSkip: actions.next)
                        .frame(width: 360)
                        .offset(x: (layout.width - 360) / 2 + Self.gutter / 2, y: Self.header + 120)
                }
            case .projects:
                WeekTip(kicker: plan.quests.isEmpty ? "Your projects" : "Your quests", nib: .left, onNext: actions.next) {
                    Text("\(plan.quests.isEmpty ? "Drag a project onto your week to give it time." : "Start with your quests: drag one onto your week to give it time.")\(plan.open.isEmpty ? "" : " Time to fill is a good place to start.")")
                }
                .offset(x: 10, y: pointing(at: plan.quests.isEmpty ? marks.projects : marks.quests))
            case .practices:
                WeekTip(kicker: "Your practices", nib: .left, onNext: actions.next) {
                    Text("Drag a practice in too. Each time on your week counts toward how often you want it.")
                }
                .offset(x: 10, y: pointing(at: marks.practices))
            case .done:
                EmptyView()
            }
        }
    }

    /// Where a tip goes so its nib points at a row in the middle at `mark` (the nib sits 19 points down the tip).
    private func pointing(at mark: CGFloat?) -> CGFloat {
        guard let mark else { return Self.header + 16 }
        return max(8, mark - 19)
    }

    private var firstEvent: ExternalEvent? {
        plan.events.filter { !isAllDay($0) && CalendarDayMath.minutes($0.end) > 8 * 60 }
            .min { ($0.start, $0.key) < ($1.start, $1.key) }
    }

    private func matches(_ block: CalendarBlock, _ selection: WeekSelection) -> Bool {
        switch selection {
        case .block(let id): id == block.id
        case .placed(let goalId, let startsAt): goalId == block.goalId && startsAt == block.startsAt
        case .event: false
        }
    }

    // MARK: State

    /// Time being drawn on one day.
    private struct Drawing {
        let day: Int
        var from: Int
        var to: Int
        var moved = false
        /// The press only closed what was open.
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
            return (start, min(CalendarDayMath.dayMinutes, max(start + step, CalendarDayMath.snapUp(max(from, to)))))
        }
    }

    /// Time drawn on a day, in minutes.
    private struct Drawn: Hashable {
        let day: Int
        let start: Int
        let end: Int
    }

    /// A block, or one of its edges, being dragged: how far in minutes and (moving it) days.
    private struct BlockDrag {
        let blockId: String
        let day: Int
        let edge: BlockEdge
        let start: Int
        let end: Int
        var delta = 0
        var dayDelta = 0
        var moved = false
    }
}

/// Follows what's carried over the week, and takes it when it's let go.
private struct WeekDrop: DropDelegate {
    let onEnter: (CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onLeave: () -> Void
    let onDrop: (CGPoint, NSItemProvider?) -> Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) { onEnter(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        onMove(info.location)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { onLeave() }
    func performDrop(info: DropInfo) -> Bool { onDrop(info.location, info.itemProviders(for: [.text]).first) }
}

/// Time about to become a block: drawn, or where something carried would land. Dashed, in its colour (or ink), with
/// its times.
private struct Outline: View {
    let label: String
    let color: String?

    var body: some View {
        let tint = color.map { GoalPalette.color($0) } ?? Theme.foreground
        Text(label)
            .font(.app(11, .semibold)).monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.map { GoalPalette.tintBackground($0) } ?? Theme.foreground(0.05))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
    }
}

// MARK: - Blocks

/// One of the calendar's events: plain grey, or hatched and faded as time to fill.
private struct EventBlock: View {
    let event: ExternalEvent
    let isOpen: Bool
    let isActive: Bool
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title).font(.app(11.5, .medium)).lineLimit(height > 40 ? 2 : 1)
                .foregroundStyle(isOpen ? Theme.muted.opacity(0.75) : Theme.foreground(0.6))
            if height > 44 {
                Text(isOpen ? "Time to fill" : "\(WeekPlan.clock(event.start))–\(WeekPlan.clock(event.end))")
                    .font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.muted.opacity(isOpen ? 0.7 : 0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if isOpen {
                Hatch(color: Theme.foreground(0.07), spacing: 5).clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Theme.foreground(0.055))
            }
        }
        .overlay { if isOpen { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground(0.07)) } }
        .overlay { if isActive { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground, lineWidth: 2) } }
        .contentShape(.rect(cornerRadius: 8))
    }
}

/// Time for a project or practice: filled in its colour for a session or a practice, hatched in it for reserved time,
/// with the calendar's mark when it came from an event.
private struct GoalBlock: View {
    let block: CalendarBlock
    let goal: CalendarGoal
    /// For a practice: "1 of 3 this week".
    let count: String?
    /// The number of the quest it moves.
    var quest: Int?
    let isActive: Bool
    let height: CGFloat
    /// Its times while it's dragged, in place of its subtitle.
    var times: String?

    private var title: String { block.source?.snapshot.title ?? goal.title }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Capsule().fill(GoalPalette.color(goal.color).opacity(0.7)).frame(width: 2.5).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 4) {
                    Text(title).font(.app(11.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(height > 48 ? 2 : 1)
                    Spacer(minLength: 0)
                    if let quest {
                        QuestMark(number: quest, size: 14)
                    }
                    if block.source != nil {
                        Icon.calendarSmall.image(size: 10).foregroundStyle(Theme.muted)
                    }
                }
                if height > 40 {
                    Text(subtitle).font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if block.reserved {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    Hatch(color: GoalPalette.color(goal.color).opacity(0.2), spacing: 5).clipShape(.rect(cornerRadius: 8))
                }
            } else {
                // On the card first, so nothing under the block shows through its tint.
                RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8).fill(GoalPalette.tintBackground(goal.color)))
            }
        }
        .overlay { if block.reserved && !isActive { RoundedRectangle(cornerRadius: 8).strokeBorder(GoalPalette.color(goal.color).opacity(0.3)) } }
        .overlay { if isActive { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground, lineWidth: 2) } }
        .opacity(block.isPending ? 0.7 : 1)
        .contentShape(.rect(cornerRadius: 8))
    }

    private var subtitle: String {
        if let times { return times }
        if let count { return count }
        if block.source != nil { return block.reserved ? "\(goal.title) · Reserved" : goal.title }
        return block.reserved ? "Reserved" : "\(WeekPlan.clock(block.startsAt))–\(WeekPlan.clock(block.endsAt))"
    }
}
