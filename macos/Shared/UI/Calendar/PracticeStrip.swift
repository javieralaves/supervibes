import SwiftUI

/*
 * Practices on the calendar that aren't blocks (the Unscheduled row of the Projects & practices page in
 * supervibes-design). A session planned for a day with no time sits on that day as a chip with a circle to tick it
 * off once its day has come. The Week row lists what's left of each practice this week that isn't on a day or a time:
 * a dot in its colour, its name and how many are left. Hovering one shows a tick to log one done today; clicking it
 * offers a day to plan one for. Giving one a time is drawing a block for it, as for any session.
 */

/// A practice's session planned for a day (or done on it), as a chip: a circle to tick it off, its practice's name,
/// and, on hover, a way to take it off the day.
struct PracticeDayChip: View {
    let session: CalendarPracticeSession
    let goal: CalendarGoal?
    /// Today, "YYYY-MM-DD": one still to come can't be ticked off yet.
    let today: String
    var actions: PracticeActions?
    var compact = false
    @State private var isHovered = false

    private var color: String { goal?.color ?? "slate" }
    private var canTick: Bool { actions != nil && !session.isPending && session.day <= today }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Button { actions?.setDone(session.id, !session.done) } label: {
                Group {
                    if session.done {
                        Circle().fill(GoalPalette.color(color))
                            .overlay(Icon.tickBold.image(size: compact ? 7 : 9).foregroundStyle(.white))
                    } else {
                        Circle().strokeBorder(GoalPalette.color(color), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 1.5]))
                    }
                }
                .frame(width: compact ? 11 : 14, height: compact ? 11 : 14)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!canTick)
            .help(session.done ? "Done. Click to put it back to planned." : canTick ? "Tick it off" : "Its day hasn’t come yet")
            .accessibilityLabel(session.done ? "Done" : "Tick off")

            Text(goal?.title ?? "Practice")
                .font(.app(compact ? 11 : 12, .medium))
                .foregroundStyle(session.done ? Theme.muted : Theme.foreground)
                .strikethrough(session.done, color: Theme.foreground(0.25))
                .lineLimit(1)
            if !compact, !session.done {
                Text("Any time").font(.app(11)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if isHovered, actions != nil, !session.isPending {
                Button { actions?.remove(session.id) } label: {
                    Icon.close.image(size: compact ? 9 : 11).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Take it off this day")
                .accessibilityLabel("Take it off this day")
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 18 : 24)
        .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: compact ? 4 : 6))
        .opacity(session.isPending ? 0.6 : 1)
        .onHover { isHovered = $0 }
    }
}

/// What's left of each practice this week that isn't on a day or a time, as quiet items after a "Week" label.
struct WeekPracticesRow: View {
    let left: [PracticeLeft]
    /// Today, "YYYY-MM-DD".
    let today: String
    var actions: PracticeActions?
    var openGoal: ((String) -> Void)?
    /// The label's column: the calendar's gutter.
    var gutter: CGFloat
    var labelSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("Week").font(.app(labelSize, .medium)).foregroundStyle(Theme.muted)
                .lineLimit(1)
                .frame(width: gutter - 8, alignment: .trailing)
                .padding(.trailing, 8)
            HStack(spacing: 2) {
                ForEach(left) { item in
                    PracticeLeftItem(item: item, today: today, actions: actions, openGoal: openGoal)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
    }
}

/// One practice in the Week row: a dot in its colour, its name and how many are left. Hover: a tick to log one done
/// today. Click: a day to plan one for, or the practice's page.
private struct PracticeLeftItem: View {
    let item: PracticeLeft
    let today: String
    var actions: PracticeActions?
    var openGoal: ((String) -> Void)?
    @State private var isHovered = false
    @State private var anchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    private var owner: String { "practice-left#\(item.goal.id)" }
    private var isOpen: Bool { overlays?.presented?.owner == owner }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: showMenu) {
                HStack(spacing: 6) {
                    Circle().fill(GoalPalette.color(item.goal.color)).frame(width: 6, height: 6)
                    Text(item.goal.title).font(.app(11, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text("\(item.left) left").font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Plan one for a day, or draw a block for it to give it a time")

            if (isHovered || isOpen), let actions {
                Button { actions.logToday(item.goal.id) } label: {
                    Icon.tick.image(size: 10).foregroundStyle(Theme.foreground)
                        .frame(width: 16, height: 16)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().strokeBorder(Theme.cardBorder))
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Did one today")
                .accessibilityLabel("Did one today")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(isHovered || isOpen ? Theme.foreground(0.06) : .clear, in: .rect(cornerRadius: 5))
        .onHover { isHovered = $0 }
        .modifier(AnchorReader(frame: $anchor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.goal.title), \(item.left) left this week")
    }

    /// The days left this week, today first.
    private var days: [String] {
        let end = CalendarDay.addDays(CalendarDay.weekStart(today), 7)
        return (0..<7).map { CalendarDay.addDays(today, $0) }.filter { $0 < end }
    }

    private func showMenu() {
        guard let overlays, actions != nil || openGoal != nil else { return }
        let goal = item.goal
        overlays.showMenu(anchor: anchor, owner: owner, alignLeading: true) {
            MenuPanel(width: 220) {
                if let actions {
                    MenuItem(icon: .tick, title: "Did one today") { overlays.dismiss(); actions.logToday(goal.id) }
                    MenuSeparator()
                    MenuLabel("Plan one for")
                    ForEach(days, id: \.self) { day in
                        MenuItem(icon: .calendarSmall, title: CalendarDay.relativeLabel(day, today: today)) {
                            overlays.dismiss()
                            actions.plan(goal.id, day)
                        }
                    }
                }
                if let openGoal {
                    MenuSeparator()
                    MenuItem(icon: .target, title: "Open practice") { overlays.dismiss(); openGoal(goal.id) }
                }
            }
        }
    }
}

/// The Day view's practices: the day's sessions planned with no time (or done), then, on a day of this week, what's
/// left of each practice. Under the Anytime strip, with "Practices" in the gutter.
struct DayPracticesBar: View {
    let sessions: [CalendarPracticeSession]
    let left: [PracticeLeft]
    let goals: [CalendarGoal]
    let today: String
    var actions: PracticeActions?
    var openGoal: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !sessions.isEmpty {
                HStack(alignment: .center, spacing: 0) {
                    Text("Practices").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                        .frame(width: DayGrid.gutter, alignment: .trailing)
                        .padding(.trailing, 8)
                    HStack(spacing: 6) {
                        ForEach(sessions) { session in
                            PracticeDayChip(session: session, goal: goals.first { $0.id == session.goalId }, today: today, actions: actions)
                                .fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 6)
            }
            if !left.isEmpty {
                WeekPracticesRow(left: left, today: today, actions: actions, openGoal: openGoal, gutter: DayGrid.gutter + 8, labelSize: 11)
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }
}
