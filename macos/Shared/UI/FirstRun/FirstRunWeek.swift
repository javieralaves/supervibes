import SwiftUI

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
    /// A project or practice dropped on a day (0 is Monday), at minutes from midnight.
    var drop: (String, Int, Int) -> Void = { _, _, _ in }
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
                PlateColumn(plan: plan)
                PlanGrid(plan: plan, selection: selection, practiceTip: practiceTip, actions: actions)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
    }
}

// MARK: - The plate

/// The plate beside the week: what to drag in, and the time each has so far: hours for a project, a count for a
/// practice. With a season, its quests come first, numbered, and each project or practice is marked with the quest
/// it moves; what waits for next season is left off, and counted at the end.
private struct PlateColumn: View {
    let plan: WeekPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !plan.quests.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your quests").font(.app(12, .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.bottom, 2)
                    ForEach(plan.quests) { quest in
                        QuestRow(quest: quest, meta: plan.meta(quest))
                    }
                }
            }
            section("Projects", plan.projects) { plan.meta($0) }
            section("Practices", plan.practices) { plan.meta($0) }
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
    }

    @ViewBuilder
    private func section(_ title: String, _ goals: [CalendarGoal], meta: @escaping (CalendarGoal) -> String) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(12, .semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.bottom, 2)
                ForEach(goals) { goal in
                    PlateRow(goal: goal, meta: meta(goal), quest: plan.quest(for: goal.id)?.number)
                }
            }
        }
    }
}

private struct PlateRow: View {
    let goal: CalendarGoal
    let meta: String
    /// The number of the quest it moves.
    var quest: Int?
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
        .draggable(goal.id) {
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
        .draggable(quest.goalIds.first ?? "") {
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

private struct PlanGrid: View {
    let plan: WeekPlan
    let selection: WeekSelection?
    let practiceTip: WeekSelection?
    let actions: WeekActions

    nonisolated static let fromHour = 8
    nonisolated static let toHour = 21
    nonisolated static let gutter: CGFloat = 44
    nonisolated static let header: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size)
            ZStack(alignment: .topLeading) {
                lines(layout)
                ForEach(0..<7, id: \.self) { day in
                    dayColumn(day, layout: layout)
                }
                overlays(layout)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    struct Layout {
        let size: CGSize
        var column: CGFloat { (size.width - PlanGrid.gutter) / 7 }
        var hour: CGFloat { max(28, (size.height - PlanGrid.header) / CGFloat(PlanGrid.toHour - PlanGrid.fromHour)) }

        func x(_ day: Int) -> CGFloat { PlanGrid.gutter + column * CGFloat(day) }
        func y(_ minutes: Int) -> CGFloat { PlanGrid.header + CGFloat(minutes - PlanGrid.fromHour * 60) / 60 * hour }

        /// Where something from `start` to `end` on a day sits, inset a little within its column.
        func frame(day: Int, start: Date, end: Date) -> CGRect {
            let from = max(CalendarDayMath.minutes(start), PlanGrid.fromHour * 60)
            let to = min(max(CalendarDayMath.minutes(end), from + 15), PlanGrid.toHour * 60)
            return CGRect(x: x(day) + 4, y: y(from) + 1.5, width: column - 8, height: max(18, y(to) - y(from) - 3))
        }

        /// Minutes from midnight at a point in a day's column, to the quarter hour.
        func minutes(at y: CGFloat) -> Int {
            let raw = Double(PlanGrid.fromHour * 60) + Double((y - PlanGrid.header) / hour) * 60
            return Int((raw / 15).rounded()) * 15
        }
    }

    // MARK: Lines and days

    private func lines(_ layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).locale(WeekPlan.locale)))
                        .foregroundStyle(Theme.muted)
                    Text(day.formatted(.dateTime.day().locale(WeekPlan.locale))).monospacedDigit()
                        .foregroundStyle(Theme.foreground)
                }
                .font(.app(12.5, .medium))
                .padding(.leading, 10)
                .frame(width: layout.column, height: Self.header, alignment: .leading)
                .offset(x: layout.x(index))
            }
            Rectangle().fill(Theme.cardBorder).frame(height: 1).offset(y: Self.header)
            ForEach(Self.fromHour + 1..<Self.toHour, id: \.self) { hour in
                Rectangle().fill(Theme.foreground(0.045)).frame(width: layout.size.width - Self.gutter, height: 1)
                    .offset(x: Self.gutter, y: layout.y(hour * 60))
                Text("\(hour):00").font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(width: Self.gutter - 8, alignment: .trailing)
                    .offset(y: layout.y(hour * 60) - 7)
            }
            ForEach(0..<7, id: \.self) { day in
                Rectangle().fill(Theme.cardBorder).frame(width: 1, height: layout.size.height).offset(x: layout.x(day))
            }
        }
    }

    private func dayColumn(_ day: Int, layout: Layout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(.rect)
            ForEach(plan.events.filter { plan.dayIndex($0.start) == day && !isAllDay($0) && !isFilled($0) }) { event in
                let frame = layout.frame(day: day, start: event.start, end: event.end)
                EventBlock(event: event, isOpen: plan.isOpen(event), isActive: selection == .event(event.key), height: frame.height)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX - layout.x(day), y: frame.minY)
                    .onTapGesture { actions.select(.event(event.key)) }
            }
            ForEach(plan.blocks.filter { plan.dayIndex($0.startsAt) == day }) { block in
                let frame = layout.frame(day: day, start: block.startsAt, end: block.endsAt)
                if let goal = plan.goal(block.goalId) {
                    GoalBlock(
                        block: block, goal: goal, count: goal.isPractice ? "\(plan.ordinal(of: block)) of \(goal.perWeek ?? 1) this week" : nil,
                        quest: plan.quest(for: goal.id)?.number, isActive: isSelected(block), height: frame.height
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX - layout.x(day), y: frame.minY)
                    .onTapGesture { actions.select(.block(block.id)) }
                }
            }
        }
        .frame(width: layout.column, height: layout.size.height)
        .offset(x: layout.x(day))
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first, plan.goal(id) != nil else { return false }
            actions.drop(id, day, min(max(layout.minutes(at: location.y), Self.fromHour * 60), (Self.toHour - 1) * 60))
            return true
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

    // MARK: Popovers and tips

    @ViewBuilder
    private func overlays(_ layout: Layout) -> some View {
        if let (frame, popover, height) = popover(layout) {
            let width: CGFloat = 284
            let right = frame.maxX + 10 + width < layout.size.width
            let x = right ? frame.maxX + 10 : frame.minX - 10 - width
            popover
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: x, y: max(Self.header + 8, min(frame.minY - 8, layout.size.height - height - 12)))
        }
        tip(layout)
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

    @ViewBuilder
    private func tip(_ layout: Layout) -> some View {
        if selection == nil {
            if let practiceTip, let block = plan.blocks.first(where: { matches($0, practiceTip) }),
               let day = plan.dayIndex(block.startsAt), let goal = plan.goal(block.goalId) {
                let frame = layout.frame(day: day, start: block.startsAt, end: block.endsAt)
                let right = frame.maxX + 240 < layout.size.width
                WeekTip(kicker: "Your practices", nib: right ? .left : .right, onNext: actions.next) {
                    Text("\(Text("That’s \(plan.ordinal(of: block)) of \(goal.perWeek ?? 1) \(goal.title) this week.").fontWeight(.semibold)) Every time you put a practice on your week counts toward it.")
                }
                .offset(x: right ? frame.maxX + 12 : frame.minX - 232, y: frame.minY - 4)
            } else {
                switch plan.stage {
                case .calendar:
                    if plan.calendar != .ready {
                        CalendarAccessCard(state: plan.calendar, onAllow: actions.allowCalendar, onSkip: actions.next)
                            .frame(width: 360)
                            .offset(x: (layout.size.width - 360) / 2 + Self.gutter / 2, y: layout.size.height / 2 - 110)
                    } else if let first = firstEvent, let day = plan.dayIndex(first.start) {
                        let frame = layout.frame(day: day, start: first.start, end: first.end)
                        let right = frame.maxX + 240 < layout.size.width
                        WeekTip(kicker: "Your calendar", nib: right ? .left : .right, onNext: actions.next) {
                            Text("These are from your Google Calendar. Click any of them to say if it’s time for one of your projects or practices.")
                        }
                        .offset(x: right ? frame.maxX + 12 : frame.minX - 232, y: frame.minY - 4)
                    }
                case .projects:
                    WeekTip(kicker: plan.quests.isEmpty ? "Your projects" : "Your quests", nib: .left, onNext: actions.next) {
                        Text("\(plan.quests.isEmpty ? "Drag a project onto your week to give it time." : "Start with your quests: drag one onto your week to give it time.")\(plan.open.isEmpty ? "" : " Time to fill is a good place to start.")")
                    }
                    .offset(x: 10, y: Self.header + 16)
                case .practices:
                    WeekTip(kicker: "Your practices", nib: .left, onNext: actions.next) {
                        Text("Drag a practice in too. Each time on your week counts toward how often you want it.")
                    }
                    .offset(x: 10, y: Self.header + 16)
                case .done:
                    EmptyView()
                }
            }
        }
    }

    private var firstEvent: ExternalEvent? {
        plan.events.filter { !isAllDay($0) && CalendarDayMath.minutes($0.end) > Self.fromHour * 60 }
            .min { ($0.start, $0.key) < ($1.start, $1.key) }
    }

    private func matches(_ block: CalendarBlock, _ selection: WeekSelection) -> Bool {
        switch selection {
        case .block(let id): id == block.id
        case .placed(let goalId, let startsAt): goalId == block.goalId && startsAt == block.startsAt
        case .event: false
        }
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
        if let count { return count }
        if block.source != nil { return block.reserved ? "\(goal.title) · Reserved" : goal.title }
        return block.reserved ? "Reserved" : "\(WeekPlan.clock(block.startsAt))–\(WeekPlan.clock(block.endsAt))"
    }
}
