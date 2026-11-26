import SwiftUI

/// What the menu bar can do for a session, each returning an error to show, or nil.
struct SessionPlanActions {
    var setAim: (_ blockId: String, _ text: String) async -> String?
    var plan: (_ blockId: String) async -> String?
    var suggestFocus: (_ blockId: String, _ instead: [String]) async -> FocusOutcome
}

/// What the session you're in (or about to start) is for, in the menu bar: your aim, which you can
/// set or change here, since right before a session is when it's clearest; then the prepared agenda
/// (folded to a few lines) and the tasks it draws on, which you can check off. Without an agenda it
/// offers to plan the session, or, when nothing says what it's for yet, to suggest a focus.
/// A task's session has no aim field: the task is its aim.
struct SessionPlanView: View {
    let block: Block
    var error: String?
    var actions: SessionPlanActions?
    var onSetTaskDone: (_ taskId: String, _ done: Bool) -> Void = { _, _ in }

    @State private var isExpanded = false
    @State private var draft: String
    @FocusState private var aimFocused: Bool
    @State private var actionError: String?
    @State private var planning = false
    /// A focus suggested here, until it's taken or set aside.
    @State private var suggestion: FocusSuggestion?
    @State private var suggesting = false
    /// Aims suggested here and passed over, so the next suggestion differs.
    @State private var passed: [String] = []

    /// `suggestion` shows one already, for previews and snapshots.
    init(
        block: Block,
        error: String? = nil,
        actions: SessionPlanActions? = nil,
        suggestion: FocusSuggestion? = nil,
        onSetTaskDone: @escaping (_ taskId: String, _ done: Bool) -> Void = { _, _ in }
    ) {
        self.block = block
        self.error = error
        self.actions = actions
        self.onSetTaskDone = onSetTaskDone
        _draft = State(initialValue: block.aim ?? "")
        _suggestion = State(initialValue: suggestion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !block.isTask {
                VStack(alignment: .leading, spacing: 4) {
                    if block.aim != nil { SectionLabel("Aim") }
                    // macOS ignores a prompt's colour, and in the system's text colour it read as an aim already set.
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .lineLimit(1...4)
                        .placeholder("Add an aim", when: draft.isEmpty, font: .callout, color: .systemPlaceholder)
                        .focused($aimFocused)
                        .onSubmit(saveAim)
                        .onChange(of: aimFocused) { if !aimFocused { saveAim() } }
                        // Set from outside the field too, like taking a suggested focus.
                        .onChange(of: block.aim) { if !aimFocused { draft = block.aim ?? "" } }
                        .onDisappear(perform: saveAim)
                        .help("What you want out of this session. Steers its plan, and the recap checks the session against it")
                        .accessibilityLabel("What you want out of this session")
                }
            }

            if let agenda = block.agenda {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Agenda")
                    Text(agenda.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    // About four lines at this width; shorter agendas show whole.
                    if agenda.text.count > 180 {
                        Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                            .linkButtonStyle()
                            .font(.caption)
                    }
                }

                if !agenda.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Named as in the calendar's block panel.
                        SectionLabel("Related tasks")
                        ForEach(agenda.tasks) { task in
                            TaskRow(task: task) { onSetTaskDone(task.id, !task.done) }
                        }
                    }
                }
            } else if block.needsFocus {
                if let suggestion {
                    SuggestedFocus(suggestion: suggestion, suggesting: suggesting, onUse: adopt, onAnother: another, onDismiss: dismiss)
                } else {
                    QuietAction(title: suggesting ? "Suggesting…" : "Suggest a focus", systemImage: "scope", busy: suggesting, action: suggest)
                        .help("Suggests an aim for this session, from the project’s week, tasks, notes and latest read")
                }
            } else {
                QuietAction(title: planning ? "Planning…" : "Plan this session", systemImage: "checklist", busy: planning, action: plan)
                    .help("A short plan for getting what this session is for, from the project’s tasks, notes and latest read")
            }

            if let message = actionError ?? error {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func saveAim() {
        guard let actions else { return }
        let text = draft
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) != (block.aim ?? "") else { return }
        let blockId = block.id
        Task { actionError = await actions.setAim(blockId, text) }
    }

    private func plan() {
        guard let actions, !planning else { return }
        actionError = nil
        planning = true
        let blockId = block.id
        Task {
            actionError = await actions.plan(blockId)
            planning = false
        }
    }

    private func suggest() {
        guard let actions, !suggesting else { return }
        actionError = nil
        suggesting = true
        let blockId = block.id, instead = passed
        Task {
            switch await actions.suggestFocus(blockId, instead) {
            case .suggested(let next): suggestion = next
            case .failed(let message): actionError = message
            }
            suggesting = false
        }
    }

    private func another() {
        if let suggestion { passed.append(suggestion.aim) }
        suggest()
    }

    private func dismiss() {
        if let suggestion { passed.append(suggestion.aim) }
        suggestion = nil
    }

    /// Takes the suggestion as the session's aim; from there the menu bar offers to plan it.
    private func adopt() {
        guard let actions, let suggestion else { return }
        actionError = nil
        let blockId = block.id
        Task {
            if let message = await actions.setAim(blockId, suggestion.aim) {
                actionError = message
            } else {
                self.suggestion = nil
                passed = []
            }
        }
    }
}

/// A suggested focus: take it as the aim, ask for another, or set it aside.
private struct SuggestedFocus: View {
    let suggestion: FocusSuggestion
    let suggesting: Bool
    let onUse: () -> Void
    let onAnother: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Suggested focus")
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Set this suggestion aside")
                .accessibilityLabel("Set this suggestion aside")
            }
            Group {
                Text(suggestion.aim)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !suggestion.why.isEmpty {
                    Text(suggestion.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(suggesting ? 0.5 : 1)
            HStack(spacing: 8) {
                Button("Use as aim", action: onUse)
                    .buttonStyle(.borderedProminent)
                Button(suggesting ? "Suggesting…" : "Another", action: onAnother)
            }
            .controlSize(.small)
            .disabled(suggesting)
            .padding(.top, 2)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
    }
}

/// A small text button with an icon, for the session's next step.
private struct QuietAction: View {
    let title: String
    let systemImage: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .disabled(busy)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct TaskRow: View {
    let task: SessionAgenda.Item
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.callout)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(TaskItem.minutesLabel(task.minutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.done ? "Reopen \(task.title)" : "Mark \(task.title) done")
    }
}

#Preview("Suggested focus") {
    let now = Fixtures.referenceNow
    if let block = Fixtures.current(at: now) {
        SessionPlanView(block: Block(id: block.id, title: block.goal, goal: "Protected time", start: block.start, end: block.end, tint: block.tint, untitled: true),
                        suggestion: Fixtures.focusSuggestion)
            .padding(16)
            .frame(width: 300)
    }
}
