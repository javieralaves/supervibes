import SwiftUI

/*
 * The Plan page's day, beside the lanes: the waking day split into sessions, reserved time and
 * what's free, then the day hour by hour with its blocks drawn as the day view draws them (sessions
 * hatched, reserved time plain), opening on the waking hours, with the now line on today. Pinch to make the hours taller or
 * shorter, as on the day view. Click protected time to give some or all of it to another goal, or
 * to switch it between a session and reserved.
 */

struct PlanTimeline: View {
    let data: CalendarData
    /// Days from today.
    let offset: Int
    let now: Date
    let clock: Clock
    /// "Fri, Nov 20".
    let dayLabel: String
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
    /// A protected block was clicked, with its frame in the overlay layer.
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

    private static let pad: CGFloat = 10
    /// The day view's, so the now line's time fits.
    private static let gutter: CGFloat = DayGrid.gutter

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

    var body: some View {
        VStack(spacing: 0) {
            DayBudgetView(budget: data.budget(day: offset, now: now), goals: data.goals, dayLabel: dayLabel, awake: awakeLabel)
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            if scrolls {
                ScrollView(.vertical) {
                    content(grid)
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
                .onChange(of: offset) { scrollToFocus() }
            } else {
                // Over a frame that takes only the room it's given, so the whole day doesn't size the page.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
                    .overlay(alignment: .top) {
                        content(grid)
                            .offset(y: -grid.scrollY(keeping: CGFloat(focus / 60 * 60), at: Self.pad, viewport: viewport))
                    }
                    .clipped()
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    /// The day's hours, its blocks, and pinching.
    private func content(_ grid: HourGrid) -> some View {
        ZStack(alignment: .topLeading) {
            sleep(grid)
            hourLines(grid)
            ForEach(segments, id: \.segment.id) { item in
                block(item.block, item.segment, grid: grid)
            }
            if offset == 0 {
                NowLine(label: clock.format(minutes: nowMinutes), gutter: Self.gutter)
                    .offset(y: grid.y(nowMinutes))
            }
        }
        .frame(height: grid.height, alignment: .top)
        .frame(maxWidth: .infinity)
        .environment(\.dayGrid, grid)
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

    /// The day's blocks, or their parts on this day, earliest first.
    private var segments: [(block: CalendarBlock, segment: DaySegment)] {
        data.blocks.flatMap { block in
            DaySegment.of(block, today: now).filter { $0.day == offset }.map { (block, $0) }
        }
        .sorted { $0.segment.start < $1.segment.start }
    }

    /// Sleep, finely hatched, as on the day view.
    private func sleep(_ grid: HourGrid) -> some View {
        ForEach(CalendarDayMath.sleepSpans(sleepStart: data.sleepStart, wakeTime: data.wakeTime), id: \.lowerBound) { span in
            Hatch(color: Theme.foreground(0.06), spacing: 7)
                .frame(height: grid.height(span.upperBound - span.lowerBound))
                .padding(.leading, Self.gutter)
                .offset(y: grid.y(span.lowerBound))
                .allowsHitTesting(false)
        }
    }

    private var nowMinutes: Int { CalendarDayMath.minutes(now) }

    /// How close (in points) an hour's label can come to the now line's before it hides, as on the day view.
    private static let nowClearance: CGFloat = 40

    private func hourLines(_ grid: HourGrid) -> some View {
        ForEach(0...24, id: \.self) { hour in
            let nearNow = offset == 0 && abs(grid.y(hour * 60) - grid.y(nowMinutes)) < Self.nowClearance
            HStack(spacing: 8) {
                Text(hour < 24 ? clock.formatHour(hour) : "")
                    .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(width: Self.gutter - 8, height: 14, alignment: .trailing)
                    .opacity(nearNow ? 0 : 1)
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
            }
            .offset(y: grid.y(hour * 60) - 7)
        }
    }

    @ViewBuilder private func block(_ block: CalendarBlock, _ segment: DaySegment, grid: HourGrid) -> some View {
        let top = grid.y(segment.start)
        let height = max(grid.height(segment.end - segment.start), 16)
        Group {
            if block.id == ghostId, let ghostGoal {
                GhostBlock(minutes: segment.end - segment.start, goal: ghostGoal)
            } else {
                PlanBlock(
                    block: block,
                    goal: data.goal(block.goalId),
                    segment: segment,
                    clock: clock,
                    elapsed: elapsed(segment),
                    isSelected: overlays?.presented?.owner == "plan-block#\(block.id)",
                    showsInitially: initiallySelected == block.id,
                    onSelect: onSelect
                )
            }
        }
        .frame(height: height - 2)
        .padding(.leading, Self.gutter + 4)
        .padding(.trailing, 10)
        .offset(y: top + 1)
    }

    /// How much of it has happened, 0 to 1.
    private func elapsed(_ segment: DaySegment) -> Double {
        let midnight = CalendarDayMath.midnight(segment.day, from: now)
        let from = midnight.addingTimeInterval(Double(segment.start) * 60)
        let to = midnight.addingTimeInterval(Double(segment.end) * 60)
        guard to > from else { return 0 }
        return min(max(now.timeIntervalSince(from) / to.timeIntervalSince(from), 0), 1)
    }
}

/// A block on the Plan page's timeline, as the day view draws it. Protected time opens its popover.
private struct PlanBlock: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let segment: DaySegment
    let clock: Clock
    let elapsed: Double
    let isSelected: Bool
    var showsInitially = false
    let onSelect: (CalendarBlock, CGRect) -> Void

    @State private var anchor = CGRect.zero
    @State private var isHovered = false
    @State private var didShowInitially = false

    var body: some View {
        BlockCardView(
            block: block, goal: goal, start: segment.start, end: segment.end, clock: clock,
            elapsed: elapsed, isHovered: isHovered
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(GoalPalette.color(goal?.color ?? "slate").opacity(0.6), lineWidth: 2)
                    .padding(-2)
            }
        }
        .contentShape(.rect(cornerRadius: 8))
        .modifier(AnchorReader(frame: $anchor))
        .onHover { isHovered = $0 && !block.isIntention }
        .onTapGesture {
            guard !block.isIntention, !block.isPending else { return }
            onSelect(block, anchor)
        }
        .onChange(of: anchor) {
            guard showsInitially, !didShowInitially, anchor != .zero else { return }
            didShowInitially = true
            onSelect(block, anchor)
        }
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

/// The waking day as one bar: each goal's sessions in its colour, reserved time, then what's free.
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
            HStack(spacing: 14) {
                figure(budget.sessionMinutes, "in sessions")
                figure(budget.reserved, "reserved")
                figure(budget.free, "free")
            }
        }
        .padding(14)
    }

    private struct Part {
        let minutes: Int
        let color: Color
    }

    private var segments: [Part] {
        var parts = budget.sessions.map { share in
            Part(minutes: share.minutes, color: GoalPalette.color(goals.first { $0.id == share.goalId }?.color ?? "slate"))
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
