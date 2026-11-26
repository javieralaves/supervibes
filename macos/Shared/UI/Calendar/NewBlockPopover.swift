import SwiftUI

/*
 * Sits next to time just drawn on the timeline, to say what it's for. The goal badge switches to a
 * goal list in place; the switch below picks a session, reserved time or a task. As a task, typing
 * suggests open tasks that don't have a time yet: ↑ ↓ move through them, Return or a click takes
 * one (and its goal). Return adds; Esc closes the suggestions, steps back from the goal list, or
 * cancels; a press elsewhere on the timeline cancels.
 */

struct NewBlockPopover: View {
    typealias Kind = BlockKind

    let goals: [CalendarGoal]
    /// Open tasks that could take this time: those without a time already.
    let tasks: [CalendarTask]
    let timeLabel: String
    let onAdd: (_ goalId: String, _ title: String?, _ kind: NewBlockKind) -> Void
    let onCancel: () -> Void

    /// Roughly how tall it is without suggestions, to decide whether it opens above or below.
    static let estimatedHeight: CGFloat = 200
    /// MAX_BLOCK_TITLE
    private static let maxTitle = 120
    private static let maxSuggestions = 5

    @State private var goalId: String
    @State private var title = ""
    @State private var kind: Kind
    /// The open task taken from the suggestions.
    @State private var pickedTaskId: String?
    @State private var highlighted: Int?
    /// Esc closed the suggestions; typing brings them back.
    @State private var hidesSuggestions = false
    @State private var showsGoals = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case title, goal }

    /// `kind` and `title` start it somewhere other than an empty session, for previews and tests.
    init(goals: [CalendarGoal], tasks: [CalendarTask], goalId: String, kind: Kind = .session, title: String = "", timeLabel: String,
         onAdd: @escaping (String, String?, NewBlockKind) -> Void, onCancel: @escaping () -> Void) {
        self.goals = goals
        self.tasks = tasks
        self.timeLabel = timeLabel
        self.onAdd = onAdd
        self.onCancel = onCancel
        _goalId = State(initialValue: goalId)
        _kind = State(initialValue: kind)
        _title = State(initialValue: title)
    }

    private var goal: CalendarGoal? { goals.first { $0.id == goalId } }
    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { goal != nil && (kind != .task || !trimmed.isEmpty) }

    /// Open tasks whose title holds what's typed: those starting with it first, then the chosen
    /// goal's, then in each goal's order.
    private var suggestions: [CalendarTask] {
        guard kind == .task, pickedTaskId == nil, !hidesSuggestions, !trimmed.isEmpty else { return [] }
        let query = trimmed
        let matches = tasks.enumerated().filter { $0.element.title.localizedStandardContains(query) }
        let ranked = matches.sorted { a, b in
            let rank = { (task: CalendarTask) in
                (Self.startsWith(task.title, query) ? 0 : 2) + (task.goalId == goalId ? 0 : 1)
            }
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }
        return ranked.prefix(Self.maxSuggestions).map(\.element)
    }

    private static func startsWith(_ text: String, _ prefix: String) -> Bool {
        text.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        Group {
            if showsGoals { goalList } else { main }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.card)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.04)), radius: 1, y: 1)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.18)), radius: 16, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
        .onEscape {
            if showsGoals {
                back(to: .goal)
            } else if !suggestions.isEmpty {
                hidesSuggestions = true
                highlighted = nil
            } else {
                onCancel()
            }
        }
        .onAppear { focus = .title }
    }

    // MARK: Main

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let goal {
                    GoalButton(goal: goal) { showsGoals = true }
                        .focused($focus, equals: .goal)
                } else {
                    Text("Add a project or practice first.").appText(.sm).foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeLabel).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    titleField
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)

            let suggestions = suggestions
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, task in
                        SuggestionRow(task: task, goal: goals.first { $0.id == task.goalId }, isHighlighted: index == highlighted) {
                            pick(task)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Open tasks")
            }

            HStack(spacing: 8) {
                KindSwitch(selection: $kind)
                Spacer(minLength: 0)
                AddButton(isEnabled: canAdd, action: add)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .onChange(of: kind) {
            highlighted = nil
            if kind != .task { pickedTaskId = nil }
            focus = .title
        }
    }

    private var titleField: some View {
        TextField("", text: $title)
            .textFieldStyle(.plain)
            .font(.app(16, .semibold))
            .tracking(-0.16)
            .foregroundStyle(Theme.foreground)
            .focused($focus, equals: .title)
            .placeholder(kind == .task ? "What you’ll do" : "Add a title", when: title.isEmpty, font: .app(16, .medium))
            .onSubmit(submit)
            .onChange(of: title) {
                if title.count > Self.maxTitle { title = String(title.prefix(Self.maxTitle)) }
                // Changing a taken task's title makes it a new one again.
                if let id = pickedTaskId, tasks.first(where: { $0.id == id })?.title != title { pickedTaskId = nil }
                hidesSuggestions = false
                highlighted = nil
            }
            .onKeyPress(.downArrow) { moveHighlight(1) }
            .onKeyPress(.upArrow) { moveHighlight(-1) }
            .accessibilityLabel("Title")
    }

    private func moveHighlight(_ by: Int) -> KeyPress.Result {
        let count = suggestions.count
        guard count > 0 else { return .ignored }
        highlighted = switch highlighted {
        case nil: by > 0 ? 0 : count - 1
        case let index?: (index + by + count) % count
        }
        return .handled
    }

    private func submit() {
        if let highlighted, suggestions.indices.contains(highlighted) {
            pick(suggestions[highlighted])
        } else {
            add()
        }
    }

    /// Take an open task: its title, and its goal.
    private func pick(_ task: CalendarTask) {
        title = task.title
        goalId = task.goalId
        // After the title's change, which would otherwise let it go.
        Task { @MainActor in
            pickedTaskId = task.id
            highlighted = nil
            focus = .title
        }
    }

    private func add() {
        guard canAdd else { return }
        let text = trimmed.isEmpty ? nil : trimmed
        switch kind {
        case .session: onAdd(goalId, text, .session)
        case .reserved: onAdd(goalId, text, .reserved)
        case .task:
            // A task typed out in full is that task, not a second one with the same title.
            let same = tasks.first { $0.goalId == goalId && $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            let id = pickedTaskId ?? same?.id
            onAdd(id.flatMap { id in tasks.first { $0.id == id }?.goalId } ?? goalId, text, .task(id: id))
        }
    }

    // MARK: Goals

    private var goalList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                BackButton { back(to: .goal) }
                Text("Project or practice").appText(.sm, .semibold).foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let sections = GoalSections(goals).sections
                    ForEach(sections, id: \.title) { section in
                        // Headings only once there's more than one kind to tell apart.
                        if sections.count > 1 {
                            Text(section.title).appText(.xs, .medium).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
                        }
                        ForEach(section.goals) { option in
                            GoalRow(goal: option, isSelected: option.id == goalId) {
                                if option.id != goalId { pickedTaskId = nil }
                                goalId = option.id
                                back(to: .title)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 256)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func back(to target: Focus) {
        showsGoals = false
        Task { @MainActor in focus = target }
    }
}

/// Session, reserved time or task, as icons in a `ToggleGroup`-style well.
private struct KindSwitch: View {
    @Binding var selection: NewBlockPopover.Kind

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NewBlockPopover.Kind.allCases, id: \.self) { kind in
                KindItem(kind: kind, isSelected: kind == selection) { selection = kind }
            }
        }
        .padding(3)
        .background(Theme.wash, in: .rect(cornerRadius: 11))
        .fixedSize()
    }

    private struct KindItem: View {
        let kind: NewBlockPopover.Kind
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                kind.icon.image(size: 18)
                    .foregroundStyle(isSelected || isHovered ? Theme.foreground : Theme.muted)
                    .frame(width: 34, height: 30)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.card)
                                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.08)), radius: 1, y: 1)
                        }
                    }
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { isHovered = $0 }
            .help(kind.longLabel)
            .accessibilityLabel(kind.longLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

/// Solid, with the Return key it answers to.
private struct AddButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Add").appText(.sm, .semibold)
                Icon.reopen.image(size: 12)
                    .frame(width: 20, height: 20)
                    .background(Theme.background.opacity(0.16), in: .rect(cornerRadius: 5))
            }
            .foregroundStyle(Theme.background)
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 32)
            .background(Theme.foreground, in: .rect(cornerRadius: 9))
            .opacity(isHovered && isEnabled ? 0.9 : 1)
            .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .compositingGroup()
        .opacity(isEnabled ? 1 : 0.3)
        .inactive(!isEnabled)
        .accessibilityLabel("Add")
    }
}

/// An open task to take: its goal's badge and its title.
private struct SuggestionRow: View {
    let task: CalendarTask
    let goal: CalendarGoal?
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let goal {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                }
                Text(task.title).appText(.sm).foregroundStyle(Theme.foreground).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHighlighted || isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(goal.map { "\(task.title) · \($0.title)" } ?? task.title)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// The goal's badge, which switches to the goal list.
private struct GoalButton: View {
    let goal: CalendarGoal
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            GoalBadge(icon: goal.icon, color: goal.color, size: .field, round: goal.isPractice)
                .overlay(RoundedRectangle(cornerRadius: goal.isPractice ? 19 : 10).stroke(Theme.foreground(isHovered ? 0.1 : 0), lineWidth: 2).padding(-1))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(goal.title)
        .accessibilityLabel("\(goal.isPractice ? "Practice" : "Project"): \(goal.title). Change it")
    }
}

private struct BackButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.arrowLeft.image(size: 16)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 32, height: 32)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Back")
    }
}

/// A goal in the list: its badge, title, and a tick on the chosen one.
private struct GoalRow: View {
    let goal: CalendarGoal
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                Text(goal.title).appText(.sm).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let perWeek = goal.perWeek, goal.isPractice {
                    Text("\(perWeek)× a week").appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
                }
                if isSelected {
                    Icon.tick.image(size: 15).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension BlockKind {
    var icon: Icon {
        switch self {
        case .session: .targetThin
        case .reserved: .lock
        case .task: .checkCircle
        }
    }

    /// "Reserved time" rather than "Reserved", where it stands alone.
    var longLabel: String { self == .reserved ? "Reserved time" : label }
}

extension CalendarData {
    /// Open tasks that could take time drawn on the calendar: those without an upcoming block.
    func unscheduledTasks(now: Date) -> [CalendarTask] {
        let timed = Set(nextBlocks(now: now).keys)
        return tasks.filter { !timed.contains($0.id) && !$0.isPending }
    }

    /// "Today · 12:00–1:00 PM · 1h" for time drawn on a day, in days from today.
    func newBlockLabel(day: Int, start: Int, end: Int, now: Date, clock: Clock) -> String {
        let name = switch day {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: CalendarDayMath.midnight(day, from: now).formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        }
        return "\(name) · \(clock.formatRange(start, end)) · \(durationLabel(Double(end - start)))"
    }
}

#Preview("New block") {
    NewBlockPopover(
        goals: Fixtures.calendar.goals, tasks: Fixtures.calendar.tasks, goalId: Fixtures.calendar.goals.first?.id ?? "",
        timeLabel: "Today · 12:00–1:00 PM · 1h", onAdd: { _, _, _ in }, onCancel: {}
    )
    .frame(width: 320)
    .padding(40)
}

#Preview("New task, suggesting") {
    NewBlockPopover(
        goals: Fixtures.calendar.goals, tasks: Fixtures.calendar.tasks, goalId: Fixtures.calendar.goals.first?.id ?? "",
        kind: .task, title: "re", timeLabel: "Today · 12:00–1:00 PM · 1h", onAdd: { _, _, _ in }, onCancel: {}
    )
    .frame(width: 320)
    .padding(40)
}
