import SwiftUI

/*
 * The Plan page's day, beside the lanes: the waking day split into sessions, reserved time and
 * what's free, then the day hour by hour with its blocks drawn as the day view draws them (sessions
 * hatched, reserved time plain), opening on the waking hours. It is the calendar's own day
 * (DayTimeline): drag on free time to protect some, drag a block or its edges to move or resize it,
 * ⋯ to edit, reserve, move or remove it, and pinch to make the hours taller or shorter. Click
 * protected time to give some or all of it to another goal, or to switch it between a session and
 * reserved; click a scheduled task's block to edit it.
 */

struct PlanTimeline: View {
    let data: CalendarData
    /// Days from today.
    let offset: Int
    let now: Date
    let clock: Clock
    /// "Fri, Nov 20".
    let dayLabel: String
    /// Moving, resizing, drawing and editing blocks, as on the calendar; without it the day is read-only.
    var actions: CalendarActions?
    /// The block standing for time being given, drawn as a dashed outline.
    var ghostId: String?
    /// Who it's being given to.
    var ghostGoal: CalendarGoal?
    /// Opens with this block's popover showing, for previews and snapshot tests.
    var initiallySelected: String?
    /// How tall an hour is, kept between visits; nil (or no binding) fits the waking day.
    var storedHour: Binding<CGFloat?>?
    /// False draws the day without a scroll view, opened on waking: snapshot tests can't scroll.
    var scrolls = true
    /// Protected time was clicked, with its frame in the overlay layer.
    let onSelect: (CalendarBlock, CGRect) -> Void

    @Environment(\.overlays) private var overlays
    @State private var position = ScrollPosition()
    @State private var scrollY: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// The day it last opened on its focus, so it does so once the scroll view has a size.
    @State private var focusedOffset: Int?
    @State private var ownHour: CGFloat?
    /// The hour height mid-pinch, saved when it ends.
    @State private var pinchHour: CGFloat?
    /// Where a pinch last scrolled to, applied again once the content has its new height.
    @State private var pinchY: CGFloat?
    /// A block being named or given a goal in the calendar's popover: one just drawn, or one opened.
    @State private var editing: BlockEditing?
    /// The day's frame in the overlay layer, to anchor a block's popover beside it.
    @State private var dayFrame = CGRect.zero
    @State private var didShowInitially = false

    private static let pad: CGFloat = DayGrid.pad

    /// Pinching goes from the whole day in view up to the day view's tallest hours.
    private var range: ClosedRange<CGFloat> { HourGrid.range(viewport: viewport, pad: Self.pad, most: DayGrid.maxHour) }

    /// Until pinched, hours tall enough for the waking day to fill the column.
    private var fitAwake: CGFloat {
        let awake = (data.sleepStart - data.wakeTime + CalendarDayMath.dayMinutes) % CalendarDayMath.dayMinutes
        guard viewport > 0, awake > 0 else { return 44 }
        return (viewport - Self.pad * 2) / (CGFloat(awake) / 60)
    }

    private var grid: HourGrid {
        let hour = pinchHour ?? storedHour?.wrappedValue ?? ownHour ?? fitAwake
        return HourGrid(hour: min(max(hour, range.lowerBound), range.upperBound), pad: Self.pad)
    }

    /// The block whose give-time popover is open.
    private var openBlockId: String? {
        guard let owner = overlays?.presented?.owner, owner.hasPrefix("plan-block#") else { return nil }
        return String(owner.dropFirst("plan-block#".count))
    }

    var body: some View {
        let grid = grid
        VStack(spacing: 0) {
            DayBudgetView(budget: data.budget(day: offset, now: now), goals: data.goals, dayLabel: dayLabel, awake: awakeLabel)
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            ScrollViewReader { proxy in
                if scrolls {
                    ScrollView(.vertical) {
                        content(grid, proxy: proxy)
                    }
                    .scrollIndicators(.never)
                    .scrollPosition($position)
                    .onScrollGeometryChange(for: [CGFloat].self) {
                        [$0.contentOffset.y, $0.containerSize.height]
                    } action: { _, value in
                        scrollY = value[0]
                        viewport = value[1]
                        if let y = pinchY {
                            // The scroll may have been held to the old height; once the new one is in, go there.
                            pinchY = nil
                            if abs(scrollY - y) > 0.5 { position.scrollTo(y: y) }
                        }
                        if focusedOffset != offset { scrollToFocus() }
                    }
                    .onChange(of: offset) {
                        editing = nil
                        scrollToFocus()
                    }
                } else {
                    // Over a frame that takes only the room it's given, so the whole day doesn't size the page.
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
                        .overlay(alignment: .top) {
                            content(grid, proxy: proxy)
                                .offset(y: -grid.scrollY(keeping: CGFloat(focus / 60 * 60), at: Self.pad, viewport: viewport))
                        }
                        .clipped()
                }
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    /// The calendar's own day, with time being given drawn over it, and pinching.
    private func content(_ grid: HourGrid, proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            DayTimeline(
                data: data, offset: offset, now: now, clock: clock, actions: actions, editing: $editing,
                selectedId: openBlockId, onSelect: { select($0, grid: grid) }, onGive: { select($0, grid: grid) }, proxy: proxy
            )
            if let ghostId, let ghostGoal {
                ForEach(segments(of: ghostId), id: \.id) { segment in
                    GhostBlock(minutes: segment.end - segment.start, goal: ghostGoal)
                        .frame(height: max(grid.height(segment.end - segment.start), 16) - 2)
                        .padding(.leading, DayGrid.gutter + 4)
                        .padding(.trailing, 8)
                        .offset(y: grid.y(segment.start) + 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: grid.height, alignment: .top)
        .environment(\.dayGrid, grid)
        .modifier(AnchorReader(frame: $dayFrame))
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
        .onChange(of: dayFrame) {
            guard let initiallySelected, !didShowInitially, dayFrame != .zero else { return }
            didShowInitially = true
            select(initiallySelected, grid: grid)
        }
    }

    /// A click on a block: protected time opens its popover beside it; a scheduled task edits in place.
    private func select(_ blockId: String, grid: HourGrid) {
        guard let block = data.blocks.first(where: { $0.id == blockId }),
              let segment = DaySegment.of(block, today: now).first(where: { $0.day == offset }) else { return }
        if block.isIntention {
            editing = BlockEditing(
                mode: .edit(blockId: block.id, intention: true), day: segment.day, start: segment.start, end: segment.end,
                goalId: block.goalId, title: block.title
            )
            return
        }
        let top = grid.y(segment.start)
        let anchor = CGRect(
            x: dayFrame.minX + DayGrid.gutter + 4, y: dayFrame.minY + top,
            width: dayFrame.width - DayGrid.gutter - 12, height: grid.y(segment.end) - top
        )
        onSelect(block, anchor)
    }

    private func segments(of blockId: String) -> [DaySegment] {
        data.blocks.first { $0.id == blockId }.map { DaySegment.of($0, today: now).filter { $0.day == offset } } ?? []
    }

    /// Where it opens: waking up, or on today an hour before now.
    private var focus: Int {
        offset == 0 ? max(data.wakeTime, CalendarDayMath.minutes(now) - 60) : data.wakeTime
    }

    private func scrollToFocus() {
        guard viewport > 0 else { return }
        focusedOffset = offset
        position.scrollTo(y: grid.scrollY(keeping: CGFloat(focus / 60 * 60), at: Self.pad, viewport: viewport))
    }

    /// "Awake 7:00 AM – 11:00 PM".
    private var awakeLabel: String {
        "Awake \(clock.format(minutes: data.wakeTime)) – \(clock.format(minutes: data.sleepStart))"
    }
}

/// Time being given, previewed: a dashed outline in the other goal's colour.
private struct GhostBlock: View {
    let minutes: Int
    let goal: CalendarGoal

    var body: some View {
        Text("+\(BoardDuration.text(minutes)) for \(goal.title)")
            .font(.app(13, .medium)).monospacedDigit()
            .foregroundStyle(GoalPalette.color(goal.color))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(GoalPalette.mix(goal.color, light: 0.08, dark: 0.12), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(GoalPalette.color(goal.color).opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            )
    }
}

/// The waking day as one bar: each goal's scheduled tasks and sessions in its colour, reserved time,
/// then what's free.
private struct DayBudgetView: View {
    let budget: DayBudget
    let goals: [CalendarGoal]
    let dayLabel: String
    let awake: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dayLabel).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                Text(awake).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
            }
            GeometryReader { geo in
                let parts = segments
                let total = max(1, parts.reduce(0) { $0 + $1.minutes })
                let gaps = CGFloat(max(0, parts.count - 1)) * 2
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { index in
                        Rectangle().fill(parts[index].color)
                            .frame(width: max(2, (geo.size.width - gaps) * CGFloat(parts[index].minutes) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            // On one line when it fits, else two.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { figures }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        figure(budget.sessionMinutes, "in sessions")
                        if budget.scheduledMinutes > 0 { figure(budget.scheduledMinutes, "scheduled") }
                    }
                    HStack(spacing: 14) {
                        figure(budget.reserved, "reserved")
                        figure(budget.free, "free")
                    }
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder private var figures: some View {
        figure(budget.sessionMinutes, "in sessions")
        if budget.scheduledMinutes > 0 { figure(budget.scheduledMinutes, "scheduled") }
        figure(budget.reserved, "reserved")
        figure(budget.free, "free")
    }

    private struct Part {
        let minutes: Int
        let color: Color
    }

    /// Each goal's time, scheduled first and solid, then its sessions lighter, as the timeline
    /// draws an intention fuller than a session; then reserved time, then what's free.
    private var segments: [Part] {
        var parts: [Part] = []
        for goal in goals {
            let color = GoalPalette.color(goal.color)
            if let scheduled = budget.scheduled.first(where: { $0.goalId == goal.id }) {
                parts.append(Part(minutes: scheduled.minutes, color: color))
            }
            if let session = budget.sessions.first(where: { $0.goalId == goal.id }) {
                parts.append(Part(minutes: session.minutes, color: color.opacity(0.45)))
            }
        }
        if budget.reserved > 0 { parts.append(Part(minutes: budget.reserved, color: Theme.foreground(0.22))) }
        if budget.free > 0 { parts.append(Part(minutes: budget.free, color: Theme.foreground(0.08))) }
        return parts
    }

    private func figure(_ minutes: Int, _ label: String) -> some View {
        Text("\(Text(BoardDuration.text(minutes)).foregroundStyle(Theme.foreground(0.85))) \(Text(label).foregroundStyle(Theme.muted))")
            .appText(.xs).monospacedDigit()
    }
}

// MARK: - Giving time

/// An open block's popover: what it is, Session or Reserved, how its goal's tasks sit in its time;
/// then the goals that could use its time to spare, each with how it stands. Hovering one previews
/// the trade on the lanes and timeline before it's made.
struct GivePanel: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    /// The block's goal's lane for the day.
    let lane: PlanLane?
    /// The other goals shown, as lanes.
    let others: [PlanLane]
    /// Every other goal, for giving the whole block.
    let goals: [CalendarGoal]
    /// What it has to spare, in minutes.
    let spare: Int
    /// "Fri, Nov 20 · 2:00 – 4:00 PM".
    let when: String
    let actions: PlanActions
    let setPreview: (GiveTime?) -> Void
    let dismiss: () -> Void

    @State private var reserved: Bool
    @State private var showsAll = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        block: CalendarBlock, goal: CalendarGoal?, lane: PlanLane?, others: [PlanLane], goals: [CalendarGoal], spare: Int,
        when: String, actions: PlanActions, setPreview: @escaping (GiveTime?) -> Void, dismiss: @escaping () -> Void
    ) {
        self.block = block
        self.goal = goal
        self.lane = lane
        self.others = others
        self.goals = goals
        self.spare = spare
        self.when = when
        self.actions = actions
        self.setPreview = setPreview
        self.dismiss = dismiss
        _reserved = State(initialValue: block.reserved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                if let goal { GoalBadge(icon: goal.icon, color: goal.color, size: .xs) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.title ?? goal?.title ?? "Protected time").appText(.sm, .medium).foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                    Text(when).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
                }
            }
            ToggleGroup(
                selection: Binding(get: { reserved }, set: { value in
                    reserved = value
                    actions.setReserved(block.id, value)
                }),
                options: [.init(value: false, label: "Session"), .init(value: true, label: "Reserved")]
            )
            .padding(.top, 12)
            .accessibilityLabel("Kind of time")

            if !reserved, let lane, let goal {
                divider
                HStack(spacing: 12) {
                    CapacityRing(planned: lane.open, protected: lane.room, color: goal.color, size: 36, stroke: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Text(BoardDuration.text(lane.open)).font(.app(14, .semibold)).foregroundStyle(lane.spare < 0 ? Theme.amber : Theme.foreground))\(Text(" / \(BoardDuration.text(lane.room))").font(.app(14)).foregroundStyle(Theme.muted))")
                        Text(standing(lane)).appText(.xs).foregroundStyle(lane.spare < 0 ? Theme.amber : Theme.muted)
                    }
                    .monospacedDigit()
                }
            }

            if !reserved, spare > 0, !others.isEmpty {
                divider
                Text("Give its \(BoardDuration.text(spare)) to spare to").appText(.xs, .medium).foregroundStyle(Theme.muted)
                    .padding(.bottom, 4)
                ForEach(others) { other in
                    GiveRow(goal: other.goal, status: short(other), isOver: other.spare < 0, ring: (other.open, other.room)) {
                        setPreview(nil)
                        dismiss()
                        actions.giveTime(block.id, spare, other.goal.id)
                    } onHover: { hovering in
                        setPreview(hovering ? GiveTime(blockId: block.id, goalId: other.goal.id, minutes: spare) : nil)
                    }
                }
                .padding(.horizontal, -6)
            }

            if !goals.isEmpty {
                divider
                if showsAll {
                    Text("Give all of it to").appText(.xs, .medium).foregroundStyle(Theme.muted).padding(.bottom, 4)
                    ForEach(goals) { other in
                        let lane = others.first { $0.id == other.id }
                        GiveRow(goal: other, status: lane.map(short) ?? "", isOver: (lane?.spare ?? 0) < 0, ring: lane.map { ($0.open, $0.room) }) {
                            setPreview(nil)
                            dismiss()
                            actions.giveBlock(block.id, other.id)
                        } onHover: { hovering in
                            setPreview(hovering ? GiveTime(blockId: block.id, goalId: other.id, minutes: 0, whole: true) : nil)
                        }
                    }
                    .padding(.horizontal, -6)
                } else {
                    Button { showsAll = true } label: {
                        HStack {
                            Text("Give all of it to another goal").font(.app(13)).foregroundStyle(Theme.foreground(0.85))
                            Spacer()
                            Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 316, alignment: .leading)
        .background {
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color(nsColor: .rgb(0x1c1e22)) : Theme.card)
                .shadow(color: .black.opacity(isDark ? 0 : 0.06), radius: 3, y: 2)
                .shadow(color: .black.opacity(isDark ? 0.7 : 0.18), radius: isDark ? 20 : 16, y: isDark ? 16 : 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colorScheme == .dark ? Theme.lineStrong : Theme.cardBorder))
        .onDisappear { setPreview(nil) }
    }

    private var divider: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 10)
    }

    /// "30 min to spare", "1 h 45 min over", "Just fits", "No session time": for a row.
    private func short(_ lane: PlanLane) -> String {
        if lane.room == 0 { return lane.open > 0 ? "No session time" : "Nothing planned" }
        if lane.spare < 0 { return "\(BoardDuration.text(-lane.spare)) over" }
        return lane.spare == 0 ? "Just fits" : "\(BoardDuration.text(lane.spare)) to spare"
    }

    /// "3 tasks · 30 min to spare", "1 h 45 min over", "No session time".
    private func standing(_ lane: PlanLane) -> String {
        if lane.room == 0 { return lane.open > 0 ? "No session time" : "Nothing planned" }
        if lane.spare < 0 { return "\(BoardDuration.text(-lane.spare)) over" }
        let tasks = lane.tasks.count == 1 ? "1 task" : "\(lane.tasks.count) tasks"
        return lane.spare == 0 ? "\(tasks) · Just fits" : "\(tasks) · \(BoardDuration.text(lane.spare)) to spare"
    }
}

/// A goal in the popover: its badge and title, then how it stands that day.
private struct GiveRow: View {
    let goal: CalendarGoal
    let status: String
    let isOver: Bool
    /// Open estimates against session time, for the ring; nil hides it.
    let ring: (Int, Int)?
    let action: () -> Void
    let onHover: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                Text(goal.title).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if let ring { CapacityRing(planned: ring.0, protected: ring.1, color: goal.color, size: 14) }
                    Text(status).appText(.xs).monospacedDigit()
                }
                .foregroundStyle(isOver ? Theme.amber : Theme.muted)
                .fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}
