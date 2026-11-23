import SwiftUI

/*
 * Clicking a day's ring on the planning board when it's over: the ring's detail, then two ways to
 * make the day fit. Move tasks out comes first (keep the time, change the scope): the moves that
 * land where there's room, each ticked, with how the day would stand. Protect more time keeps the
 * tasks: free time that day, then time another goal has to spare. Designed in supervibes-design
 * ("Planning, consolidated", 3 · When a ring goes over). The rules are in Fit.swift.
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
}

struct MakeItFitPanel: View {
    enum Mode: Hashable { case move, protect }

    /// "Tomorrow · Thu, Nov 19 · Build Supervibes".
    let label: String
    /// "Tomorrow", "Fri".
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
    /// Moves left out, by task id.
    @State private var unticked: Set<String> = []
    @State private var chosen = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.overlays) private var overlays

    init(
        label: String, dayName: String, capacity: Capacity, color: String, moves: [Fit.Move], sources: [FitSource],
        today: String, clock: Clock, initialMode: Mode = .move,
        onMove: @escaping ([Fit.Move]) -> Void, onProtect: @escaping (FitSource) -> Void
    ) {
        self.label = label
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
    }

    private var over: Int { max(0, capacity.planned - capacity.protected) }
    private var picked: [Fit.Move] { moves.filter { !unticked.contains($0.task.id) } }
    private var source: FitSource? { sources.indices.contains(chosen) ? sources[chosen] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).appText(.xs).foregroundStyle(Theme.muted).lineLimit(2)
            HStack(spacing: 14) {
                CapacityRing(planned: capacity.planned, protected: capacity.protected, color: color, size: 52, stroke: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Totals(planned: capacity.planned, protected: capacity.protected, size: 18)
                    Text(capacity.protected == 0 ? "No time protected" : "\(BoardDuration.text(over)) over")
                        .appText(.xs).foregroundStyle(Theme.amber)
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
        .frame(width: 372, alignment: .leading)
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
                    MoveRow(move: move, destination: destinationName(move.to), after: after(move), isOn: !unticked.contains(move.task.id)) {
                        if unticked.contains(move.task.id) { unticked.remove(move.task.id) } else { unticked.insert(move.task.id) }
                    }
                }
            }
            .padding(.top, 8)
            footer(planned: capacity.planned - picked.reduce(0) { $0 + $1.task.minutes }, protected: capacity.protected) {
                SmallButton(title: picked.count == 1 ? "Move 1 task" : "Move \(picked.count) tasks", isEnabled: !picked.isEmpty) {
                    overlays?.dismiss()
                    onMove(picked)
                }
            }
        }
    }

    private func destinationName(_ destination: Fit.Destination) -> String {
        switch destination {
        case .day(let day): CalendarDay.relativeLabel(day, today: today)
        case .thisWeek: "This week"
        case .nextWeek: "Next week"
        }
    }

    /// How the place a task goes stands once it's there.
    private func after(_ move: Fit.Move) -> String {
        switch move.to {
        case .day: move.roomAfter == 0 ? "fills its \(BoardDuration.text(move.protected))" : "\(BoardDuration.text(move.roomAfter)) left there"
        case .nextWeek: "\(BoardDuration.text(move.roomAfter)) free"
        case .thisWeek: "no day yet"
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
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    SourceRow(source: source, clock: clock, color: color, isOn: chosen == index) { chosen = index }
                }
            }
            .padding(.top, 8)
            if let source {
                footer(planned: capacity.planned, protected: capacity.protected + source.slot.minutes) {
                    SmallButton(title: "\(source.give == nil ? "Protect" : "Take") \(BoardDuration.text(source.slot.minutes))", isEnabled: true) {
                        overlays?.dismiss()
                        onProtect(source)
                    }
                }
            }
        }
    }

    /// "Tomorrow after: 1 h 15 min / 2 h", and the action.
    private func footer(planned: Int, protected: Int, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 10)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("\(dayName) after:").foregroundStyle(Theme.muted)
                    Totals(planned: planned, protected: protected, size: 12)
                }
                .appText(.xs)
                .monospacedDigit()
                Spacer(minLength: 8)
                action()
            }
        }
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
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Theme.lineStrong : .clear))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A suggested move: a tick, the task, where it goes and how that place stands after.
private struct MoveRow: View {
    let move: Fit.Move
    let destination: String
    let after: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? Theme.foreground : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isOn ? .clear : Theme.lineStrong, lineWidth: 1.5))
                    .overlay { if isOn { Icon.tickBold.image(size: 11).foregroundStyle(Theme.background) } }
                    .frame(width: 16, height: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(move.task.title).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(BoardDuration.text(move.task.minutes))
                        Icon.arrowForward.image(size: 11)
                        Text(destination).fontWeight(.medium).foregroundStyle(Theme.foreground(0.8))
                        Text("· \(after)")
                    }
                    .appText(.xs)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Time to protect: free, or another goal's to spare. The chosen one sits on a wash.
private struct SourceRow: View {
    let source: FitSource
    let clock: Clock
    /// The goal getting the time.
    let color: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(GoalPalette.color(source.goalColor ?? color)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(13)).foregroundStyle(isOn ? Theme.foreground : Theme.muted).lineLimit(1).truncationMode(.tail)
                    if let detail { Text(detail).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(BoardDuration.text(source.slot.minutes)).appText(.xs).foregroundStyle(Theme.muted)
            }
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isOn ? Theme.wash : isHovered ? Theme.wash.opacity(0.5) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The time first, so a long goal name never hides it.
    private var title: String {
        let range = clock.range(source.slot.start, source.slot.end)
        return source.give == nil ? "Free, \(range)" : range
    }

    private var detail: String? {
        source.goalTitle.map { "Spare from \($0)" }
    }
}

/// The panel's action: `h-7 rounded-lg bg-foreground px-3 text-xs font-medium text-background`.
private struct SmallButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.xs, .medium)
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.foreground.opacity(isEnabled ? (isHovered ? 0.85 : 1) : 0.3), in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#Preview("Make it fit") {
    let data = Fixtures.board
    let goal = data.goal("1")!
    let now = Fixtures.referenceNow
    let day = "2026-11-18"
    let capacity = Capacity.day(day, open: goal.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }, blocks: goal.protectedBlocks, now: now)
    let sources = Fit.freeSlots(for: goal, day: day, in: data, now: now).map { FitSource(give: nil, goalTitle: nil, goalColor: nil, slot: $0) }
        + Fit.gives(to: goal, day: day, in: data, now: now).map { FitSource(give: $0, goalTitle: data.goal($0.fromGoal)?.title, goalColor: data.goal($0.fromGoal)?.color, slot: $0.slot) }
    return MakeItFitPanel(
        label: "Today · Wed, Nov 18", dayName: "Today", capacity: capacity, color: goal.color,
        moves: Fit.moves(goal, day: day, today: data.today, now: now), sources: sources,
        today: data.today, clock: .device, onMove: { _ in }, onProtect: { _ in }
    )
    .padding(24)
    .background(Theme.background)
}
