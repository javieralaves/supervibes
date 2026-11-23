import SwiftUI

/// The home page, matching src/app/(app)/page.tsx and goals-board.tsx: a greeting, then the goals
/// as cards, each with its week (this week's objective, and its tasks against its session time),
/// its status and the last weeks, and a button for a new goal.
struct GoalsHome: View {
    let firstName: String
    let goals: [Goal]
    /// Today, "YYYY-MM-DD"; the trails end on it.
    let today: String
    /// Each goal's week, by goal id. A goal without one (or a page without any) shows no week.
    var weeks: [String: GoalWeek] = [:]
    var max = 12
    var error: String?
    var onOpen: (Goal) -> Void = { _ in }
    var onNew: (GoalInput) -> Void = { _ in }
    /// What a goal card's right-click menu offers besides opening it.
    var actions = GoalCardActions()

    @State private var width: CGFloat = 1024

    /// The web's grid: one column, two from 640pt (`sm`), three from 1024pt (`lg`).
    private var columns: Int { width >= 1024 ? 3 : width >= 640 ? 2 : 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // `text-5xl leading-[1.05] tracking-[-0.035em]`: the lines sit tighter than the font's own.
                VStack(alignment: .leading, spacing: -48 * 0.15) {
                    Text("Hey \(firstName),")
                    Text("good to see you.").foregroundStyle(Theme.muted)
                }
                .font(.app(48, .semibold))
                .tracking(-0.035 * 48)
                .foregroundStyle(Theme.foreground)

                Text("Here’s what you’re working toward.")
                    .appText(.base)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 20)

                board.padding(.top, 48)
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 80)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        // The page runs up under the hidden title bar, where macOS 26 otherwise draws its hard scroll edge:
        // a frosted strip with a line under it, across the top of the app's window. Soft just fades.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
            Text("Goals").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Spacer()
            if !goals.isEmpty {
                Text(countLine).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .padding(.bottom, 16)

        if let error {
            Banner(text: error, tone: .error).padding(.bottom, 16)
        }

        if goals.isEmpty {
            EmptyGoals(onNew: onNew)
        } else {
            let cells: [Cell] = goals.map { .goal($0) } + (goals.count < max ? [.new] : [])
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(stride(from: 0, to: cells.count, by: columns)), id: \.self) { start in
                    GridRow(alignment: .top) {
                        ForEach(start..<min(start + columns, cells.count), id: \.self) { index in
                            cell(cells[index])
                        }
                        // Keep a short last row's cards the same width as the rest.
                        ForEach(0..<(start + columns - min(start + columns, cells.count)), id: \.self) { _ in
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
        }
    }

    /// "5 h 15 min of 35 h planned this week · 7 of 12": the week across goals with session time,
    /// beside the count; just the count when none has any.
    private var countLine: String {
        let count = "\(goals.count) of \(max)"
        let withTime = goals.compactMap { weeks[$0.id] }.filter { $0.sessionMinutes > 0 }
        guard !withTime.isEmpty else { return count }
        let planned = withTime.reduce(0) { $0 + $1.plannedMinutes }
        let sessions = withTime.reduce(0) { $0 + $1.sessionMinutes }
        return "\(BoardDuration.text(planned)) of \(BoardDuration.text(sessions)) planned this week · \(count)"
    }

    private enum Cell { case goal(Goal), new }

    @ViewBuilder private func cell(_ cell: Cell) -> some View {
        switch cell {
        case .goal(let goal):
            GoalCard(goal: goal, week: weeks[goal.id], today: today, onSetObjective: actions.setObjective) { onOpen(goal) }
                .contextPanel(owner: GoalCard.menuOwner(goal), isEnabled: !goal.isPending) {
                    GoalCardMenu(goal: goal, actions: actions) { onOpen(goal) }
                }
        case .new:
            NewGoalButton { onNew(GoalInput()) }
        }
    }
}

/// `rounded-2xl border bg-card p-5`, hover `border-line-strong`: who it is at the top, how it's going
/// pinned to the bottom, so footers line up across a row.
/// A goal card's menu, beyond opening it: each nil leaves its row out.
struct GoalCardActions {
    /// Opens its planning board.
    var plan: ((Goal) -> Void)?
    /// Opens it with the cursor in this week's objective, from the card's "Set this week's objective".
    var setObjective: ((Goal) -> Void)?
    /// Opens it and starts a new read.
    var updateStatus: ((Goal) -> Void)?
    var edit: ((Goal) -> Void)?
    /// Asks first.
    var delete: ((Goal) -> Void)?
}

/// What right-clicking a goal card offers: the goal page's own ⋯ menu, plus opening it or its board.
struct GoalCardMenu: View {
    let goal: Goal
    let actions: GoalCardActions
    let onOpen: () -> Void

    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel(width: 200) {
            MenuItem(icon: .view, title: "Open") { run(onOpen) }
            if let plan = actions.plan {
                MenuItem(icon: .calendarSmall, title: "Plan tasks") { run { plan(goal) } }
            }
            if let updateStatus = actions.updateStatus {
                MenuItem(icon: .refresh, title: "Update status") { run { updateStatus(goal) } }
            }
            if let edit = actions.edit {
                MenuSeparator()
                MenuItem(icon: .edit, title: "Edit goal") { run { edit(goal) } }
            }
            if let delete = actions.delete {
                MenuItem(icon: .delete, title: "Delete goal", isDestructive: true) { run { delete(goal) } }
            }
        }
    }

    private func run(_ action: () -> Void) {
        overlays?.dismiss()
        action()
    }
}

private struct GoalCard: View {
    let goal: Goal
    /// Its week; nil shows none.
    var week: GoalWeek?
    let today: String
    var onSetObjective: ((Goal) -> Void)?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.overlays) private var overlays

    static func menuOwner(_ goal: Goal) -> String { "goal-card#\(goal.id)" }

    /// Hovered, or its menu is open.
    private var isEngaged: Bool { isHovered || overlays?.presented?.owner == Self.menuOwner(goal) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.title)
                            .font(.app(15.2, .semibold))
                            .tracking(-0.01 * 15.2)
                            .lineSpacing(15.2 * 0.375 - 15.2 * 0.2)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let week {
                            WeekObjectiveLine(week: week, onSet: onSetObjective.map { set in { set(goal) } })
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 20)
                }
                .overlay(alignment: .topTrailing) {
                    Icon.arrowRight.image(size: 16).foregroundStyle(Theme.muted)
                        .opacity(isEngaged ? 1 : 0)
                        .offset(x: 4)
                }

                Spacer(minLength: 20)

                if let week {
                    WeekTimeLine(week: week, color: goal.color).padding(.bottom, 10)
                }

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let latest = goal.latest, let status = latest.status, let basis = latest.basis {
                        StatusText(status: status, basis: basis)
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    if let target = goal.targetDate {
                        let days = CalendarDay.daysUntil(target, today: today)
                        Text("\(CalendarDay.format(target, today: today)) · \(CalendarDay.shortRelative(days))")
                            .appText(.xs).monospacedDigit()
                            .foregroundStyle(days < 0 ? Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24)) : Theme.muted)
                            .help("Target \(CalendarDay.format(target, today: today))")
                    }
                }
                TrajectoryStrip(days: goal.trajectory).padding(.top, 8)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isEngaged ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .inactive(goal.isPending)
        .opacity(goal.isPending ? 0.6 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isEngaged)
    }
}

/// Under a card's title: this week's objective with a flag, or, for a goal with session time this
/// week and no objective yet, a dashed "Set this week's objective" that opens the goal to write one.
private struct WeekObjectiveLine: View {
    let week: GoalWeek
    let onSet: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        if let objective = week.objective, !objective.isEmpty {
            HStack(spacing: 6) {
                Icon.flag.image(size: 12)
                Text(objective).font(.app(13)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(Theme.muted)
            .help(objective)
        } else if week.sessionMinutes > 0, let onSet {
            Button(action: onSet) {
                HStack(spacing: 4) {
                    Icon.add.image(size: 10)
                    Text("Set this week’s objective").font(.app(11, .medium))
                }
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(isHovered ? Theme.wash : .clear, in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .padding(.top, 2)
        }
    }
}

/// Above a card's status: its week's time. A ring in the goal's colour and what's planned against
/// the session time, with what's free or over; or the session time with nothing planned yet; or,
/// with no session time, the reserved time, or that there's none.
private struct WeekTimeLine: View {
    let week: GoalWeek
    let color: String

    var body: some View {
        HStack(spacing: 6) {
            CapacityRing(planned: week.sessionMinutes > 0 ? week.plannedMinutes : 0, protected: week.sessionMinutes, color: color, size: 14)
            if week.sessionMinutes > 0, week.plannedMinutes > 0 {
                Text("\(Text(BoardDuration.text(week.plannedMinutes)).foregroundStyle(week.remaining < 0 ? Theme.amber : Theme.foreground)) / \(BoardDuration.text(week.sessionMinutes))")
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Text(week.remaining < 0 ? "\(BoardDuration.text(-week.remaining)) over"
                     : week.remaining == 0 ? "Just fits" : "\(BoardDuration.text(week.remaining)) free")
                    .foregroundStyle(week.remaining < 0 ? Theme.amber : Theme.muted)
            } else {
                Text(emptyLine).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
        }
        .appText(.xs)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var emptyLine: String {
        if week.sessionMinutes > 0 { return "\(BoardDuration.text(week.sessionMinutes)) this week, nothing planned" }
        if week.reservedMinutes > 0 { return "\(BoardDuration.text(week.reservedMinutes)) reserved this week" }
        if week.plannedMinutes > 0 { return "\(BoardDuration.text(week.plannedMinutes)) planned, no time this week" }
        return "No time this week"
    }
}

/// `min-h-[84px] rounded-2xl border border-dashed border-foreground/15 text-sm font-medium text-muted`
private struct NewGoalButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon.add.image(size: 18)
                Text("New goal").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 84)
            .background(isHovered ? Theme.card : .clear, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.foreground(isHovered ? 0.3 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// For someone with no goals yet: a prompt, two suggestions, and New goal.
private struct EmptyGoals: View {
    let onNew: (GoalInput) -> Void

    private static let suggestions = [
        GoalInput(title: "Turn Supervibes into a world-class experience", icon: "SparklesIcon", color: "violet"),
        GoalInput(title: "Create political program as side project", icon: "Megaphone01Icon", color: "coral"),
    ]

    var body: some View {
        Card(padding: 32) {
            Text("What are you working toward?").appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Text("Add a handful of goals, each with its own icon and color. Start from scratch or pick one below.")
                .appText(.sm).foregroundStyle(Theme.muted)
                .frame(maxWidth: 448, alignment: .leading)
                .padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.title) { suggestion in
                    SuggestionRow(input: suggestion) { onNew(suggestion) }
                }
            }
            .padding(.top, 24)
            PrimaryButton(title: "New goal", icon: .add) { onNew(GoalInput()) }
                .padding(.top, 24)
        }
    }

    private struct SuggestionRow: View {
        let input: GoalInput
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    GoalBadge(icon: input.icon, color: input.color)
                    Text(input.title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                    Spacer()
                    Icon.add.image(size: 16).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .padding(.trailing, 4)
                .background(Theme.background.opacity(isHovered ? 1 : 0.6), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

#Preview("Goals") {
    GoalsHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
              actions: GoalCardActions(setObjective: { _ in }))
        .background(Theme.background)
        .frame(width: 1180, height: 900)
}

#Preview("No goals yet") {
    GoalsHome(firstName: "Javier", goals: [], today: "2026-11-18")
        .background(Theme.background)
        .frame(width: 900, height: 760)
}
