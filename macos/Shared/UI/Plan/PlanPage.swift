import SwiftUI

/*
 * Planning a day across goals, from Plan on the rail: it opens on tomorrow. A lane for each goal
 * shown, with its tasks for the day in its order and a cut line where its session time runs out;
 * the day's timeline beside them, where time is given from one goal to another and reserved. What
 * doesn't fit moves to this week or next, each with how that week would stand.
 * Designed in supervibes-design ("Cross-goal planning", components/studio/frames/cross-goal-planning.tsx).
 */

/// What the Plan page can do.
struct PlanActions {
    /// The cards' own actions, as on the planning board.
    var tasks = TaskActions()
    /// Give `minutes` from the end of a session to another goal.
    var giveTime: (_ blockId: String, _ minutes: Int, _ goalId: String) -> Void = { _, _, _ in }
    /// Give a whole block to another goal.
    var giveBlock: (_ blockId: String, _ goalId: String) -> Void = { _, _ in }
    var setReserved: (_ blockId: String, _ reserved: Bool) -> Void = { _, _ in }
    var openGoal: (String) -> Void = { _ in }
    var openCalendar: () -> Void = {}
}

struct PlanPage: View {
    let data: CalendarData
    /// The day shown, in days from today.
    let offset: Int
    let now: Date
    var error: String?
    var actions = PlanActions()
    var onStep: (Int) -> Void = { _ in }
    var onToday: () -> Void = {}
    /// Opens previewing time being given, for previews and snapshot tests.
    var initialGive: GiveTime?
    /// Opens with this block's popover showing, for previews and snapshot tests.
    var initiallySelected: String?
    /// Opens with this goal's Move menu showing, for previews and snapshot tests.
    var initiallyMoving: String?
    /// How tall an hour is on the timeline, kept between visits; nil fits the waking day.
    var hour: Binding<CGFloat?>?
    /// False draws the timeline without scrolling, opened on waking, for snapshot tests.
    var scrollsTimeline = true

    /// Goals left out by hand, as their ids joined with commas.
    @AppStorage(PlanGoalsMenu.hiddenKey) private var hiddenGoals = ""
    /// Leave out goals with nothing that day.
    @AppStorage(PlanGoalsMenu.onlyActiveKey) private var onlyActive = true
    @State private var preview: GiveTime?
    @State private var goalsAnchor = CGRect.zero
    /// The page's frame in the overlay layer, to keep a block's popover inside it.
    @State private var pageFrame = CGRect.zero
    @Environment(\.overlays) private var overlays

    init(
        data: CalendarData, offset: Int, now: Date, error: String? = nil, actions: PlanActions = PlanActions(),
        onStep: @escaping (Int) -> Void = { _ in }, onToday: @escaping () -> Void = {},
        initialGive: GiveTime? = nil, initiallySelected: String? = nil, initiallyMoving: String? = nil,
        hour: Binding<CGFloat?>? = nil, scrollsTimeline: Bool = true
    ) {
        self.data = data
        self.offset = offset
        self.now = now
        self.error = error
        self.actions = actions
        self.onStep = onStep
        self.onToday = onToday
        self.initialGive = initialGive
        self.initiallySelected = initiallySelected
        self.initiallyMoving = initiallyMoving
        self.hour = hour
        self.scrollsTimeline = scrollsTimeline
        _preview = State(initialValue: initialGive)
    }

    private var today: String { CalendarDay.today(now) }
    private var day: String { CalendarDay.addDays(today, offset) }
    private var clock: Clock { data.clock ?? .device }
    private var hidden: Set<String> { Set(hiddenGoals.split(separator: ",").map(String.init)) }

    private static let previewId = "giving"

    var body: some View {
        // The lanes and timeline show a trade being considered as if it were made.
        let shown = preview.map { data.giving($0, newId: Self.previewId) } ?? data
        let lanes = shown.planLanes(day: day, now: now)
        let before = preview == nil ? nil : Dictionary(uniqueKeysWithValues: data.planLanes(day: day, now: now).map { ($0.id, $0) })
        let visible = lanes.filter { !hidden.contains($0.id) && (!onlyActive || $0.isActive) }

        VStack(alignment: .leading, spacing: 24) {
            header(total: data.goals.count, showing: visible.count)
                .padding(.horizontal, 24)
            HStack(alignment: .top, spacing: 10) {
                if visible.isEmpty {
                    PlanEmpty(day: PlanDay.title(offset: offset, day: day).lowercasedIfRelative, hasGoals: !data.goals.isEmpty)
                } else {
                    lanesRow(visible, before: before)
                }
                PlanTimeline(
                    data: shown,
                    offset: offset,
                    now: now,
                    clock: clock,
                    dayLabel: "\(PlanDay.weekday(day)), \(CalendarDay.format(day, today: today))",
                    ghostId: preview.map { $0.whole ? $0.blockId : Self.previewId },
                    ghostGoal: preview.flatMap { data.goal($0.goalId) },
                    initiallySelected: initiallySelected,
                    storedHour: hour,
                    scrolls: scrollsTimeline
                ) { block, anchor in
                    showGive(block, anchor: anchor)
                }
                .frame(width: 392)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(AnchorReader(frame: $pageFrame))
        .background(Backdrop())
        .environment(\.shortHours, true)
        .overlay(alignment: .bottom) {
            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: Header

    private func header(total: Int, showing: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanDay.title(offset: offset, day: day))
                    .font(.app(20, .semibold)).tracking(-0.4).foregroundStyle(Theme.foreground)
                    .frame(minHeight: 24)
                Text(PlanDay.subtitle(day)).appText(.sm).foregroundStyle(Theme.muted).frame(minHeight: 20)
            }
            Spacer(minLength: 24)
            PlanBarButton(action: { onStep(-1) }) { Icon.arrowLeft.image(size: 16).frame(width: 32) }
                .help("Previous day").accessibilityLabel("Previous day")
            PlanBarButton(action: onToday) { Text("Today").appText(.sm, .medium).padding(.horizontal, 12) }
            PlanBarButton(action: { onStep(1) }) { Icon.arrowRight.image(size: 16).frame(width: 32) }
                .help("Next day").accessibilityLabel("Next day")
            PlanBarButton(isOn: overlays?.presented?.owner == PlanGoalsMenu.owner, action: showGoals) {
                HStack(spacing: 6) {
                    Icon.preferences.image(size: 16)
                    Text("\(showing) of \(total) goals").appText(.sm, .medium).monospacedDigit()
                }
                .padding(.horizontal, 10)
            }
            .modifier(AnchorReader(frame: $goalsAnchor))
            .padding(.leading, 4)
            PlanBarButton(action: actions.openCalendar) {
                HStack(spacing: 6) {
                    Icon.calendarSmall.image(size: 16)
                    Text("Open in Calendar").appText(.sm, .medium)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    private func showGoals() {
        guard let overlays else { return }
        let lanes = data.planLanes(day: day, now: now)
        let reserved = Set(data.blocks.filter { block in
            block.reserved && DaySegment.of(block, today: now).contains { $0.day == offset }
        }.map(\.goalId))
        overlays.showMenu(anchor: goalsAnchor, owner: PlanGoalsMenu.owner) {
            PlanGoalsMenu(lanes: lanes, reservedGoals: reserved, dayName: PlanDay.title(offset: offset, day: day).lowercasedIfRelative)
        }
    }

    // MARK: Lanes

    private func lanesRow(_ lanes: [PlanLane], before: [String: PlanLane]?) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 10
            let width = max(300, (geo.size.width - gap * CGFloat(lanes.count - 1)) / CGFloat(lanes.count))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: gap) {
                    ForEach(lanes) { lane in
                        PlanLaneView(
                            lane: lane,
                            day: day,
                            fitBefore: before?[lane.id]?.fitting,
                            change: change(for: lane, before: before?[lane.id]),
                            today: today,
                            now: now,
                            clock: clock,
                            actions: actions,
                            initiallyMoving: initiallyMoving == lane.id
                        )
                        .frame(width: width, height: geo.size.height)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(width * CGFloat(lanes.count) + gap * CGFloat(lanes.count - 1) <= geo.size.width + 1)
        }
    }

    /// "+30 min from Lead design…" or "30 min given to Build Supervibes", while a trade is previewed.
    private func change(for lane: PlanLane, before: PlanLane?) -> String? {
        guard let preview, let before else { return nil }
        let delta = lane.day.protected - before.day.protected
        guard delta != 0 else { return nil }
        let from = data.blocks.first { $0.id == preview.blockId }.flatMap { data.goal($0.goalId) }
        if delta > 0 { return "+\(BoardDuration.text(delta)) from \(from?.title ?? "another goal")" }
        return "\(BoardDuration.text(-delta)) given to \(data.goal(preview.goalId)?.title ?? "another goal")"
    }

    // MARK: Giving time

    private func showGive(_ shown: CalendarBlock, anchor: CGRect) {
        // As it is, not as a previewed trade has it.
        guard let overlays, let block = data.blocks.first(where: { $0.id == shown.id }), !block.isIntention else { return }
        let lanes = data.planLanes(day: day, now: now)
        let lane = lanes.first { $0.id == block.goalId }
        let others = lanes.filter { $0.id != block.goalId && !hidden.contains($0.id) && (!onlyActive || $0.isActive) }
        let spare = data.spare(in: block, lane: lane, now: now)
        let setPreview: (GiveTime?) -> Void = { preview = $0 }
        // Beside the block, to its left, so the timeline stays in view while a trade is previewed.
        // About as tall as the popover gets, so one for a block late in the day still fits.
        let top = pageFrame == .zero ? anchor.minY : min(anchor.minY, pageFrame.maxY - 460)
        let beside = CGRect(x: anchor.minX - 10, y: top - 6, width: 0, height: 0)
        overlays.showMenu(anchor: beside, owner: "plan-block#\(block.id)") {
            GivePanel(
                block: block,
                goal: data.goal(block.goalId),
                lane: lane,
                others: others,
                goals: data.goals.filter { $0.id != block.goalId },
                spare: spare,
                when: "\(PlanDay.weekday(day)), \(CalendarDay.format(day, today: today)) · \(clock.range(block.startsAt, block.endsAt))",
                actions: actions,
                setPreview: setPreview,
                dismiss: { overlays.dismiss() }
            )
        }
    }
}

private extension String {
    /// "Today" → "today", "Tomorrow" → "tomorrow"; weekdays keep their capital.
    var lowercasedIfRelative: String { ["Today", "Tomorrow", "Yesterday"].contains(self) ? lowercased() : self }
}

// MARK: - A goal's lane

/// One goal's tasks for the day, in its order, with the cut line where its session time runs out,
/// and how its weeks stand at the bottom.
private struct PlanLaneView: View {
    let lane: PlanLane
    /// The day shown, "YYYY-MM-DD".
    let day: String
    /// While a trade is previewed: how many fitted before it, so those that fit now stand out.
    let fitBefore: Int?
    /// While a trade is previewed: what it does to this goal's time.
    let change: String?
    let today: String
    let now: Date
    let clock: Clock
    let actions: PlanActions
    var initiallyMoving = false

    @State private var isTargeted = false

    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
                .padding(.horizontal, 6)
                .padding(.top, 4)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    // On the calendar: they fit, on their own time, ahead of the rest.
                    ForEach(lane.scheduled) { task in
                        row(task)
                    }
                    ForEach(Array(lane.tasks.enumerated()), id: \.element.id) { index, task in
                        if index == lane.fitting { cutLine }
                        card(task, fits: index < lane.fitting, gained: fitBefore.map { index >= $0 && index < lane.fitting } ?? false)
                    }
                    if lane.tasks.isEmpty && lane.scheduled.isEmpty {
                        PlanNote(text: lane.day.protected > 0
                            ? "Nothing planned · \(BoardDuration.text(lane.room)) protected"
                            : "Nothing planned")
                    } else if lane.overflow.isEmpty, lane.spare > 0 {
                        PlanNote(text: "\(BoardDuration.text(lane.spare)) to spare")
                    }
                }
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            weeks
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isTargeted ? Theme.foreground(0.07) : laneFill, in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let task = lane.tasks.first(where: { $0.id == id }) else { return false }
            actions.tasks.place(task, TaskPatch(), nil)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    /// The goal, this week's objective, and its ring for the day.
    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            GoalBadge(icon: lane.goal.icon, color: lane.goal.color, size: .xs)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Button { actions.openGoal(lane.goal.id) } label: {
                    Text(lane.goal.title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open \(lane.goal.title)")
                HStack(spacing: 8) {
                    Text(lane.objective ?? "No objective this week")
                        .appText(.xs).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ring
                }
                if let change {
                    HStack(spacing: 6) {
                        Circle().fill(GoalPalette.color(lane.goal.color)).frame(width: 6, height: 6)
                        Text(change).appText(.xs, .medium).lineLimit(1)
                    }
                    .foregroundStyle(Theme.foreground(0.8))
                    .padding(.top, 4)
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Tasks against what's left of the session time: "3 h 45 min / 2 h", amber when over. With
    /// only scheduled tasks and no sessions, how much is scheduled.
    @ViewBuilder private var ring: some View {
        if lane.room == 0, lane.open == 0, !lane.scheduled.isEmpty {
            Text("\(BoardDuration.text(lane.scheduled.reduce(0) { $0 + $1.minutes })) scheduled")
                .appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
        } else {
            capacity
        }
    }

    private var capacity: some View {
        HStack(spacing: 6) {
            CapacityRing(planned: lane.open, protected: lane.room, color: lane.goal.color)
            Group {
                Text("\(BoardDuration.text(lane.open))\(Text(lane.room > 0 ? " / \(BoardDuration.text(lane.room))" : "").foregroundStyle(Theme.muted))")
            }
            .appText(.xs).monospacedDigit()
        }
        .foregroundStyle(lane.spare < 0 ? Theme.amber : Theme.muted)
        .fixedSize()
        .help(lane.room == 0 ? "No session time" : lane.spare < 0 ? "\(BoardDuration.text(-lane.spare)) over" : "\(BoardDuration.text(lane.spare)) to spare")
    }

    /// A card, as on the planning board.
    private func row(_ task: TaskItem) -> some View {
        GoalTaskRow(
            task: task,
            horizon: task.horizon(today: today),
            clock: clock,
            today: today,
            thisWeek: thisWeek,
            nextWeek: nextWeek,
            now: now,
            isDragging: false,
            isReorderable: false,
            actions: actions.tasks,
            showsNotes: false,
            showsPlan: false,
            onOpen: {}
        )
        .modifier(CardStyle(isOpen: false))
    }

    /// A task that needs room in the sessions: ranked by dragging, faded under the cut line.
    private func card(_ task: TaskItem, fits: Bool, gained: Bool) -> some View {
        row(task)
        .overlay {
            // Fits now, thanks to the time being given.
            if gained {
                RoundedRectangle(cornerRadius: 12).strokeBorder(GoalPalette.color(lane.goal.color).opacity(0.55), lineWidth: 2)
            }
        }
        .opacity(fits ? 1 : 0.55)
        .draggable(task.id) {
            Text(task.title).appText(.sm).foregroundStyle(Theme.foreground)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(width: 220, alignment: .leading)
                .background(Theme.card, in: .rect(cornerRadius: 12))
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, id != task.id, let moved = lane.tasks.first(where: { $0.id == id }) else { return false }
            actions.tasks.place(moved, TaskPatch(), task.id)
            return true
        }
        .contextMenu {
            Button("Move to this week") { actions.tasks.place(task, TaskPatch(plannedFor: "", plannedWeek: thisWeek), nil) }
            Button("Move to next week") { actions.tasks.place(task, TaskPatch(plannedFor: "", plannedWeek: nextWeek), nil) }
            Button("Move to Unplanned") { actions.tasks.place(task, TaskPatch(plannedFor: "", plannedWeek: ""), nil) }
        }
    }

    /// Where the session time runs out: "Doesn't fit · 1 h 45 min", a dashed rule, and Move.
    private var cutLine: some View {
        HStack(spacing: 8) {
            Text("Doesn’t fit · \(BoardDuration.text(lane.overflowMinutes))")
                .appText(.xs, .medium).foregroundStyle(Theme.amber).monospacedDigit()
                .fixedSize()
            Line()
                .stroke(Theme.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 1.5)
            MoveButton(lane: lane, day: day, today: today, actions: actions, showsInitially: initiallyMoving)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    /// How the goal's weeks stand, for deciding where what doesn't fit goes.
    private var weeks: some View {
        VStack(spacing: 6) {
            WeekLine(label: "This week", capacity: lane.thisWeek, color: lane.goal.color)
            WeekLine(label: "Next week", capacity: lane.nextWeek, color: lane.goal.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.card.opacity(0.55), in: .rect(cornerRadius: 12))
    }
}

/// A horizontal line, for dashing.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/// A quiet dashed note at the end of a lane: time to spare, or nothing planned.
private struct PlanNote: View {
    let text: String

    var body: some View {
        Text(text).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
}

/// "○ This week · 45 min to spare".
private struct WeekLine: View {
    let label: String
    let capacity: Capacity
    let color: String

    var body: some View {
        HStack(spacing: 8) {
            CapacityRing(planned: capacity.planned, protected: capacity.protected, color: color, size: 14)
            Text(label).appText(.xs).foregroundStyle(Theme.foreground(0.8))
            Spacer(minLength: 8)
            Text(Self.status(capacity)).appText(.xs).monospacedDigit()
                .foregroundStyle(capacity.isOver ? Theme.amber : Theme.muted)
        }
    }

    /// "45 min to spare", "1 h over", "Just fits", "No time protected".
    static func status(_ capacity: Capacity) -> String {
        if capacity.protected == 0 { return "No time protected" }
        if capacity.remaining < 0 { return "\(BoardDuration.text(-capacity.remaining)) over" }
        return capacity.remaining == 0 ? "Just fits" : "\(BoardDuration.text(capacity.remaining)) to spare"
    }
}

/// "Move 3 ⌄" on the cut line: where what doesn't fit can go, each with how that week would stand.
private struct MoveButton: View {
    let lane: PlanLane
    /// The day they're planned for now: its week already counts them.
    let day: String
    let today: String
    let actions: PlanActions
    var showsInitially = false

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero
    @State private var isHovered = false
    @State private var didShowInitially = false

    private var owner: String { "plan-move#\(lane.id)" }
    private var isOpen: Bool { overlays?.presented?.owner == owner }

    var body: some View {
        Button(action: show) {
            HStack(spacing: 4) {
                Text("Move \(lane.overflow.count)").appText(.xs, .medium)
                Icon.chevronDown.image(size: 12)
            }
            .foregroundStyle(isOpen || isHovered ? Theme.foreground : Theme.foreground(0.8))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isOpen ? Theme.foreground(0.08) : Theme.card, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isOpen ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .modifier(AnchorReader(frame: $anchor))
        .fixedSize()
        .onChange(of: anchor) {
            guard showsInitially, !didShowInitially, anchor != .zero else { return }
            didShowInitially = true
            show()
        }
        .accessibilityLabel("Move the \(lane.overflow.count) that don’t fit")
    }

    private func show() {
        guard let overlays else { return }
        let thisWeek = CalendarDay.weekStart(today)
        let nextWeek = CalendarDay.addDays(thisWeek, 7)
        let tasks = lane.overflow
        let minutes = lane.overflowMinutes
        let move = actions.tasks.place
        let dayWeek = CalendarDay.weekStart(day)
        /// A week with them in it; the day's own week has them already.
        func with(_ week: Capacity, _ start: String) -> Capacity {
            Capacity(planned: week.planned + (start == dayWeek ? 0 : minutes), protected: week.protected)
        }
        overlays.showMenu(anchor: anchor, owner: owner) {
            MenuPanel(width: 320) {
                Text("Move the \(tasks.count) that don’t fit · \(BoardDuration.text(minutes))")
                    .appText(.xs).foregroundStyle(Theme.muted).monospacedDigit()
                    .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
                MoveOption(
                    title: "This week", detail: CalendarDay.formatWeek(thisWeek),
                    capacity: with(lane.thisWeek, thisWeek), color: lane.goal.color
                ) {
                    overlays.dismiss()
                    for task in tasks { move(task, TaskPatch(plannedFor: "", plannedWeek: thisWeek), nil) }
                }
                MoveOption(
                    title: "Next week", detail: CalendarDay.formatWeek(nextWeek),
                    capacity: with(lane.nextWeek, nextWeek), color: lane.goal.color
                ) {
                    overlays.dismiss()
                    for task in tasks { move(task, TaskPatch(plannedFor: "", plannedWeek: nextWeek), nil) }
                }
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
                MoveOption(title: "Unplanned", detail: nil, capacity: nil, color: lane.goal.color) {
                    overlays.dismiss()
                    for task in tasks { move(task, TaskPatch(plannedFor: "", plannedWeek: ""), nil) }
                }
            }
        }
    }
}

/// A place in the Move menu, with its ring and how the week would stand once they're there.
private struct MoveOption: View {
    let title: String
    let detail: String?
    /// The week with them in it; nil for Unplanned.
    let capacity: Capacity?
    let color: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CapacityRing(planned: capacity?.planned ?? 0, protected: capacity?.protected ?? 0, color: color, size: 28, stroke: 5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title).font(.app(13, .medium)).foregroundStyle(Theme.foreground)
                        if let detail { Text(detail).font(.app(13)).foregroundStyle(Theme.muted) }
                    }
                    Text(status).appText(.xs).monospacedDigit().lineLimit(1)
                        .foregroundStyle(capacity?.isOver == true ? Theme.amber : Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var status: String {
        guard let capacity else { return "Off the plan until you pick them up" }
        if capacity.protected == 0 { return "No time protected" }
        let totals = "\(BoardDuration.text(capacity.planned)) / \(BoardDuration.text(capacity.protected))"
        return capacity.isOver
            ? "\(totals) · \(BoardDuration.text(-capacity.remaining)) over"
            : "\(totals) · \(BoardDuration.text(capacity.remaining)) left"
    }
}

/// No lanes to show: nothing planned and no sessions, or every goal left out.
private struct PlanEmpty: View {
    let day: String
    let hasGoals: Bool

    var body: some View {
        VStack(spacing: 4) {
            Icon.plan.image(size: 18)
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: .circle)
                .overlay(Circle().strokeBorder(Theme.cardBorder))
                .padding(.bottom, 6)
            Text(hasGoals ? "Nothing to plan for \(day)" : "No goals yet").font(.app(14, .medium)).foregroundStyle(Theme.foreground(0.85))
            Text(hasGoals
                ? "Plan tasks for \(day) from a goal’s board, or protect time for one on the calendar."
                : "Add a goal to plan its tasks here.")
                .appText(.sm).foregroundStyle(Theme.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(laneFill, in: .rect(cornerRadius: 14))
    }
}

/// A bordered button on the card colour, as the calendar's top bar draws them; pressed while its
/// menu is open.
struct PlanBarButton<Label: View>: View {
    var isOn = false
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(isOn || isHovered ? Theme.foreground : Theme.muted)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(isOn ? Theme.foreground(0.06) : Theme.card)
                        .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn || isHovered ? Theme.lineStrong : Theme.cardBorder))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Choosing goals

/// Which goals get a lane: each by hand, and whether goals with nothing that day are left out.
struct PlanGoalsMenu: View {
    static let owner = "plan-goals"
    static let hiddenKey = "sv-plan-hidden-goals"
    static let onlyActiveKey = "sv-plan-only-active"

    let lanes: [PlanLane]
    /// Goals with reserved time that day.
    let reservedGoals: Set<String>
    let dayName: String

    @AppStorage(hiddenKey) private var hiddenGoals = ""
    @AppStorage(onlyActiveKey) private var onlyActive = true

    private var hidden: Set<String> { Set(hiddenGoals.split(separator: ",").map(String.init)) }

    var body: some View {
        MenuPanel(width: 340) {
            Text("Lanes").appText(.xs, .medium).foregroundStyle(Theme.muted)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
            ForEach(lanes) { lane in
                GoalRow(lane: lane, isShown: !hidden.contains(lane.id), detail: detail(lane)) { toggle(lane.id) }
            }
            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 6)
            Toggle(isOn: $onlyActive) {
                Text("Only goals with time or tasks that day").font(.app(13)).foregroundStyle(Theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    /// How the goal stands that day.
    private func detail(_ lane: PlanLane) -> String {
        if lane.isActive { return "\(BoardDuration.text(lane.open)) / \(BoardDuration.text(lane.room))" }
        return reservedGoals.contains(lane.id) ? "Reserved time only" : "Nothing \(dayName)"
    }

    private func toggle(_ id: String) {
        var next = hidden
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        hiddenGoals = next.sorted().joined(separator: ",")
    }

    private struct GoalRow: View {
        let lane: PlanLane
        let isShown: Bool
        let detail: String
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Icon.tickBold.image(size: 11)
                        .foregroundStyle(isShown ? Theme.background : .clear)
                        .frame(width: 16, height: 16)
                        .background(isShown ? Theme.foreground : .clear, in: .rect(cornerRadius: 5))
                        .overlay {
                            if !isShown { RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.lineStrong, lineWidth: 1.5) }
                        }
                    GoalBadge(icon: lane.goal.icon, color: lane.goal.color, size: .xs)
                    Text(lane.goal.title).font(.app(13)).foregroundStyle(Theme.foreground(isShown ? 1 : 0.7))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(detail).appText(.xs).foregroundStyle(Theme.muted).monospacedDigit().fixedSize()
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("\(isShown ? "Hide" : "Show") \(lane.goal.title)")
        }
    }
}

// MARK: - Previews

#Preview("Plan tomorrow") {
    PlanPage(data: Fixtures.plan, offset: 1, now: Fixtures.referenceNow)
        .frame(width: 1540, height: 1000)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
}

#Preview("Giving time") {
    PlanPage(
        data: Fixtures.plan, offset: 1, now: Fixtures.referenceNow,
        initialGive: GiveTime(blockId: "p4", goalId: "pg1", minutes: 30), initiallySelected: "p4"
    )
    .frame(width: 1540, height: 1000)
    .background(Theme.background)
    .overlayHost(OverlayCenter())
}

#Preview("Moving what doesn't fit") {
    PlanPage(data: Fixtures.plan, offset: 1, now: Fixtures.referenceNow, initiallyMoving: "pg1")
        .frame(width: 1540, height: 1000)
        .background(Theme.background)
        .overlayHost(OverlayCenter())
}
