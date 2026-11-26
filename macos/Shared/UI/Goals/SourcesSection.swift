import SwiftUI

/// What the Sources section asks of whoever owns the data. Saving reports an error message, or nil.
struct SourceActions {
    /// Adds a source for a connected app, or with `editing`, changes that source.
    var save: (_ connection: ConnectionOption, _ relation: String, _ editing: SourceItem?) async -> String? = { _, _, _ in nil }
    var delete: (SourceItem) -> Void = { _ in }
    var openConnections: () -> Void = {}
}

/// Where context for the goal lives, and how it relates, matching sources-section.tsx.
struct SourcesSection: View {
    let sources: [SourceItem]
    let options: [ConnectionOption]
    let goal: Goal
    var actions = SourceActions()

    @Environment(\.overlays) private var overlays
    @State private var addAnchor = CGRect.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sources").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                    Text("Where context for this \(goal.kind.noun) lives, and how it relates.").appText(.sm).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !options.isEmpty {
                    RoundIconButton(icon: .add, action: add)
                        .modifier(AnchorReader(frame: $addAnchor))
                        .help("Add source")
                        .accessibilityLabel("Add source")
                }
            }
            .padding(.bottom, 16)

            if options.isEmpty {
                // `rounded-2xl border border-dashed p-6`, with "Go to Connections" as an inline link.
                Text("Connect Linear, GitHub or Granola first, then tell Supervibes where this \(goal.kind.noun)’s context lives. **[Go to Connections](supervibes-app://connections)**")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .tint(Theme.foreground)
                    .environment(\.openURL, OpenURLAction { _ in
                        actions.openConnections()
                        return .handled
                    })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .dashedCard()
            } else if sources.isEmpty {
                Text("No sources yet. Add one and describe, in your own words, where to look and how it relates to this \(goal.kind.noun).")
                    .appText(.sm).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .dashedCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        SourceRow(source: source, onEdit: { edit(source) }, actions: actions)
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .clipShape(.rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            }
        }
        .padding(.top, 48)
    }

    /// "Add source": straight to the dialog with one connected app, otherwise pick the app first.
    private func add() {
        guard let overlays else { return }
        if options.count == 1, let only = options.first {
            return openDialog(only, editing: nil)
        }
        overlays.showMenu(anchor: addAnchor) {
            MenuPanel(width: 208) {
                ForEach(options) { option in
                    AppRow(option: option) { openDialog(option, editing: nil) }
                }
            }
        }
    }

    private func edit(_ source: SourceItem) {
        let option = options.first { $0.id == source.connectionId }
            ?? ConnectionOption(id: source.connectionId, provider: source.provider, label: source.provider.label, relationHint: "")
        openDialog(option, editing: source)
    }

    private func openDialog(_ connection: ConnectionOption, editing: SourceItem?) {
        guard let overlays else { return }
        overlays.showDialog {
            SourceDialog(
                goal: goal,
                connection: connection,
                relation: editing?.relation ?? "",
                isEditing: editing != nil,
                onCancel: { overlays.dismiss() },
                onSave: { relation in
                    let error = await actions.save(connection, relation, editing)
                    if error == nil { overlays.dismiss() }
                    return error
                }
            )
        }
    }
}

extension ConnectionItem.Provider {
    var label: String {
        switch self {
        case .linear: "Linear"
        case .github: "GitHub"
        case .granola: "Granola"
        case .slack: "Slack"
        }
    }
}

/// `flex items-center gap-4 px-5 py-3.5`: the app, how it relates, and its menu.
private struct SourceRow: View {
    let source: SourceItem
    let onEdit: () -> Void
    let actions: SourceActions

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero

    var body: some View {
        HStack(spacing: 16) {
            ProviderMark(provider: source.provider)
            VStack(alignment: .leading, spacing: 0) {
                Text(source.provider.label).appText(.sm, .semibold).foregroundStyle(Theme.foreground)
                Text(source.relation.replacingOccurrences(of: "\n", with: " "))
                    .appText(.sm).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                    .help(source.relation)
            }
            Spacer(minLength: 8)
            if let error = source.lastError {
                LinkButton(title: "Needs reconnecting", tone: Theme.danger, size: .xs, action: actions.openConnections)
                    .help(error)
            }
            RoundIconButton(icon: .more, action: openMenu)
                .modifier(AnchorReader(frame: $anchor))
                .accessibilityLabel("\(source.provider.label) source options")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contextPanel { menu }
    }

    private func openMenu() {
        overlays?.showMenu(anchor: anchor) { menu }
    }

    /// The same for ⋯ and a right-click.
    @ViewBuilder private var menu: some View {
        if let overlays {
            MenuPanel {
                MenuItem(icon: .edit, title: "Edit") {
                    overlays.dismiss()
                    onEdit()
                }
                MenuItem(icon: .delete, title: "Delete", isDestructive: true) {
                    overlays.showDialog {
                        ConfirmDialog(
                            title: "Remove this \(source.provider.label) source?",
                            message: "Future progress reads won’t look here anymore. The app itself stays connected.",
                            confirmTitle: "Remove",
                            onCancel: { overlays.dismiss() },
                            onConfirm: {
                                overlays.dismiss()
                                actions.delete(source)
                            }
                        )
                    }
                }
            }
        }
    }
}

/// A connected app in the "Add source" menu: `h-10 rounded-lg px-2.5 text-sm font-medium`.
private struct AppRow: View {
    let option: ConnectionOption
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProviderMark(provider: option.provider, size: 24)
                Text(option.label).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Inline text that acts like a link: semibold, underlined on hover.
private struct LinkButton: View {
    let title: String
    var tone: Color = Theme.foreground
    var size: TextSize = .sm
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(size, size == .xs ? .medium : .semibold).foregroundStyle(tone).underline(isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private extension View {
    /// `rounded-2xl border border-dashed border-foreground/15`
    func dashedCard() -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Dialog

/// "Add a source" or "Edit source": the goal with the app tucked into its corner, then how the app
/// relates to the goal, in the person's words.
struct SourceDialog: View {
    let goal: Goal
    let connection: ConnectionOption
    @State var relation: String
    let isEditing: Bool
    var onCancel: () -> Void = {}
    /// Returns an error to show, or nil once saved.
    var onSave: (String) async -> String? = { _ in nil }

    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .lg)
                        .overlay(alignment: .bottomTrailing) {
                            ProviderMark(provider: connection.provider, size: 24)
                                .padding(3)
                                .background(Theme.background, in: .rect(cornerRadius: 9))
                                .offset(x: 9, y: 9)
                        }
                    Spacer()
                    DialogCloseButton(action: onCancel)
                }

                Text(isEditing ? "Edit source" : "Add a source")
                    .appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                    .padding(.top, 20)
                Text("For “\(goal.title)”").appText(.sm).foregroundStyle(Theme.muted).padding(.top, 4)

                Text("How does \(connection.label) relate to this \(goal.kind.noun)?")
                    .appText(.sm, .medium).foregroundStyle(Theme.foreground)
                    .padding(.top, 24)
                Text("Where to look, what counts, and what to ignore.")
                    .appText(.sm).foregroundStyle(Theme.muted)
                    .padding(.top, 4)

                TextField("", text: $relation, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(14))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(6...12)
                    .focused($focused)
                    .placeholder(connection.relationHint, when: relation.isEmpty, font: .app(14), color: Theme.muted.opacity(0.8))
                    .accessibilityLabel("How \(connection.label) relates to this \(goal.kind.noun)")
                    .onChange(of: relation) { error = nil }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focused ? Theme.lineStrong : Theme.cardBorder))
                    .padding(.top, 12)

                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 8)
                }
            }
            .padding(24)

            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel", action: onCancel)
                PrimaryButton(title: isSaving ? "Saving…" : isEditing ? "Save" : "Add source", isBusy: isSaving, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.background)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
        .onAppear { focused = true }
        .onEscape(perform: onCancel)
    }

    private func submit() {
        if let problem = SourceItem.problem(relation) {
            error = problem
            return
        }
        isSaving = true
        Task {
            let failure = await onSave(relation.trimmingCharacters(in: .whitespacesAndNewlines))
            isSaving = false
            error = failure
        }
    }
}

/// `h-9 w-9 rounded-full text-muted hover:bg-wash`
private struct DialogCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.close.image(size: 18)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 36, height: 36)
                .background(isHovered ? Theme.wash : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.trailing, -8)
        .padding(.top, -4)
        .accessibilityLabel("Close")
    }
}

#Preview("Sources") {
    VStack(spacing: 0) {
        SourcesSection(sources: Fixtures.sources, options: Fixtures.connectionOptions, goal: Fixtures.goals[0])
        SourcesSection(sources: [], options: Fixtures.connectionOptions, goal: Fixtures.goals[0])
    }
    .padding(.horizontal, 32)
    .frame(width: 832, height: 600, alignment: .top)
    .background(Theme.background)
}

#Preview("Source dialog") {
    SourceDialog(goal: Fixtures.goals[0], connection: Fixtures.connectionOptions[0], relation: "", isEditing: false)
        .padding(24)
        .background(Theme.shell)
}
