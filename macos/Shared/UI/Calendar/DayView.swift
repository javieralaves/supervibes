import SwiftUI

/*
 * One day, hour by hour, matching src/app/(app)/calendar/day-calendar.tsx: the top bar, the
 * "Anytime" strip of tasks planned or due without a time, a row per goal (GoalStrip), then the
 * timeline with sleep shaded, past time washed, blocks filling in as their time passes, and the now
 * line. A goal open on the strip rings its sessions on the timeline.
 */

/// The timeline's geometry (geometry.ts). Pinching changes how tall an hour is (`HourGrid`).
enum DayGrid {
    /// Height of one hour, before any pinching.
    static let hour: CGFloat = 176
    /// Pinching in stops at twice that.
    static let maxHour = hour * 2
    /// Room above midnight and below the last hour so their labels aren't clipped.
    static let pad: CGFloat = 12
    /// Width of the hour-label column.
    static let gutter: CGFloat = 64
    static let standard = HourGrid(hour: hour, pad: pad)
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
    /// The multi-day view's first day, in days from today; without it, where the view starts that
    /// holds `offset`: its Monday in Week, or `offset` itself.
    var first: Int?
    /// Where the first day can go (what's loaded).
    var firstRange: ClosedRange<Int>?
    /// Moves the first day by that many days (the arrows, and scrolling sideways); without it the
    /// arrows step `offset` a page and the days don't scroll.
    var onScroll: ((Int) -> Void)?
    /// Changing blocks; without it the day is read-only.
    var actions: CalendarActions?
    /// The block whose panel is open on the right.
    var selectedId: Binding<String?> = .constant(nil)
    /// What the block panel can do; without it, clicking a block edits it in place.
    var panel: BlockPanelActions?
    /// Day, Next N days or Week (the screen decides, since the multi-day views need a wide window).
    var span = CalendarSpan.day
    /// The count Next N days last showed, for the switch's button.
    var dayCount = 3
    /// Changes the view; without it there's no switch.
    var onSetSpan: ((CalendarSpan) -> Void)?
    /// How tall an hour is in the day and in the week, as last pinched; without them each keeps its own.
    var dayHour: Binding<CGFloat>?
    var weekHour: Binding<CGFloat>?
    /// Calendar import's events panel, beside the days where a block's panel opens; a block's panel
    /// takes its place while one is open.
    var eventsPanel: AnyView?
    var showsEvents = false
    /// Opens or closes it; without it there's no events button.
    var onToggleEvents: (() -> Void)?
    /// Imported events that changed since, as a count on the button.
    var eventChanges = 0
    /// The button's tooltip: where events come from and when they were last read.
    var eventsHelp = "Events from Google"
    /// A hovered event, previewed on the grid.
    var eventPreview: EventPreview?
    /// Imported blocks whose events changed since, by block: marked on the grid, offered in their panel.
    var importChanges: [String: ImportChange] = [:]

    @State private var drag = TaskDragState()
    /// Time drawn on the week and waiting to be named.
    @State private var weekCreating: BlockEditing?
    /// The block being named or given a goal in the popover.
    @State private var editing: BlockEditing?
    @State private var width: CGFloat = 0
    /// The goals open on the strip, by day ("YYYY-MM-DD"): their tasks showing and their sessions ringed.
    @State private var openGoals: [String: Set<String>]

    init(data: CalendarData, offset: Int, now: Date, error: String? = nil, onStep: @escaping (Int) -> Void = { _ in },
         onToday: @escaping () -> Void = {}, first: Int? = nil, firstRange: ClosedRange<Int>? = nil,
         onScroll: ((Int) -> Void)? = nil, actions: CalendarActions? = nil, editing: BlockEditing? = nil,
         selectedId: Binding<String?> = .constant(nil),
         panel: BlockPanelActions? = nil, span: CalendarSpan = .day, dayCount: Int = 3, onSetSpan: ((CalendarSpan) -> Void)? = nil,
         dayHour: Binding<CGFloat>? = nil, weekHour: Binding<CGFloat>? = nil,
         eventsPanel: AnyView? = nil, showsEvents: Bool = false, onToggleEvents: (() -> Void)? = nil, eventChanges: Int = 0,
         eventsHelp: String = "Events from Google", eventPreview: EventPreview? = nil, importChanges: [String: ImportChange] = [:],
         openGoals: Set<String> = []) {
        self.data = data
        self.offset = offset
        self.now = now
        self.error = error
        self.onStep = onStep
        self.onToday = onToday
        self.first = first
        self.firstRange = firstRange
        self.onScroll = onScroll
        self.actions = actions
        self.selectedId = selectedId
        self.panel = panel
        self.span = span
        self.dayCount = dayCount
        self.onSetSpan = onSetSpan
        self.dayHour = dayHour
        self.weekHour = weekHour
        self.eventsPanel = eventsPanel
        self.showsEvents = showsEvents
        self.onToggleEvents = onToggleEvents
        self.eventChanges = eventChanges
        self.eventsHelp = eventsHelp
        self.eventPreview = eventPreview
        self.importChanges = importChanges
        _editing = State(initialValue: editing)
        _openGoals = State(initialValue: [CalendarDay.today(CalendarDayMath.midnight(offset, from: now)): openGoals])
    }

    private var isMultiDay: Bool { span.isMultiDay }

    /// The goals open on the shown day's strip.
    private var openOnShownDay: Binding<Set<String>> {
        let day = CalendarDay.today(CalendarDayMath.midnight(offset, from: now))
        return Binding(get: { openGoals[day] ?? [] }, set: { openGoals[day] = $0 })
    }
    /// The first of the days shown, in days from today: any day, once they've been scrolled.
    private var shownFirst: Int { first ?? (span == .week ? CalendarDayMath.monday(of: offset, from: now) : offset) }
    /// The Monday-to-Sunday week the "This week" label goes by: the one holding the middle day shown
    /// (most of them, in the week), in days from today.
    private var monday: Int { CalendarDayMath.monday(of: shownFirst + span.count / 2, from: now) }
    /// Starting where Today puts it: this Monday-to-Sunday week, or today first.
    private var atHome: Bool { shownFirst == span.home(now: now) }

    /// The arrows: a day, or a page (N days, a week) from whichever day the view starts on.
    private func step(_ direction: Int) {
        editing = nil
        weekCreating = nil
        if !isMultiDay {
            onStep(direction)
        } else if let onScroll {
            onScroll(direction * span.count)
        } else {
            onStep(direction * span.count)
        }
    }

    private func setSpan(_ span: CalendarSpan) {
        editing = nil
        weekCreating = nil
        onSetSpan?(span)
    }

    /// "This week", "Next week", "Last week" in Week; "From today", "From tomorrow" in Next N days.
    private var multiDayRelative: String? {
        guard span != .week else { return weekRelative }
        switch shownFirst {
        case 0: return "From today"
        case 1: return "From tomorrow"
        case -1: return "From yesterday"
        default: return nil
        }
    }

    /// "This week", "Next week" or "Last week"; nil further away.
    private var weekRelative: String? {
        switch (monday - CalendarDayMath.monday(of: 0, from: now)) / 7 {
        case 0: "This week"
        case 1: "Next week"
        case -1: "Last week"
        default: nil
        }
    }

    /// The selected block, while it's there and saved; below the width the panel needs, none.
    private var selected: CalendarBlock? {
        guard panel != nil, width >= 1024, let id = selectedId.wrappedValue else { return nil }
        return data.blocks.first { $0.id == id && !$0.isPending }
    }

    /// The events panel shows: open, wide enough, and no block's panel in its place.
    private var showsEventsPanel: Bool { showsEvents && eventsPanel != nil && width >= 1024 && selected == nil }
    /// With a changed block's panel open: where its event moved to, previewed on the grid.
    private var changePreview: EventPreview? {
        guard let selected, let times = importChanges[selected.id]?.times else { return nil }
        let day = CalendarDayMath.dayOffset(times.start, from: now)
        return EventPreview(
            day: day,
            start: CalendarDayMath.minutes(times.start),
            end: CalendarDayMath.dayOffset(times.end, from: now) > day ? CalendarDayMath.dayMinutes : CalendarDayMath.minutes(times.end),
            title: importChanges[selected.id]?.bothMoved == true ? "Meeting’s time" : "New time",
            color: data.goal(selected.goalId)?.color ?? "slate"
        )
    }

    /// Something open on the right: a block's panel or the events panel.
    private var hasRightPanel: Bool { selected != nil || showsEventsPanel }

    private var clock: Clock { data.clock ?? .device }
    private var isToday: Bool { offset == 0 }
    private var shownDay: Date { CalendarDayMath.midnight(offset, from: now) }

    var body: some View {
        VStack(spacing: 0) {
            CalendarTopBar(
                span: onSetSpan != nil && width >= 1024 ? span : nil,
                dayCount: dayCount,
                onSetSpan: setSpan,
                showsEvents: onToggleEvents != nil && eventsPanel != nil && width >= 1024 ? showsEvents : nil,
                eventChanges: eventChanges,
                eventsHelp: eventsHelp,
                onToggleEvents: { onToggleEvents?() },
                title: isMultiDay
                    ? CalendarDay.formatRange(CalendarDay.today(CalendarDayMath.midnight(shownFirst, from: now)), days: span.count)
                    : shownDay.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_US"))),
                relative: isMultiDay ? multiDayRelative : Self.dayLabel(offset),
                page: span,
                showsToday: isMultiDay ? !atHome : !isToday,
                onToday: onToday,
                onPrevious: { step(-1) },
                onNext: { step(1) }
            )

            if isMultiDay { weekLayout } else { dayLayout }
        }
        .coordinateSpace(.calendar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay(alignment: .topLeading) {
            // The task under the pointer, until it's over the timeline and the preview takes over.
            if let placing = drag.placing, placing.moved {
                DragChip(title: placing.title, color: data.goal(placing.goalId)?.color ?? "slate")
                    .offset(x: placing.location.x + 14, y: placing.location.y + 10)
                    // Over the timeline the preview takes over; in its own list, the task itself is lifted.
                    .opacity(placing.start == nil && placing.listIndex == nil ? 1 : 0)
            }
        }
        .pointerStyle(drag.placing?.moved == true ? .grabActive : nil)
        .environment(\.taskDrag, actions == nil ? nil : drag)
        .environment(\.eventPreview, showsEventsPanel ? eventPreview : changePreview)
        .environment(\.changedBlocks, Set(importChanges.keys))
        .onChange(of: offset, initial: true) {
            // Let go in its own goal's list: a new place in the goal's order; on the timeline: a time on
            // the shown day; elsewhere on the strip: the day itself.
            drag.onDrop = { [offset, actions] placing in
                if let index = placing.listIndex {
                    actions?.reorder(placing.taskId, offset, index)
                } else if placing.onStrip {
                    actions?.plan(placing.taskId, offset)
                } else if let start = placing.start {
                    actions?.place(placing.taskId, offset, start, placing.minutes)
                }
            }
        }
    }

    private var dayLayout: some View {
        HStack(spacing: 16) {
            day
            if let selected {
                blockPanel(selected).frame(width: 320)
            } else if showsEventsPanel, let eventsPanel {
                eventsPanel.frame(width: 320)
            }
        }
        .frame(maxWidth: hasRightPanel ? 1104 : 768)
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var weekLayout: some View {
        HStack(spacing: 16) {
            VStack(spacing: 0) {
                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                WeekView(
                    data: data,
                    first: shownFirst,
                    count: span.count,
                    firstRange: firstRange,
                    onScroll: onScroll,
                    now: now,
                    clock: clock,
                    actions: actions,
                    creating: $weekCreating,
                    selectedId: selected?.id,
                    storedHour: weekHour,
                    onOpenBlock: { id in if panel != nil { selectedId.wrappedValue = id } },
                    onOpenDay: { day in
                        weekCreating = nil
                        onSetSpan?(.day)
                        onStep(day - offset)
                    }
                )
            }
            if let selected {
                blockPanel(selected).frame(width: 320)
            } else if showsEventsPanel, let eventsPanel {
                eventsPanel.frame(width: 320)
            }
        }
        // The week takes the whole width, however wide the window: more room for each day.
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    private var day: some View {
        VStack(spacing: 0) {
            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
            }
            let rows = data.goalRows(day: offset, now: now)
            if !rows.isEmpty {
                GoalStrip(
                    rows: rows,
                    blocks: data.nextBlocks(now: now),
                    today: CalendarDay.today(now),
                    dayName: Self.dayLabel(offset) ?? shownDay.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US"))),
                    open: openOnShownDay,
                    menu: actions.map { actions in { item in taskMenu(item, actions: actions) } },
                    fit: offset >= 0 ? actions.map { actions in { row in fitPanel(row, actions: actions) } } : nil
                )
            }
            // Practices: the day's sessions with no time, then, on a day of this week, what's left of each.
            let practiceSessions = data.practiceSessions(day: offset, today: now)
            let todayISO = CalendarDay.today(now)
            let shownISO = CalendarDay.addDays(todayISO, offset)
            let left = CalendarDay.weekStart(shownISO) == CalendarDay.weekStart(todayISO) ? data.practicesLeft() : []
            if !practiceSessions.isEmpty || !left.isEmpty {
                DayPracticesBar(
                    sessions: practiceSessions, left: left, goals: data.goals, today: todayISO,
                    actions: actions?.practices, openGoal: actions?.openGoal
                )
            }
            TimelineScroll(
                data: data, offset: offset, now: now, clock: clock, actions: actions, editing: $editing,
                selectedId: selected?.id, ringedGoals: openOnShownDay.wrappedValue,
                onSelect: panel != nil && width >= 1024 ? { selectedId.wrappedValue = $0 } : nil,
                storedHour: dayHour
            )
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    /// An over goal's Make it fit for the day, as the planning board opens it. Applying a move plans
    /// the task where it's going; protecting time makes a session; taking time shortens the other
    /// goal's session and gives its end to this one.
    private func fitPanel(_ row: DayGoalRow, actions: CalendarActions) -> AnyView {
        let board = data.board(now: now)
        guard let goal = board.goal(row.goal.id) else { return AnyView(EmptyView()) }
        let day = offset
        let fit = BoardFitActions(
            move: { moves, _ in
                for move in moves { actions.changeTask(move.task.id, move.to.patch(today: board.today)) }
            },
            protect: { slot, goalId in
                let start = CalendarDayMath.minutes(slot.start)
                actions.create(day, start, start + slot.minutes, goalId, nil, .session)
            },
            give: { give, goalId in actions.giveTime(give.blockId, give.slot.minutes, goalId) }
        )
        let dayName = Self.dayLabel(offset) ?? CalendarDay.weekday(row.day)
        return AnyView(MakeItFitPanel(goal: goal, day: row.day, dayName: dayName, in: board, now: now, clock: clock, actions: fit))
    }

    /// A task's menu on the strip: the usual rows, and what its goal's time that day suggests.
    private func taskMenu(_ item: StripItem, actions: CalendarActions) -> AnyView {
        guard let row = data.goalRows(day: offset, now: now).first(where: { $0.id == item.task.goalId }),
              let suggestions = data.suggestions(for: item.task.id, day: offset, now: now) else { return AnyView(EmptyView()) }
        return AnyView(DayTaskMenu(
            task: item.task, goal: row.goal, suggestions: suggestions, sessionMinutes: row.capacity.protected,
            day: offset, dayISO: row.day, today: CalendarDay.today(now), clock: clock, actions: actions
        ))
    }

    private func blockPanel(_ block: CalendarBlock) -> some View {
        let start = CalendarDayMath.minutes(block.startsAt)
        let day = CalendarDayMath.dayOffset(block.startsAt, from: now)
        let end = CalendarDayMath.dayOffset(block.endsAt, from: now) > day ? CalendarDayMath.dayMinutes : CalendarDayMath.minutes(block.endsAt)
        let range = clock.formatRange(start, end)
        let relative = Self.dayLabel(day)
        let en = Locale(identifier: "en_US")
        let date = block.startsAt.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(en))
        let when = "\(date)\(relative.map { " (\($0.lowercased()))" } ?? ""), \(range)"
        return BlockPanel(
            block: block,
            goal: data.goal(block.goalId),
            goals: data.goals,
            description: data.description(of: block),
            day: day,
            start: start,
            end: end,
            clock: clock,
            when: when,
            openTaskIds: Set(data.tasks.map(\.id)),
            ended: block.endsAt <= now,
            now: now,
            actions: panel,
            calendar: actions,
            importChange: importChanges[block.id],
            onClose: { selectedId.wrappedValue = nil }
        )
        .id(block.id)
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
    /// Day, Next N days or Week; nil hides the switch (the multi-day views need a wide window).
    var span: CalendarSpan?
    /// The count Next N days last showed, for its button while another view is on.
    var dayCount = 3
    var onSetSpan: (CalendarSpan) -> Void = { _ in }
    /// Whether Calendar import's events panel is open; nil hides its button.
    var showsEvents: Bool?
    /// Imported events that changed since, as a count on the button.
    var eventChanges = 0
    var eventsHelp = "Events from Google"
    var onToggleEvents: () -> Void = {}
    let title: String
    var relative: String?
    /// What the arrows move by: a day, N days or a week.
    var page = CalendarSpan.day
    var showsToday: Bool
    var onToday: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let span {
                ViewSwitch(span: span, dayCount: dayCount, onSet: onSetSpan)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground).lineLimit(1)
                if let relative {
                    Text(relative).appText(.sm).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if showsEvents != nil {
                // The same open or closed: the panel beside the days says it's open.
                BarButton(action: onToggleEvents) { Icon.calendarImport.image(size: 16).frame(width: 32) }
                    .overlay(alignment: .topTrailing) {
                        if eventChanges > 0 {
                            Text("\(eventChanges)").font(.app(10, .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.background)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Theme.foreground, in: .capsule)
                                .overlay(Capsule().strokeBorder(Theme.background, lineWidth: 2).padding(-2))
                                .offset(x: 6, y: -6)
                                .allowsHitTesting(false)
                        }
                    }
                    .help(eventsHelp)
                    .accessibilityLabel(eventChanges > 0 ? "Events, \(eventChanges) changed" : "Events")
            }
            if showsToday {
                BarButton(action: onToday) { Text("Today").appText(.sm, .medium).padding(.horizontal, 12) }
            }
            HStack(spacing: 4) {
                BarButton(action: onPrevious) { Icon.arrowLeft.image(size: 16).frame(width: 32) }
                    .help("Previous \(pageName)")
                    .accessibilityLabel("Previous \(pageName)")
                BarButton(action: onNext) { Icon.arrowRight.image(size: 16).frame(width: 32) }
                    .help("Next \(pageName)")
                    .accessibilityLabel("Next \(pageName)")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }

    /// "day", "3 days", "week".
    private var pageName: String { page.label.lowercased() }

    /// Day, N days or Week: `h-8 rounded-lg border bg-card p-0.5`, the chosen one washed. N days
    /// opens on the count it last showed; its chevron picks another.
    private struct ViewSwitch: View {
        let span: CalendarSpan
        let dayCount: Int
        let onSet: (CalendarSpan) -> Void
        @State private var daysFrame = CGRect.zero
        @Environment(\.overlays) private var overlays

        private var count: Int { span.dayCount ?? dayCount }
        private var isMenuOpen: Bool { overlays?.presented?.owner == "calendar-days" }

        var body: some View {
            HStack(spacing: 0) {
                SwitchOption(title: "Day", isOn: span == .day) { onSet(.day) }
                SwitchOption(title: "\(count) days", isOn: span.dayCount != nil, onMenu: openMenu, isMenuOpen: isMenuOpen) {
                    onSet(.days(count))
                }
                .modifier(AnchorReader(frame: $daysFrame))
                SwitchOption(title: "Week", isOn: span == .week) { onSet(.week) }
            }
            .padding(2)
            .frame(height: 32)
            .background(Theme.card, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
        }

        private func openMenu() {
            guard let overlays else { return }
            if isMenuOpen { return overlays.dismiss() }
            overlays.showMenu(anchor: daysFrame, owner: "calendar-days", alignLeading: true) {
                DaysMenu(selected: span.dayCount) { n in
                    overlays.dismiss()
                    onSet(.days(n))
                }
            }
        }

        private struct SwitchOption: View {
            let title: String
            let isOn: Bool
            /// Opens a menu from a chevron beside the title; without it there's none.
            var onMenu: (() -> Void)?
            var isMenuOpen = false
            let action: () -> Void
            @State private var isHovered = false
            @State private var isChevronHovered = false

            var body: some View {
                HStack(spacing: 0) {
                    Button(action: action) {
                        Text(title).appText(.sm, .medium).monospacedDigit()
                            .foregroundStyle(isOn || isHovered ? Theme.foreground : Theme.muted)
                            .padding(.leading, 10)
                            .padding(.trailing, onMenu == nil ? 10 : 4)
                            .frame(maxHeight: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered = $0 }
                    if let onMenu {
                        Button(action: onMenu) {
                            Icon.chevronDown.image(size: 12)
                                .foregroundStyle(isOn || isChevronHovered || isMenuOpen ? Theme.foreground : Theme.muted)
                                .frame(width: 20)
                                .frame(maxHeight: .infinity)
                                .background(isChevronHovered || isMenuOpen ? Theme.foreground(0.06) : .clear, in: .rect(cornerRadius: 5))
                                .padding(.trailing, 2)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .onHover { isChevronHovered = $0 }
                        .help("Show 3, 5 or 7 days")
                        .accessibilityLabel("How many days")
                    }
                }
                .background(isOn ? Theme.foreground(0.07) : .clear, in: .rect(cornerRadius: 6))
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
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

/// Next 3, 5 or 7 days, from the switch's chevron; the one showing is ticked.
struct DaysMenu: View {
    /// The count showing, if Next N days is on.
    let selected: Int?
    let onPick: (Int) -> Void

    var body: some View {
        MenuPanel(width: 200) {
            ForEach(CalendarSpan.dayCounts, id: \.self) { n in
                MenuItem(icon: .calendarSmall, title: CalendarSpan.days(n).title, isChecked: n == selected) { onPick(n) }
            }
        }
    }
}

// MARK: - Flow layout (the strip by goal is GoalStrip.swift)

/// A view a FlowLayout may leave out when it would start a new row, such as a pill that's
/// invisible until hover: it keeps its place on a row that has room, without adding a blank one.
struct FlowOptional: LayoutValueKey {
    static let defaultValue = false
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
        let rows = arrange(subviews, width: bounds.width)
        let placed = Set(rows.flatMap(\.indices))
        // Left out: placed at the corner with no size, so they take no room.
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: bounds.origin, proposal: .zero)
        }
        for row in rows {
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
                if view[FlowOptional.self] { continue }
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

/// The day's hours, scrolled to about an hour before now when it opens on today. Pinch to make
/// the hours taller or shorter.
private struct TimelineScroll: View {
    let data: CalendarData
    let offset: Int
    let now: Date
    let clock: Clock
    let actions: CalendarActions?
    @Binding var editing: BlockEditing?
    let selectedId: String?
    /// Goals open on the strip: their sessions are ringed.
    var ringedGoals: Set<String> = []
    let onSelect: ((String) -> Void)?
    /// How tall an hour is, kept between visits; without it the timeline keeps its own.
    let storedHour: Binding<CGFloat>?
    @Environment(\.taskDrag) private var drag
    @State private var position = ScrollPosition()
    @State private var scrollY: CGFloat = 0
    @State private var maxScrollY: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// The day it last opened on its focus, so it does so once the scroll view has a size.
    @State private var focusedOffset: Int?
    @State private var ownHour = DayGrid.hour
    /// The hour height mid-pinch, saved when it ends.
    @State private var pinchHour: CGFloat?
    /// Where a pinch last scrolled to, applied again once the content has its new height.
    @State private var pinchY: CGFloat?

    /// How close to the top or bottom edge a dragged task starts it scrolling.
    private static let scrollEdge: CGFloat = 56

    private var range: ClosedRange<CGFloat> { HourGrid.range(viewport: viewport, pad: DayGrid.pad, most: DayGrid.maxHour) }

    private var grid: HourGrid {
        let hour = pinchHour ?? storedHour?.wrappedValue ?? ownHour
        return HourGrid(hour: min(max(hour, range.lowerBound), range.upperBound), pad: DayGrid.pad)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DayTimeline(
                    data: data, offset: offset, now: now, clock: clock, actions: actions, editing: $editing,
                    selectedId: selectedId, ringedGoals: ringedGoals, onSelect: onSelect, proxy: proxy
                )
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
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) {
                [$0.contentOffset.y, $0.contentSize.height - $0.containerSize.height, $0.containerSize.height]
            } action: { _, value in
                scrollY = value[0]
                maxScrollY = max(value[1], 0)
                viewport = value[2]
                if let y = pinchY {
                    // The scroll may have been held to the old height; once the new one is in, go there.
                    pinchY = nil
                    if abs(scrollY - y) > 0.5 { position.scrollTo(y: y) }
                }
                if focusedOffset != offset { scrollToFocus() }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .calendar) } action: { drag?.viewportFrame = $0 }
            .task(id: drag?.placing?.moved == true) { await scrollWhileDragging() }
            .onChange(of: offset) { scrollToFocus() }
        }
    }

    /// While a task is dragged near the top or bottom edge, scroll that way.
    private func scrollWhileDragging() async {
        while !Task.isCancelled {
            guard let drag, let placing = drag.placing, placing.moved else { return }
            let view = drag.viewportFrame
            let p = placing.location
            if p.x >= view.minX, p.x <= view.maxX {
                let above = view.minY + Self.scrollEdge - p.y
                let below = p.y - (view.maxY - Self.scrollEdge)
                var step: CGFloat = 0
                if above > 0, above < Self.scrollEdge * 2 { step = -min(18, (above / 4).rounded(.up)) }
                else if below > 0, below < Self.scrollEdge * 2 { step = min(18, (below / 4).rounded(.up)) }
                let target = min(max(scrollY + step, 0), maxScrollY)
                if target != scrollY {
                    position.scrollTo(y: target)
                    scrollY = target
                }
            }
            drag.update()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Open on the current time (or waking up, on other days), with about an hour above it. By
    /// position rather than by an hour line's id: the lines are placed with `.offset`, which
    /// layout doesn't see, so scrolling to one landed on midnight.
    private func scrollToFocus() {
        guard viewport > 0 else { return }
        focusedOffset = offset
        let focus = offset == 0 ? CalendarDayMath.minutes(now) : data.wakeTime
        position.scrollTo(y: grid.scrollY(keeping: CGFloat(max(0, focus / 60 - 1) * 60), at: DayGrid.pad, viewport: viewport))
    }
}

/// What the calendar can change, handed down from its model.
struct CalendarActions {
    var create: (_ day: Int, _ start: Int, _ end: Int, _ goalId: String, _ title: String?, _ kind: NewBlockKind) -> Void
    var saveDetails: (_ blockId: String, _ goalId: String, _ title: String?) -> Void
    /// Make protected time reserved (kept for its own sake) or a session again.
    var setReserved: (_ blockId: String, _ reserved: Bool) -> Void = { _, _ in }
    /// Make a block a session, reserved time or a task's time.
    var setKind: (_ blockId: String, _ kind: BlockKind) -> Void = { _, _ in }
    /// By `delta` minutes and, moving it whole, `days` days.
    var move: (_ blockId: String, _ edge: BlockEdge, _ delta: Int, _ days: Int) -> Void
    var moveToTomorrow: (_ blockId: String) -> Void
    var toggleDone: (_ blockId: String) -> Void
    var remove: (_ blockId: String) -> Void
    /// A task dropped on `day` at `start`: a new intention, or its next block moved there.
    var place: (_ taskId: String, _ day: Int, _ start: Int, _ minutes: Int) -> Void
    /// Plan a task for `day` without a time, or take it off its day (nil).
    var plan: (_ taskId: String, _ day: Int?) -> Void
    /// Move a task to `index` among its goal's other tasks on `day`'s strip, changing the goal's order.
    var reorder: (_ taskId: String, _ day: Int, _ index: Int) -> Void = { _, _, _ in }
    /// A task on the strip checked off, deleted, or given another day, week, estimate or due date.
    var markTaskDone: (_ taskId: String) -> Void = { _ in }
    var deleteTask: (_ taskId: String) -> Void = { _ in }
    var changeTask: (_ taskId: String, _ patch: TaskPatch) -> Void = { _, _ in }
    /// The end of a session, `minutes` long, given to another goal.
    var giveTime: (_ blockId: String, _ minutes: Int, _ goalId: String) -> Void = { _, _, _ in }
    /// The goal a new block starts with.
    var defaultGoalId: () -> String?
    /// A block's menu offers its goal's page.
    var openGoal: ((String) -> Void)?
    /// Practices' sessions off the calendar; nil leaves them read-only.
    var practices: PracticeActions? = nil
}

/// What the calendar can do with practices' sessions that aren't blocks.
struct PracticeActions {
    /// Logs one done today.
    var logToday: (_ goalId: String) -> Void
    /// Plans one for a day ("YYYY-MM-DD"), with no time.
    var plan: (_ goalId: String, _ day: String) -> Void
    var setDone: (_ sessionId: String, _ done: Bool) -> Void
    var remove: (_ sessionId: String) -> Void
}

extension CalendarActions {
    /// Does nothing: for previews and snapshot tests.
    static var preview: CalendarActions {
        CalendarActions(
            create: { _, _, _, _, _, _ in }, saveDetails: { _, _, _ in }, move: { _, _, _, _ in }, moveToTomorrow: { _ in },
            toggleDone: { _ in }, remove: { _ in }, place: { _, _, _, _ in }, plan: { _, _ in }, defaultGoalId: { nil },
            openGoal: { _ in }
        )
    }
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
    @Binding var editing: BlockEditing?
    /// The block whose panel is open, ringed in its goal's colour.
    var selectedId: String?
    /// Goals open on the strip: their sessions are ringed, lightly.
    var ringedGoals: Set<String> = []
    /// Clicking a block opens its panel; without it, the click edits it in place.
    var onSelect: ((String) -> Void)?
    /// A block's menu offers to give its time to another goal, where that's wired (nothing does yet).
    var onGive: ((String) -> Void)?
    var proxy: ScrollViewProxy?

    @State private var drawing: Drawing?
    @State private var dragging: BlockDrag?
    @State private var width: CGFloat = 0
    @Environment(\.overlays) private var overlays
    /// A hovered event from the events panel, previewed where it would go.
    @Environment(\.eventPreview) private var eventPreview
    @Environment(\.taskDrag) private var drag
    @Environment(\.dayGrid) private var grid

    /// How close (in points) an hour's label can come to the now line's before it hides.
    private static let nowClearance: CGFloat = 40
    /// How tall sleep needs to be for its label: 45 minutes at the usual hour height.
    private static let sleepLabelHeight: CGFloat = 132

    init(data: CalendarData, offset: Int, now: Date, clock: Clock, actions: CalendarActions? = nil,
         editing: Binding<BlockEditing?> = .constant(nil), selectedId: String? = nil, ringedGoals: Set<String> = [],
         onSelect: ((String) -> Void)? = nil,
         onGive: ((String) -> Void)? = nil, proxy: ScrollViewProxy? = nil) {
        self.data = data
        self.offset = offset
        self.now = now
        self.clock = clock
        self.actions = actions
        _editing = editing
        self.selectedId = selectedId
        self.ringedGoals = ringedGoals
        self.onSelect = onSelect
        self.onGive = onGive
        self.proxy = proxy
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
                let nearNow = isToday && abs(grid.y(hour * 60) - grid.y(nowMinutes)) < Self.nowClearance
                ZStack(alignment: .topLeading) {
                    Text(hour < 24 ? clock.formatHour(hour) : "")
                        .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: DayGrid.gutter - 8, height: 14, alignment: .trailing)
                        .offset(y: -7)
                        .opacity(nearNow ? 0 : 1)
                    Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.leading, DayGrid.gutter)
                }
                .offset(y: grid.y(hour * 60))
                .allowsHitTesting(false)
            }

            // Sleep
            ForEach(CalendarDayMath.sleepSpans(sleepStart: data.sleepStart, wakeTime: data.wakeTime), id: \.lowerBound) { span in
                SleepShade(showsLabel: grid.height(span.upperBound - span.lowerBound) >= Self.sleepLabelHeight)
                    .frame(height: grid.y(span.upperBound) - grid.y(span.lowerBound))
                    .padding(.leading, DayGrid.gutter)
                    .offset(y: grid.y(span.lowerBound))
            }

            // Time that's already gone
            if let pastUntil {
                Rectangle().fill(Theme.foreground(0.03))
                    .frame(height: grid.y(pastUntil) - DayGrid.pad)
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
                        isSelected: block.id == selectedId,
                        isRinged: ringedGoals.contains(block.goalId) && block.kind == .session,
                        onDrag: { edge, dy in dragBlock(segment, edge: edge, dy: dy) },
                        onDragEnd: { edge in endBlockDrag(block, segment, edge: edge) },
                        onMenu: { anchor in showMenu(block, segment, anchor: anchor) }
                    )
                    .frame(height: max(grid.y(end) - grid.y(start) - 2, 14))
                    .contextPanel(owner: block.id, isEnabled: actions != nil && !block.isPending) { menu(block, segment) }
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: grid.y(start) + 1)
                    .zIndex(moving != nil ? 1 : 0)
                }
            }

            // The block being drawn
            if let draft {
                DraftBlock(label: clock.formatRange(draft.start, draft.end))
                    .frame(height: grid.y(draft.end) - grid.y(draft.start) - 2)
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: grid.y(draft.start) + 1)
                    .zIndex(2)
            }

            // Where a dragged task would land
            if let placing = drag?.placing, placing.moved, let start = placing.start {
                let end = start + placing.minutes
                DropPreview(title: placing.title, color: data.goal(placing.goalId)?.color ?? "slate", start: start, end: end, clock: clock)
                    .frame(height: max(grid.y(end) - grid.y(start) - 2, 14))
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: grid.y(start) + 1)
                    .zIndex(2)
            }

            // A hovered event, where it would go: over a block, on its right half
            if let eventPreview, eventPreview.day == offset {
                let height = max(grid.y(eventPreview.end) - grid.y(eventPreview.start) - 2, 14)
                HStack(spacing: 0) {
                    if eventPreview.overlaps(data.blocks, now: now) { Color.clear }
                    EventPreviewCard(
                        title: eventPreview.title, color: eventPreview.color,
                        range: clock.formatRange(eventPreview.start, eventPreview.end), height: height
                    )
                }
                .frame(height: height)
                .padding(.leading, DayGrid.gutter + 4)
                .padding(.trailing, 8)
                .offset(y: grid.y(eventPreview.start) + 1)
                .allowsHitTesting(false)
                .zIndex(2)
            }

            // Now
            if isToday {
                NowLine(label: clock.format(minutes: nowMinutes)).offset(y: grid.y(nowMinutes))
                    .zIndex(3)
            }

            if let editing, editing.day == offset, isShown(editing) {
                popover(editing)
                    .zIndex(4)
            }
        }
        .frame(height: grid.height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .calendar) } action: { drag?.timelineFrame = $0 }
        .onChange(of: grid, initial: true) { drag?.grid = grid }
        .onChange(of: offset) { if editing?.day != offset { editing = nil } }
        .onChange(of: editing) { if editing != nil { scrollToPopover() } }
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
                    let m = grid.minutes(at: value.startLocation.y)
                    drawing = Drawing(from: m, to: m)
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
        let raw = Int((dy / grid.hour * 60 / CGFloat(step)).rounded()) * step
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
            // A click on the block: open its panel, or edit it in place.
            if edge == .move {
                if let onSelect { onSelect(block.id) } else { edit(block, segment) }
            }
            return
        }
        if current.delta != 0 { actions?.move(block.id, current.edge, current.delta, 0) }
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
    }

    /// Bring the popover into view.
    private func scrollToPopover() {
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
        editing = nil
        overlays?.showMenu(anchor: anchor, owner: block.id) { menu(block, segment) }
    }

    /// The same for ⋯ and a right-click.
    @ViewBuilder private func menu(_ block: CalendarBlock, _ segment: DaySegment) -> some View {
        if let actions {
            BlockMenu(
                block: block, goal: data.goal(block.goalId), day: segment.day, actions: actions,
                onEdit: {
                    editing = nil
                    edit(block, segment)
                },
                onGive: onGive.map { give in { give(block.id) } }
            )
        }
    }

    /// Below the block, or above it near the end of the day. Time just drawn gets the new block
    /// popover; a block already there, the one that renames it or changes its goal.
    @ViewBuilder private func popover(_ editing: BlockEditing) -> some View {
        let top = grid.y(editing.start)
        let bottom = grid.y(editing.end)
        let above = bottom + 8 + BlockPopover.estimatedHeight > grid.height
        Group {
            switch editing.mode {
            case .create:
                NewBlockPopover(
                    goals: data.goals,
                    tasks: data.unscheduledTasks(now: now),
                    goalId: editing.goalId,
                    timeLabel: data.newBlockLabel(day: editing.day, start: editing.start, end: editing.end, now: now, clock: clock),
                    onAdd: { goalId, title, kind in
                        self.editing = nil
                        actions?.create(editing.day, editing.start, editing.end, goalId, title, kind)
                    },
                    onCancel: { self.editing = nil }
                )
            case .edit(_, let intention):
                let weekday = CalendarDayMath.midnight(editing.day, from: now)
                    .formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
                BlockPopover(
                    goals: data.goals,
                    goalId: editing.goalId,
                    title: editing.title ?? "",
                    intention: intention,
                    timeLabel: "\(weekday) · \(clock.formatRange(editing.start, editing.end))",
                    onSave: { goalId, title in save(editing, goalId: goalId, title: title) },
                    onCancel: { self.editing = nil }
                )
            }
        }
        .id(editing.key)
        .frame(width: max(min(320, width - DayGrid.gutter - 24), 240))
        .alignmentGuide(.top) { d in above ? d.height - (top - 8) : -(bottom + 8) }
        .alignmentGuide(.leading) { _ in -(DayGrid.gutter + 12) }
        .id(Self.popoverID)
    }

    private func save(_ value: BlockEditing, goalId: String, title: String?) {
        editing = nil
        switch value.mode {
        case .create: actions?.create(value.day, value.start, value.end, goalId, title, .session)
        case .edit(let id, _): actions?.saveDetails(id, goalId, title)
        }
    }
}

/// What a block's ⋯ menu and a right-click on it offer: edit or open it, tick off its task, switch
/// a session and reserved time, give its time away (where that's wired), move it a day on, open its
/// goal, and remove it.
struct BlockMenu: View {
    let block: CalendarBlock
    /// Its project or practice, to name it in "Open …".
    var goal: CalendarGoal?
    /// Its day, in days from today.
    let day: Int
    let actions: CalendarActions
    var editTitle = "Edit"
    /// Left out where the block is already open to edit (its panel).
    var onEdit: (() -> Void)?
    var onGive: (() -> Void)?

    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel(width: 208) {
            if let onEdit {
                MenuItem(icon: .edit, title: editTitle) { run(onEdit) }
            }
            if block.taskId != nil {
                MenuItem(icon: block.taskDone ? .reopen : .tick, title: block.taskDone ? "Reopen task" : "Mark done") {
                    run { actions.toggleDone(block.id) }
                }
            }
            if !block.isIntention {
                MenuItem(icon: block.reserved ? .target : .clock, title: block.reserved ? "Make it a session" : "Reserve this time") {
                    run { actions.setReserved(block.id, !block.reserved) }
                }
                if let onGive {
                    // Opens the give-time panel beside the block, in place of this menu.
                    MenuItem(icon: .plan, title: "Give time…") { run(onGive) }
                }
            }
            MenuItem(icon: .arrowForward, title: day == 0 ? "Move to tomorrow" : "Move to next day") {
                run { actions.moveToTomorrow(block.id) }
            }
            if let openGoal = actions.openGoal {
                MenuSeparator()
                MenuItem(icon: .target, title: "Open \(goal?.kind.noun ?? "project")") { run { openGoal(block.goalId) } }
            }
            MenuSeparator()
            MenuItem(icon: .delete, title: "Remove", isDestructive: true) { run { actions.remove(block.id) } }
        }
    }

    private func run(_ action: () -> Void) {
        overlays?.dismiss()
        action()
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
    var isSelected = false
    /// Its goal is open on the strip and it's one of the goal's sessions: a lighter ring.
    var isRinged = false
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
            .overlay {
                // Its panel is open: a ring in its goal's colour; its goal open on the strip, a lighter one.
                if isSelected || isRinged {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(GoalPalette.color(goal?.color ?? "slate").opacity(isSelected ? 0.6 : 0.3), lineWidth: 2)
                        .padding(-2)
                        .allowsHitTesting(false)
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
/// Drawn with a narrower gutter where the timeline is narrower.
struct NowLine: View {
    let label: String
    var gutter: CGFloat = DayGrid.gutter

    var body: some View {
        ZStack(alignment: .leading) {
            Text(label).font(.app(11, .semibold)).monospacedDigit()
                .foregroundStyle(Color(nsColor: .rgb(0xef4444)))
                .frame(width: gutter - 8, alignment: .trailing)
            Rectangle().fill(Color(nsColor: .rgb(0xef4444))).frame(height: 2)
                .padding(.leading, gutter)
            Circle().fill(Color(nsColor: .rgb(0xef4444))).frame(width: 10, height: 10)
                .offset(x: gutter - 5)
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
    /// The week's narrower card: a smaller label that shrinks with the block.
    var compact = false

    /// Height a block needs for its title and time on two lines; shorter ones get a single line.
    private static let twoLines: CGFloat = 48
    @Environment(\.dayGrid) private var grid
    /// Imported blocks whose events have changed since.
    @Environment(\.changedBlocks) private var changedBlocks

    private var color: String { goal?.color ?? "slate" }
    private var title: String { block.title ?? goal?.title ?? "Protected time" }
    private var time: String { clock.formatRange(start, end) }
    private var isShort: Bool { grid.height(end - start) < Self.twoLines }

    var body: some View {
        GeometryReader { geometry in
            let filled = geometry.size.height * elapsed
            ZStack(alignment: .topLeading) {
                // The block, drawn filled: solid for an intention, hatched for a session of protected
                // time, plain and quieter for reserved time, which isn't there to be worked in.
                Rectangle().fill(block.isIntention
                    ? GoalPalette.mix(color, light: 0.18, dark: 0.24)
                    : block.reserved
                        ? GoalPalette.mix(color, light: 0.07, dark: 0.09)
                        : GoalPalette.mix(color, light: 0.10, dark: 0.13))
                if !block.isIntention, !block.reserved {
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

                if compact { compactLabel(height: geometry.size.height) } else { label }

                if block.recapWaiting, !compact || geometry.size.height >= 18 {
                    Circle().fill(GoalPalette.color(color)).frame(width: 6, height: 6)
                        .opacity(isHovered ? 0 : block.hasRecapDraft ? 1 : 0.6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(.top, compact ? 6 : 10)
                        .padding(.trailing, compact ? 6 : 10)
                        .help(block.hasRecapDraft ? "Recap to review" : "Drafting recap")
                }

                // Imported from a calendar: the events button's icon in the corner, beside a
                // waiting recap's dot, out of the way of the menu that shows on hover.
                if let source = block.source, !compact || geometry.size.height >= 18 {
                    let changed = changedBlocks.contains(block.id)
                    // Changed since: the sync arrows on a dark dot, in the same place.
                    (changed ? Icon.refresh : Icon.calendarImport).image(size: 11)
                        .foregroundStyle(changed ? Theme.background : Theme.muted)
                        .frame(width: 18, height: 18)
                        .background(changed ? Theme.foreground : Theme.card.opacity(0.7), in: changed ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 5)))
                        .opacity(isHovered ? 0 : 1)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(.top, compact ? 3 : 6)
                        .padding(.trailing, (compact ? 3 : 6) + (block.recapWaiting ? 14 : 0))
                        .help(changed ? "Changed in \(source.calendar) since you imported it" : "From \(source.calendar) · Google")
                        .accessibilityLabel(changed ? "Imported from \(source.calendar), changed since" : "Imported from \(source.calendar)")
                }
            }
            .clipShape(.rect(cornerRadius: compact ? 6 : 8))
            .overlay(RoundedRectangle(cornerRadius: compact ? 6 : 8).strokeBorder(GoalPalette.color(color).opacity(0.22)))
        }
        // A practice's block that didn't happen stays where it was, faded, so the week still reads true.
        .opacity(block.isPending ? 0.6 : block.missed ? 0.4 : 1)
        .help(block.missed ? "\(title) · didn’t happen" : compact ? "\(title)\n\(time)" : "\(title) · \(time)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.kindLabel): \(title), \(time)\(block.missed ? ", didn’t happen" : "")")
    }

    /// In the week: the title clamped to what fits, and the time once there's room.
    @ViewBuilder private func compactLabel(height: CGFloat) -> some View {
        if height >= 18 {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(12.5, .medium))
                    .strikethrough(block.taskDone, color: Theme.foreground(0.25))
                    .foregroundStyle(block.taskDone ? Theme.muted : Theme.foreground)
                    .lineLimit(height >= 110 ? 3 : height >= 60 ? 2 : 1)
                if height >= 60 {
                    Text(time).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.leading, 8)
            // Clear of the imported mark in the corner.
            .padding(.trailing, block.source == nil ? 8 : 22)
            .padding(.top, height >= 44 ? 6 : 2)
        }
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

#Preview("Day") {
    DayView(data: Fixtures.calendar, offset: 0, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 1180, height: 760)
}
