import SwiftUI

/// A practice's own page, from the Projects & practices page in supervibes-design: the way back to Life; the header
/// (its round badge, its area and rhythm under the name, Log one, and a menu to pause, edit or delete it); this week
/// day by day; how it's holding, which is its count rather than a read; and the sessions that counted. Its sources and
/// activity follow in `sections`.
struct PracticePage<Sections: View>: View {
    let detail: GoalDetail
    var headerError: String?
    var practiceError: String?
    var onBack: () -> Void = {}
    var onOpenArea: (String) -> Void = { _ in }
    var areas: [Area] = []
    var onSetArea: ((String?) -> Void)?
    var onNewArea: (() -> Void)?
    /// Logs a session done today.
    var onLogOne: () -> Void = {}
    /// Pauses it until a day ("YYYY-MM-DD"), or until it's resumed with nil.
    var onPause: (String?) -> Void = { _ in }
    var onResume: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    @ViewBuilder var sections: Sections

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(action: onBack).padding(.bottom, 32)
                if let practice = detail.goal.practice {
                    PracticeHeader(
                        detail: detail,
                        practice: practice,
                        error: headerError ?? practiceError,
                        onOpenArea: onOpenArea,
                        areas: areas,
                        onSetArea: onSetArea,
                        onNewArea: onNewArea,
                        onLogOne: onLogOne,
                        onPause: onPause,
                        onResume: onResume,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                    PracticeWeekSection(detail: detail, practice: practice).padding(.top, 32)
                    HoldingCard(detail: detail, practice: practice).padding(.top, 40)
                    SessionsList(detail: detail).padding(.top, 56)
                }
                sections
            }
            .frame(maxWidth: 768, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

extension PracticePage where Sections == EmptyView {
    init(detail: GoalDetail, headerError: String? = nil, practiceError: String? = nil) {
        self.init(detail: detail, headerError: headerError, practiceError: practiceError) { EmptyView() }
    }
}

// MARK: - Header

private struct PracticeHeader: View {
    let detail: GoalDetail
    let practice: Practice
    let error: String?
    let onOpenArea: (String) -> Void
    let areas: [Area]
    let onSetArea: ((String?) -> Void)?
    let onNewArea: (() -> Void)?
    let onLogOne: () -> Void
    let onPause: (String?) -> Void
    let onResume: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.overlays) private var overlays
    @State private var menuAnchor = CGRect.zero

    var body: some View {
        let goal = detail.goal
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                GoalBadge(goal: goal, size: .lg)
                    .saturation(practice.paused == nil ? 1 : 0)
                    .opacity(practice.paused == nil ? 1 : 0.6)
                Spacer()
                if practice.paused != nil {
                    PrimaryButton(title: "Resume now", icon: .play, action: onResume)
                } else {
                    LogOneButton(action: onLogOne)
                }
                RoundIconButton(icon: .more, action: openMenu)
                    .modifier(AnchorReader(frame: $menuAnchor))
                    .accessibilityLabel("Practice options")
            }

            Text(goal.title)
                .appText(.xl3, .semibold, tracking: -0.03)
                .foregroundStyle(Theme.foreground)
                .padding(.top, 20)

            // Under the name: its area, then its rhythm, where a project has its target date.
            HStack(spacing: 12) {
                if let area = detail.area {
                    AreaChip(area: area) { onOpenArea(area.id) }
                }
                RhythmLabel(perWeek: practice.perWeek, minMinutes: practice.minMinutes, iconSize: 14)
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                if detail.area == nil, let onSetArea {
                    AddToAreaChip(areas: areas, onPick: onSetArea, onNewArea: onNewArea)
                }
            }
            .padding(.top, 8)

            if let description = goal.description, !description.isEmpty {
                Text(description)
                    .font(.app(15.2))
                    .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                    .foregroundStyle(Theme.foreground(0.75))
                    .frame(maxWidth: 672, alignment: .leading)
                    .padding(.top, 12)
            }

            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 16)
            }
        }
    }

    private func openMenu() {
        guard let overlays else { return }
        let today = detail.today
        overlays.showMenu(anchor: menuAnchor) {
            MenuPanel(width: 220) {
                if practice.paused != nil {
                    MenuItem(icon: .play, title: "Resume now") { run(onResume) }
                } else {
                    MenuItem(icon: .pause, title: "Pause for a week") { run { onPause(CalendarDay.addDays(today, 7)) } }
                    MenuItem(icon: .pause, title: "Pause for two weeks") { run { onPause(CalendarDay.addDays(today, 14)) } }
                    MenuItem(icon: .pause, title: "Pause until I resume it") { run { onPause(nil) } }
                }
                MenuSeparator()
                MenuItem(icon: .edit, title: "Edit practice") { run(onEdit) }
                MenuItem(icon: .delete, title: "Delete practice", isDestructive: true) { run(onDelete) }
            }
        }
    }

    private func run(_ action: () -> Void) {
        overlays?.dismiss()
        action()
    }
}

/// "✓ Log one": counts a session done today that never touched the calendar.
private struct LogOneButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.tick.image(size: 14)
                Text("Log one").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Count a session done today that wasn’t on the calendar")
    }
}

// MARK: - This week

/// This week, day by day: each day's sessions as one mark (done, planned or didn't happen), with what's done and
/// planned beside the heading as pips.
private struct PracticeWeekSection: View {
    let detail: GoalDetail
    let practice: Practice

    private var days: [String] { (0..<7).map { CalendarDay.addDays(practice.week.start, $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This week").appText(.sm, .semibold).foregroundStyle(Theme.foreground)
                Text(CalendarDay.formatWeek(practice.week.start)).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
                Spacer()
                if practice.paused == nil {
                    HStack(spacing: 8) {
                        PracticePips(pips: practice.pips, color: detail.goal.color, size: 9)
                        Text(summary).appText(.sm, .medium).monospacedDigit().foregroundStyle(Theme.foreground)
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, today: detail.today, sessions: sessions(on: day), color: detail.goal.color)
                }
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .opacity(practice.paused == nil ? 1 : 0.6)
            .padding(.top, 12)

            if let aside {
                Text(aside).appText(.sm).foregroundStyle(Theme.muted).padding(.top, 8)
            }
        }
    }

    private func sessions(on day: String) -> [PracticeSession] {
        (detail.practice?.sessions ?? []).filter { $0.day == day }
    }

    /// "1 of 3 done · 2 planned", or "2 of 3 done · 1 to go" with nothing planned.
    private var summary: String {
        let done = "\(practice.week.done) of \(practice.perWeek) done"
        if practice.week.planned > 0 { return "\(done) · \(practice.week.planned) planned" }
        if practice.left > 0 { return "\(done) · \(practice.left) to go" }
        return done
    }

    /// What the week means, when there's something to say: what's left with nothing planned, or when it's paused.
    private var aside: String? {
        if let paused = practice.paused {
            return paused.resumesOn.map { "Paused until \(CalendarDay.relativeLabel($0, today: detail.today)). These weeks don’t count." }
                ?? "Paused until you resume it. These weeks don’t count."
        }
        let unplanned = practice.left - practice.week.planned
        guard unplanned > 0 else { return nil }
        let daysLeft = CalendarDay.daysUntil(CalendarDay.addDays(practice.week.start, 7), today: detail.today)
        return "\(unplanned) to go with nothing planned, and \(daysLeft) \(daysLeft == 1 ? "day" : "days") left. Any days count; whatever doesn’t happen passes on Sunday."
    }
}

/// One day of the week: its date, and its sessions as a single mark.
private struct DayCell: View {
    let day: String
    let today: String
    let sessions: [PracticeSession]
    let color: String

    private var isToday: Bool { day == today }
    private var done: [PracticeSession] { sessions.filter { $0.state == .done } }
    private var planned: [PracticeSession] { sessions.filter { $0.state == .planned } }
    private var missed: [PracticeSession] { sessions.filter { $0.state == .missed || $0.state == .short || $0.state == .lapsed } }

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .appText(.xs, isToday ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(isToday ? Theme.foreground : Theme.muted)
            mark
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .overlay {
                    if isToday { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground(0.3)) }
                }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Mon 23".
    private var label: String {
        let weekday = CalendarDay.date(day).map {
            $0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated))
        } ?? ""
        return "\(weekday) \(Int(day.suffix(2)) ?? 0)"
    }

    @ViewBuilder private var mark: some View {
        if !done.isEmpty {
            VStack(spacing: 4) {
                Circle().fill(GoalPalette.color(color)).frame(width: 20, height: 20)
                    .overlay(Icon.tickBold.image(size: 12).foregroundStyle(.white))
                Text(done.count > 1 ? "\(done.count) done" : caption(done[0])).font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.foreground(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 12))
        } else if !planned.isEmpty {
            VStack(spacing: 4) {
                Circle().strokeBorder(GoalPalette.color(color), lineWidth: 1.5).frame(width: 20, height: 20)
                Text(planned.count > 1 ? "\(planned.count) planned" : caption(planned[0])).font(.app(10.5)).monospacedDigit().foregroundStyle(Theme.foreground(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GoalPalette.color(color).opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: planned[0].source == .day ? [4, 3] : [])))
        } else if let first = missed.first {
            VStack(spacing: 4) {
                Circle().strokeBorder(Theme.foreground(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 20, height: 20)
                Text(first.state == .short ? "Too short" : "Didn’t happen").font(.app(10.5)).strikethrough().foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.foreground(0.04), in: .rect(cornerRadius: 12))
        } else if day < today {
            RoundedRectangle(cornerRadius: 12).fill(Theme.foreground(0.025))
        } else {
            RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// "30 min" for a block, "Logged" for one done off the calendar, "Any time" for a day with no time yet, or the
    /// block's start for one still to come.
    private func caption(_ session: PracticeSession) -> String {
        switch (session.source, session.state) {
        case (.day, .done): return "Logged"
        case (.day, _): return "Any time"
        case (.block, .planned):
            return session.startsAt.map { $0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).hour().minute()) } ?? ""
        case (.block, _):
            guard let start = session.startsAt, let end = session.endsAt else { return "" }
            return TaskItem.minutesLabel(Int(end.timeIntervalSince(start) / 60))
        }
    }
}

// MARK: - How it's holding

/// In the place a project's read takes: the status (or Paused, or none yet), the count as its headline, a line on
/// what it means, and the last 8 weeks as columns of pips with this week ringed. No AI: it's the count.
private struct HoldingCard: View {
    let detail: GoalDetail
    let practice: Practice

    var body: some View {
        Card {
            pill.padding(.bottom, 12)
            Text(headline).appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Text(body_)
                .font(.app(15.2))
                .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
            WeekColumns(detail: detail, practice: practice).padding(.top, 20)
        }
    }

    @ViewBuilder private var pill: some View {
        if practice.paused != nil {
            HStack(spacing: 6) {
                Icon.pause.image(size: 11)
                Text("Paused").appText(.xs, .medium)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.foreground(0.06), in: .capsule)
        } else if let status = practice.status {
            StatusPill(status: status.status, basis: .week, help: "Counted from its last \(status.weeks) full \(status.weeks == 1 ? "week" : "weeks")")
        } else {
            HStack(spacing: 6) {
                Circle().strokeBorder(Theme.muted, lineWidth: 1).frame(width: 6, height: 6)
                Text("No status yet").appText(.xs, .medium)
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.foreground(0.06), in: .capsule)
        }
    }

    private var headline: String {
        if let paused = practice.paused {
            return paused.resumesOn.map { "Paused until \(CalendarDay.format($0, today: detail.today))" } ?? "Paused until you resume it"
        }
        return practice.status?.reason ?? "No full week yet"
    }

    private var body_: String {
        if practice.paused != nil {
            return "Its weeks don’t count toward its status or its area’s while it’s paused, and nothing asks you to plan sessions."
        }
        guard let status = practice.status else {
            return "Its status starts once it’s had a full week. This week counts once it’s over."
        }
        // The weeks the status looked at: the latest that weren't paused and came after it was made.
        let counted = (detail.practice?.weeks ?? []).filter { !$0.paused && !$0.beforeStart }.suffix(status.weeks)
        let short = counted.filter { $0.done < practice.perWeek }.count
        let lead = short == 0
            ? (status.weeks == 1 ? "Last week had all its sessions." : "Each of the last \(status.weeks) weeks had all its sessions.")
            : "\(short == status.weeks ? "Every one" : "\(short)") of the last \(status.weeks) \(status.weeks == 1 ? "week" : "weeks") fell short of \(practice.perWeek)."
        return "\(lead) This week counts once it’s over."
    }
}

/// The last 8 full weeks and this one, a column of pips each, the weeks the status counts shaded.
private struct WeekColumns: View {
    let detail: GoalDetail
    let practice: Practice

    var body: some View {
        let weeks = detail.practice?.weeks ?? []
        let counted = Set(weeks.filter { !$0.paused && !$0.beforeStart }.suffix(practice.status?.weeks ?? 0).map(\.start))
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last \(weeks.count) weeks")
                Spacer()
                if !counted.isEmpty { Text(counted.count == 1 ? "Status counts the shaded week" : "Status counts the \(counted.count) shaded weeks") }
            }
            .font(.app(11)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(weeks, id: \.start) { week in
                    column(pips: week.beforeStart ? nil : pips(done: week.done, planned: 0),
                           label: CalendarDay.format(week.start, today: detail.today),
                           shaded: counted.contains(week.start), paused: week.paused)
                }
                column(pips: practice.paused == nil ? practice.pips : nil, label: "This week", isCurrent: true, paused: practice.paused != nil)
            }
        }
    }

    private func pips(done: Int, planned: Int) -> [Practice.Pip] {
        (0..<max(practice.perWeek, done)).map { $0 < done ? .done : .empty }
    }

    private func column(pips: [Practice.Pip]?, label: String, shaded: Bool = false, isCurrent: Bool = false, paused: Bool = false) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 4) {
                ForEach(Array((pips ?? []).enumerated().reversed()), id: \.offset) { _, pip in
                    switch pip {
                    case .done: Circle().fill(GoalPalette.color(detail.goal.color)).frame(width: 10, height: 10)
                    case .planned: Circle().strokeBorder(GoalPalette.color(detail.goal.color), lineWidth: 1.5).frame(width: 10, height: 10)
                    case .empty: Circle().fill(Theme.foreground(0.1)).frame(width: 10, height: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(max(practice.perWeek, 1)) * 14 + 12, alignment: .bottom)
            .padding(.vertical, 6)
            .background {
                if paused {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.foreground(0.05))
                } else if shaded {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.foreground(0.035))
                }
            }
            .overlay {
                if isCurrent { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground(0.3)) }
            }
            Text(paused ? "Paused" : label)
                .font(.app(10, isCurrent ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Theme.foreground : Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Sessions

/// What's counted, latest first, and what didn't: blocks from the calendar and ones logged. No tasks: a practice is
/// how often, not what's left.
private struct SessionsList: View {
    let detail: GoalDetail

    private var past: [PracticeSession] {
        (detail.practice?.sessions ?? []).filter { $0.state != .planned }.reversed().prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sessions").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Text("What’s counted, latest first.").appText(.sm).foregroundStyle(Theme.muted)
            if past.isEmpty {
                Text("Nothing yet. Sessions for it on the calendar count once they’ve happened, and Log one counts one that wasn’t.")
                    .appText(.sm).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .padding(.top, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(past.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        SessionRow(session: session, title: detail.goal.title, color: detail.goal.color, today: detail.today)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
                .padding(.top, 16)
            }
        }
    }
}

private struct SessionRow: View {
    let session: PracticeSession
    let title: String
    let color: String
    let today: String

    private var counted: Bool { session.state == .done }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if counted {
                    Circle().fill(GoalPalette.color(color))
                        .overlay((session.source == .day ? Icon.tickBold : Icon.target).image(size: 13).foregroundStyle(.white))
                } else {
                    Circle().strokeBorder(Theme.foreground(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? title)
                    .appText(.sm, .semibold, tracking: -0.01)
                    .foregroundStyle(counted ? Theme.foreground : Theme.muted)
                    .strikethrough(!counted)
                Text(detailLine).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                (session.source == .day ? Icon.edit : Icon.calendarSmall).image(size: 12)
                Text(source)
            }
            .appText(.xs)
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// "Mon, Nov 23 · 30 min", "Sat, Nov 21 · Logged", "Tue, Nov 24 · Didn't happen".
    private var detailLine: String {
        let day = CalendarDay.date(session.day).map {
            $0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day())
        } ?? session.day
        let what: String = switch session.state {
        case .missed: "Didn’t happen"
        case .short: "Too short to count"
        case .lapsed: "Its day went by"
        default:
            if session.source == .day { "Logged" } else if let start = session.startsAt, let end = session.endsAt {
                TaskItem.minutesLabel(Int(end.timeIntervalSince(start) / 60))
            } else { "" }
        }
        return "\(day) · \(what)"
    }

    private var source: String { session.source == .day ? "You logged it" : "From the calendar" }
}

#Preview("Practice") {
    PracticePage(detail: Fixtures.practiceDetail)
        .background(Theme.background)
        .frame(width: 1100, height: 1200)
}
