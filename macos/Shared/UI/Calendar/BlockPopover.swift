import SwiftUI

/*
 * Sits next to a block on the timeline to name it and pick its goal, as block-popover.tsx. The goal
 * icon beside the title switches it to a goal list in place. Return saves; Esc steps back or
 * cancels; a press elsewhere on the timeline cancels.
 */

struct BlockPopover: View {
    let goals: [CalendarGoal]
    /// Intentions are a task already: the title reads as what you'll do.
    let intention: Bool
    let timeLabel: String
    let onSave: (_ goalId: String, _ title: String?) -> Void
    let onCancel: () -> Void

    /// Roughly how tall it is, to decide whether it opens above or below.
    static let estimatedHeight: CGFloat = 200
    /// MAX_BLOCK_TITLE
    private static let maxTitle = 120

    @State private var goalId: String
    @State private var title: String
    @State private var showsGoals = false
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case title, goal }

    init(goals: [CalendarGoal], goalId: String, title: String, intention: Bool, timeLabel: String,
         onSave: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.goals = goals
        self.intention = intention
        self.timeLabel = timeLabel
        self.onSave = onSave
        self.onCancel = onCancel
        _goalId = State(initialValue: goalId)
        _title = State(initialValue: title)
    }

    private var goal: CalendarGoal? { goals.first { $0.id == goalId } }

    var body: some View {
        Group {
            if showsGoals { goalList } else { main }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.card)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.04)), radius: 1, y: 1)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.18)), radius: 16, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .onExitCommand {
            if showsGoals { back(to: .goal) } else { onCancel() }
        }
        .onAppear { focus = .title }
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let goal {
                    GoalButton(goal: goal) { showsGoals = true }
                        .focused($focus, equals: .goal)
                } else {
                    Text("Add a goal first.").appText(.sm).foregroundStyle(Theme.muted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeLabel).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.app(16, .semibold))
                        .tracking(-0.16)
                        .foregroundStyle(Theme.foreground)
                        .focused($focus, equals: .title)
                        .placeholder(intention ? "What you’ll do" : "Add a title", when: title.isEmpty, font: .app(16, .medium))
                        .onSubmit(save)
                        .onChange(of: title) { if title.count > Self.maxTitle { title = String(title.prefix(Self.maxTitle)) } }
                        .accessibilityLabel("Title")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)

            HStack(spacing: 4) {
                Spacer()
                PopoverButton(title: "Cancel", isPrimary: false, action: onCancel)
                PopoverButton(title: "Save", isPrimary: true, action: save)
                    .compositingGroup()
                    .opacity(goal == nil ? 0.3 : 1)
                    .inactive(goal == nil)
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private func save() {
        guard goal != nil else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(goalId, trimmed.isEmpty ? nil : trimmed)
    }

    // MARK: Goals

    private var goalList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                BackButton { back(to: .goal) }
                Text("Goal").appText(.sm, .semibold).foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(goals) { option in
                        GoalRow(goal: option, isSelected: option.id == goalId) {
                            goalId = option.id
                            back(to: .title)
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

/// The goal's badge, which switches to the goal list.
private struct GoalButton: View {
    let goal: CalendarGoal
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            GoalBadge(icon: goal.icon, color: goal.color, size: .field)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.foreground(isHovered ? 0.1 : 0), lineWidth: 2).padding(-1))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .help(goal.title)
        .accessibilityLabel("Goal: \(goal.title). Change goal")
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
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                Text(goal.title).appText(.sm).foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

/// `h-8 rounded-lg`: Cancel is quiet, Save is solid.
private struct PopoverButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, isPrimary ? .semibold : .medium)
                .foregroundStyle(isPrimary ? Theme.background : isHovered ? Theme.foreground : Theme.muted)
                .padding(.horizontal, isPrimary ? 14 : 12)
                .frame(height: 32)
                .background(isPrimary ? Theme.foreground : isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .opacity(isPrimary && isHovered ? 0.9 : 1)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
