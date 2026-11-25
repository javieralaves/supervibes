import SwiftUI

/*
 * Clicking a goal's ring for a day that's over, on the planning board or the Day view's strip: the
 * ring's detail, then two ways to make the day fit. Move tasks out comes first (keep the time, change
 * the scope): each move that lands where there's room, with its own Apply. Protect more time keeps
 * the tasks: free time that day, then time another goal has to spare, each with its own Apply. An
 * applied suggestion says so, and the ring and totals above count it straight away. Designed in
 * supervibes-design ("Planning, consolidated", 3, reworked in "The day, by goal"). The rules are in
 * Fit.swift.
 */

/// What the panel's choices do.
struct BoardFitActions {
    /// Plans these tasks where they're going, for the goal with this id.
    var move: ([Fit.Move], String) -> Void = { _, _ in }
    /// Protects this time for the goal.
    var protect: (Fit.Slot, String) -> Void = { _, _ in }
    /// Gives the end of another goal's session to the goal.
    var give: (Fit.Give, String) -> Void = { _, _ in }
}

/// A session time can come from: free, or another goal's.
struct FitSource: Hashable {
    /// The goal giving it, with its title and colour; nil for free time.
    let give: Fit.Give?
    let goalTitle: String?
    let goalColor: String?
    let slot: Fit.Slot

    var id: String { "\(give?.blockId ?? "free")@\(slot.start.timeIntervalSince1970)" }
}

struct MakeItFitPanel: View {
    enum Mode: Hashable { case move, protect }

    /// The goal's icon, before the day.
    let icon: String
    /// "Today", "Tomorrow", "Fri".
    let dayName: String
    let capacity: Capacity
    let color: String
    let moves: [Fit.Move]
    let sources: [FitSource]
    let today: String
    let clock: Clock
    var initialMode: Mode = .move
    let onMove: ([Fit.Move]) -> Void
    let onProtect: (FitSource) -> Void

    @State private var mode: Mode
    /// Suggestions applied while the panel's open: moves by task id, sources by their id.
    @State private var applied: Set<String>
    @Environment(\.colorScheme) private var colorScheme

    init(
        icon: String, dayName: String, capacity: Capacity, color: String, moves: [Fit.Move], sources: [FitSource],
        today: String, clock: Clock, initialMode: Mode = .move, applied: Set<String> = [],
        onMove: @escaping ([Fit.Move]) -> Void, onProtect: @escaping (FitSource) -> Void
    ) {
        self.icon = icon
        self.dayName = dayName
        self.capacity = capacity
        self.color = color
        self.moves = moves
        self.sources = sources
        self.today = today
        self.clock = clock
        self.initialMode = initialMode
        self.onMove = onMove
        self.onProtect = onProtect
        _mode = State(initialValue: initialMode)
        _applied = State(initialValue: applied)
    }

    /// The day as it stands with what's been applied here.
    private var planned: Int { capacity.planned - moves.filter { applied.contains($0.task.id) }.reduce(0) { $0 + $1.task.minutes } }
    private var protected: Int { capacity.protected + sources.filter { applied.contains($0.id) }.reduce(0) { $0 + $1.slot.minutes } }
    private var over: Int { max(0, planned - protected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                GoalIconImage(name: icon, size: 14).foregroundStyle(GoalPalette.color(color))
                Text(dayName).appText(.xs).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                CapacityRing(planned: planned, protected: protected, color: color, size: 52, stroke: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Totals(planned: planned, protected: protected, size: 18)
                    Text(protected == 0 ? "No time protected" : over > 0 ? "\(BoardDuration.text(over)) over" : "Fits")
                        .appText(.xs).foregroundStyle(over > 0 || protected == 0 ? Theme.amber : Theme.muted)
                }
            }
            .monospacedDigit()
            .padding(.top, 10)

            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 10)
            Text("Make it fit").appText(.xs, .medium).foregroundStyle(Theme.muted).padding(.bottom, 8)
            HStack(spacing: 4) {
                ModeChoice(title: "Move tasks out", detail: capacity.protected > 0 ? "Keep the \(BoardDuration.text(capacity.protected))" : "Keep the day clear", isOn: mode == .move) { mode = .move }
                ModeChoice(title: "Protect more time", detail: "Keep the tasks", isOn: mode == .protect) { mode = .protect }
            }

            switch mode {
            case .move: moveOut
            case .protect: protectMore
            }
        }
        .padding(12)
        .frame(width: 368, alignment: .leading)
        .background {
            let isDark = colorScheme == .dark
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color(nsColor: .rgb(0x1c1e22)) : Theme.card)
                .shadow(color: .black.opacity(isDark ? 0 : 0.06), radius: 3, y: 2)
                .shadow(color: .black.opacity(isDark ? 0.7 : 0.18), radius: isDark ? 20 : 16, y: isDark ? 16 : 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colorScheme == .dark ? Theme.lineStrong : Theme.cardBorder))
    }

    // MARK: Move tasks out

    @ViewBuilder private var moveOut: some View {
        if moves.isEmpty {
            Text("Nothing on \(dayName.lowercasedIfRelative) has a place with room for it this week or next.")
                .font(.app(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(moves, id: \.task.id) { move in
                    MoveRow(move: move, destination: destinationName(move.to), isApplied: applied.contains(move.task.id)) {
                        applied.insert(move.task.id)
                        onMove([move])
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func destinationName(_ destination: Fit.Destination) -> String {
        switch destination {
        case .day(let day): CalendarDay.relativeLabel(day, today: today)
        case .thisWeek: "This week"
        case .nextWeek: "Next week"
        }
    }

    // MARK: Protect more time

    @ViewBuilder private var protectMore: some View {
        if sources.isEmpty {
            Text("No free time left on \(dayName.lowercasedIfRelative), and no other goal has time to spare.")
                .font(.app(13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sources, id: \.id) { source in
                    SourceRow(source: source, clock: clock, color: color, isApplied: applied.contains(source.id)) {
                        applied.insert(source.id)
                        onProtect(source)
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

extension MakeItFitPanel {
    /// The panel for `goal` on `day`, built from the board's data: its moves, free time that day and
    /// time other goals have to spare. The board and the Day view's strip open the same one.
    init(goal: BoardGoal, day: String, dayName: String, in data: BoardData, now: Date, clock: Clock,
         initialMode: Mode = .move, applied: Set<String> = [], actions: BoardFitActions) {
        let capacity = Capacity.day(day, open: goal.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }, blocks: goal.protectedBlocks, now: now)
        let free = Fit.freeSlots(for: goal, day: day, in: data, now: now).map { FitSource(give: nil, goalTitle: nil, goalColor: nil, slot: $0) }
        let given = Fit.gives(to: goal, day: day, in: data, now: now).compactMap { give in
            data.goal(give.fromGoal).map { FitSource(give: give, goalTitle: $0.title, goalColor: $0.color, slot: give.slot) }
        }
        self.init(
            icon: goal.icon, dayName: dayName, capacity: capacity, color: goal.color,
            moves: Fit.moves(goal, day: day, today: data.today, now: now), sources: free + given,
            today: data.today, clock: clock, initialMode: initialMode, applied: applied,
            onMove: { actions.move($0, goal.id) },
            onProtect: { source in
                if let give = source.give { actions.give(give, goal.id) } else { actions.protect(source.slot, goal.id) }
            }
        )
    }
}

private extension String {
    /// "Today" → "today", "Tomorrow" → "tomorrow"; weekdays keep their capital.
    var lowercasedIfRelative: String { self == "Today" || self == "Tomorrow" ? lowercased() : self }
}

/// "3 h 45 min / 2 h": the planned figure amber when over.
private struct Totals: View {
    let planned: Int
    let protected: Int
    let size: CGFloat

    var body: some View {
        let isOver = planned > protected
        Text("\(Text(BoardDuration.text(planned)).foregroundStyle(isOver ? Theme.amber : Theme.foreground)) / \(BoardDuration.text(protected))")
            .font(.app(size, size > 14 ? .semibold : .medium))
            .foregroundStyle(Theme.muted)
            .tracking(size > 14 ? -0.18 : 0)
    }
}

/// One of the two ways to make it fit.
private struct ModeChoice: View {
    let title: String
    let detail: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.app(13, .medium)).foregroundStyle(isOn ? Theme.foreground : Theme.muted)
                Text(detail).font(.app(11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Theme.foreground(0.07) : isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A suggested move: the task, its estimate and where it goes, and Apply; once applied, "Moved".
private struct MoveRow: View {
    let move: Fit.Move
    let destination: String
    let isApplied: Bool
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                // Long titles wrap rather than lose their end.
                Text(move.task.title).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(BoardDuration.text(move.task.minutes))
                    Icon.arrowForward.image(size: 11)
                    Text(destination).fontWeight(.medium).foregroundStyle(Theme.foreground(0.8))
                }
                .appText(.xs)
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            ApplyButton(isApplied: isApplied, appliedTitle: "Moved", action: apply)
        }
        .padding(.vertical, 6)
        .opacity(isApplied ? 0.6 : 1)
    }
}

/// Time to protect: free, or another goal's to spare, and Apply; once applied, "Protected".
private struct SourceRow: View {
    let source: FitSource
    let clock: Clock
    /// The goal getting the time.
    let color: String
    let isApplied: Bool
    let apply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(GoalPalette.color(source.goalColor ?? color)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(1).truncationMode(.tail)
                Text(detail).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            ApplyButton(isApplied: isApplied, appliedTitle: source.give == nil ? "Protected" : "Taken", action: apply)
        }
        .monospacedDigit()
        .padding(.vertical, 6)
        .opacity(isApplied ? 0.6 : 1)
    }

    /// The time first, so a long goal name never hides it.
    private var title: String {
        let range = clock.range(source.slot.start, source.slot.end)
        return source.give == nil ? "Free, \(range)" : range
    }

    private var detail: String {
        let minutes = BoardDuration.text(source.slot.minutes)
        return source.goalTitle.map { "\(minutes) spare from \($0)" } ?? minutes
    }
}

/// A suggestion's own action, secondary: `h-7 rounded-lg bg-card px-2.5 text-xs font-medium` with a
/// hairline, as the top bar's buttons. Once applied, what happened, muted, with a tick.
private struct ApplyButton: View {
    let isApplied: Bool
    let appliedTitle: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        if isApplied {
            HStack(spacing: 4) {
                Icon.tick.image(size: 12)
                Text(appliedTitle)
            }
            .appText(.xs, .medium)
            .foregroundStyle(Theme.muted)
            .frame(height: 28)
        } else {
            Button(action: action) {
                Text("Apply").appText(.xs, .medium)
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(isHovered ? Theme.wash : Theme.card)
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

// MARK: - Previews

#Preview("Make it fit") {
    let data = Fixtures.board
    return MakeItFitPanel(
        goal: data.goal("1")!, day: "2026-11-18", dayName: "Today", in: data, now: Fixtures.referenceNow, clock: .device,
        actions: BoardFitActions()
    )
    .padding(24)
    .background(Theme.background)
}
