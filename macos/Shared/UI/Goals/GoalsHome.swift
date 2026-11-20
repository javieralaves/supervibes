import SwiftUI

/// The home page, matching src/app/(app)/page.tsx and goals-board.tsx: a greeting, then the goals
/// as cards, each with its status and the last weeks, and a button for a new goal.
struct GoalsHome: View {
    let firstName: String
    let goals: [Goal]
    /// Today, "YYYY-MM-DD"; the trails end on it.
    let today: String
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
            Text("Goals").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Spacer()
            if !goals.isEmpty {
                Text("\(goals.count) of \(max)").appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
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

    private enum Cell { case goal(Goal), new }

    @ViewBuilder private func cell(_ cell: Cell) -> some View {
        switch cell {
        case .goal(let goal):
            GoalCard(goal: goal, today: today) { onOpen(goal) }
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
    let today: String
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
                    Text(goal.title)
                        .font(.app(15.2, .semibold))
                        .tracking(-0.01 * 15.2)
                        .lineSpacing(15.2 * 0.375 - 15.2 * 0.2)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                    Spacer(minLength: 20)
                }
                .overlay(alignment: .topTrailing) {
                    Icon.arrowRight.image(size: 16).foregroundStyle(Theme.muted)
                        .opacity(isEngaged ? 1 : 0)
                        .offset(x: 4)
                }

                Spacer(minLength: 20)

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
    GoalsHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18")
        .background(Theme.background)
        .frame(width: 1180, height: 900)
}

#Preview("No goals yet") {
    GoalsHome(firstName: "Javier", goals: [], today: "2026-11-18")
        .background(Theme.background)
        .frame(width: 900, height: 760)
}
