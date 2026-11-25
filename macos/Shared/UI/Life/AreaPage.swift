import SwiftUI

/// An area's own page, from its card on Life or a goal's page: one column, top to bottom. The way back to Life, the
/// area's tile and name, its read, where you are and where you're going in your own words (a prompt for each until
/// said), then the goals moving it, each opening its own page, with ways to start or move one in.
///
/// The pencil edits it in place: its icon, name and words become fields, each goal can be taken out of it, another
/// goal moved in, and the area removed. Done saves.
struct AreaPage: View {
    let detail: AreaDetail
    /// The person's goals outside this area, to move one in.
    var otherGoals: [Goal] = []
    /// Why the last change didn't go through.
    var error: String?
    var onBack: () -> Void = {}
    var onOpenGoal: (Goal) -> Void = { _ in }
    /// What can change the area; nil leaves the page as it is.
    var actions: AreaPageActions?
    /// Opens being edited (snapshots).
    var startsEditing = false
    /// Its read is being written.
    var reading = false
    /// Why the last read didn't come back.
    var readError: String?
    /// Writes its read; nil leaves the read as it is.
    var onRead: (() -> Void)?
    /// The clock the read's age is told against.
    var now = Date()

    enum Field: Hashable { case name, now, want }

    /// Editing; nil until the pencil or Done is pressed, then it follows them.
    @State private var editing: Bool?
    /// The area as edited, until saved.
    @State private var draft: AreaInput?
    @State private var isSaving = false
    @FocusState private var focus: Field?
    @Environment(\.overlays) private var overlays

    private var isEditing: Bool { editing ?? startsEditing }
    private var input: AreaInput { draft ?? AreaInput(editing: detail.area) }
    private var area: Area { detail.area }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackToLife(action: onBack)
                    Spacer()
                    if actions != nil {
                        if isEditing {
                            PrimaryButton(title: isSaving ? "Saving…" : "Done", isBusy: isSaving, action: finish)
                        } else {
                            EditButton { startEditing() }
                        }
                    }
                }
                .frame(height: 32)

                if isEditing {
                    AreaIconButton(icon: input.icon, size: 48) { icon in
                        var next = input
                        next.icon = icon
                        draft = next
                    }
                    .padding(.top, 32)
                    TextField("", text: binding(\.name, max: AreaInput.maxName))
                        .textFieldStyle(.plain)
                        .font(.app(32, .semibold))
                        .tracking(-0.03 * 32)
                        .foregroundStyle(Theme.foreground)
                        .placeholder("Name this area", when: input.name.isEmpty, font: .app(32, .semibold))
                        .focused($focus, equals: .name)
                        .onSubmit(finish)
                        .padding(.horizontal, 10)
                        .frame(height: 52)
                        .background(Theme.card, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focus == .name ? Theme.foreground(0.6) : Theme.cardBorder, lineWidth: focus == .name ? 1.5 : 1))
                        .padding(.horizontal, -10)
                        .padding(.top, 16)
                } else {
                    AreaTile(icon: area.icon, size: 48).padding(.top, 32)
                    Text(area.name)
                        .font(.app(32, .semibold))
                        .tracking(-0.03 * 32)
                        .foregroundStyle(Theme.foreground)
                        .padding(.top, 16)
                }

                if let error {
                    Banner(text: error, tone: .error).padding(.top, 20)
                }

                // The read is Supervibes' to write, so it's out of the way while you edit.
                if !isEditing {
                    AreaReadCard(detail: detail, reading: reading, error: readError, now: now, onRead: onRead)
                        .padding(.top, 32)
                }

                words(.now, label: "Where you are", text: area.now, prompt: "Where does this area stand today?")
                    .padding(.top, 40)
                words(.want, label: "Where you’re going", text: area.want, prompt: "Where do you want it to go?", muted: true)
                    .padding(.top, 28)

                goals.padding(.top, 40)

                if isEditing, actions != nil {
                    RemoveAreaLink(name: area.name) { confirmRemove() }
                        .padding(.top, 40)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onExitCommand { if isEditing { cancel() } }
    }

    // MARK: Words

    @ViewBuilder
    private func words(_ field: Field, label: String, text: String?, prompt: String, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            if isEditing {
                TextField("", text: binding(field == .now ? \.now : \.want, max: AreaInput.maxWords), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(17, .medium))
                    .tracking(-0.01 * 17)
                    .lineSpacing(17 * 0.5 - 17 * 0.2)
                    .foregroundStyle(muted ? Theme.foreground(0.8) : Theme.foreground)
                    .lineLimit(1...8)
                    .placeholder(prompt, when: (field == .now ? input.now : input.want).isEmpty, font: .app(17, .medium))
                    .focused($focus, equals: field)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focus == field ? Theme.foreground(0.6) : Theme.cardBorder, lineWidth: focus == field ? 1.5 : 1))
            } else if let text, !text.isEmpty {
                Text(text)
                    .font(.app(17, .medium))
                    .tracking(-0.01 * 17)
                    .lineSpacing(17 * 0.5 - 17 * 0.2)
                    .foregroundStyle(muted ? Theme.foreground(0.8) : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PromptBox(text: prompt, isEnabled: actions != nil) { startEditing(focusing: field) }
            }
        }
    }

    // MARK: Goals

    private var goals: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Goals")
            if detail.goals.isEmpty, actions == nil || isEditing {
                Text("No goals in this area yet.").appText(.sm).foregroundStyle(Theme.muted).padding(.top, 12)
            } else if !detail.goals.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(detail.goals.enumerated()), id: \.element.id) { index, goal in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        GoalRow(
                            goal: goal,
                            week: detail.weeks[goal.id],
                            onTakeOut: isEditing ? actions.map { actions in { actions.takeOut(goal) } } : nil
                        ) { onOpenGoal(goal) }
                    }
                }
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
                .clipShape(.rect(cornerRadius: 16))
                .padding(.top, 12)
            }

            if let actions {
                HStack(spacing: 12) {
                    if isEditing {
                        MoveGoalHere(title: "Move a goal into \(area.name)", goals: otherGoals, onPick: actions.moveIn)
                    } else if detail.goals.isEmpty {
                        DashedButton(icon: .add, title: "New goal in this area", action: actions.newGoal)
                        MoveGoalHere(title: "Move a goal here", goals: otherGoals, onPick: actions.moveIn)
                    } else {
                        DashedButton(icon: .add, title: "New goal in \(area.name)", action: actions.newGoal)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: Editing

    private func binding(_ key: WritableKeyPath<AreaInput, String>, max: Int) -> Binding<String> {
        Binding(
            get: { input[keyPath: key] },
            set: { value in
                var next = input
                next[keyPath: key] = String(value.prefix(max))
                draft = next
            }
        )
    }

    private func startEditing(focusing field: Field? = nil) {
        draft = AreaInput(editing: area)
        editing = true
        if let field {
            DispatchQueue.main.async { focus = field }
        }
    }

    private func finish() {
        guard let actions else { return }
        isSaving = true
        Task {
            if await actions.save(input) {
                editing = false
                draft = nil
            }
            isSaving = false
        }
    }

    private func cancel() {
        draft = nil
        editing = false
    }

    private func confirmRemove() {
        guard let overlays, let actions else { return }
        overlays.showDialog {
            removeAreaDialog(area.name, onCancel: { overlays.dismiss() }) {
                overlays.dismiss()
                actions.remove()
            }
        }
    }
}

/// What an area's page can do: save its edits, remove it (once the person has said yes), move goals in and out,
/// and start a goal in it.
struct AreaPageActions {
    /// Saves the area's edits; true once saved.
    var save: (AreaInput) async -> Bool
    var remove: () -> Void
    var takeOut: (Goal) -> Void
    var moveIn: (Goal) -> Void
    var newGoal: () -> Void
}

/// "← Life": `text-sm font-medium text-muted hover:text-foreground`, as on a goal's page.
private struct BackToLife: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text("Life").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The page's pencil: `size-8 rounded-lg border bg-card`.
private struct EditButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.edit.image(size: 15)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.8))
                .frame(width: 32, height: 32)
                .background(Theme.card, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Edit")
        .accessibilityLabel("Edit area")
    }
}

/// `text-[11px] font-medium uppercase tracking-[0.02em] text-muted`
private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.app(11, .medium))
            .tracking(0.02 * 11)
            .foregroundStyle(Theme.muted)
    }
}

/// A dashed prompt for an answer not said yet; it opens editing on that answer.
private struct PromptBox: View {
    let text: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon.edit.image(size: 15)
                Text(text).font(.app(15))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(isHovered ? Theme.card : .clear, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.foreground(isHovered ? 0.3 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .inactive(!isEnabled)
        .onHover { isHovered = $0 && isEnabled }
    }
}

/// `h-11 rounded-2xl border border-dashed text-[13px] font-medium text-muted`, filling its share of the row.
private struct DashedButton: View {
    let icon: Icon
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.image(size: 15)
                Text(title).font(.app(13, .medium)).lineLimit(1)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
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

/// A dashed button that opens a menu of the person's other goals, to move one into the area.
private struct MoveGoalHere: View {
    let title: String
    let goals: [Goal]
    let onPick: (Goal) -> Void
    @State private var anchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    var body: some View {
        DashedButton(icon: .arrowForward, title: title) {
            overlays?.showMenu(anchor: anchor, alignLeading: true) {
                MenuPanel(width: 320) {
                    if goals.isEmpty {
                        Text("Every goal is in this area already.")
                            .appText(.sm).foregroundStyle(Theme.muted)
                            .padding(10)
                    }
                    ForEach(goals) { goal in
                        GoalMenuRow(goal: goal) {
                            overlays?.dismiss()
                            onPick(goal)
                        }
                    }
                }
            }
        }
        .modifier(AnchorReader(frame: $anchor))
    }
}

/// A goal as a row in a menu: its badge and title.
private struct GoalMenuRow: View {
    let goal: Goal
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .mini)
                Text(goal.title).appText(.sm, .medium).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// "Remove Madrid", in red, at the end of the page while editing.
private struct RemoveAreaLink: View {
    let name: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.close.image(size: 14)
                Text("Remove \(name)").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isHovered ? Theme.danger.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
            .padding(.horizontal, -10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A goal in the area: its badge, title and this week's objective, its status, and a way into its page. While
/// editing, an × in place of the status takes it out of the area, and the row itself doesn't open the goal.
private struct GoalRow: View {
    let goal: Goal
    let week: GoalWeek?
    var onTakeOut: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        if let onTakeOut {
            row { AreaRemoveButton(help: "Take it out of this area", action: onTakeOut) }
        } else {
            Button(action: action) {
                row {
                    if let latest = goal.latest, let status = latest.status, let basis = latest.basis {
                        StatusText(status: status, basis: basis)
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                    Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
                }
                .background(isHovered ? Theme.wash : .clear)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private func row(@ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            GoalBadge(icon: goal.icon, color: goal.color, size: .card)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.app(14, .semibold))
                    .tracking(-0.01 * 14)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                if let objective = week?.objective, !objective.isEmpty {
                    HStack(spacing: 6) {
                        Icon.flag.image(size: 11)
                        Text(objective).font(.app(12.5)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

@MainActor private let previewActions = AreaPageActions(save: { _ in true }, remove: {}, takeOut: { _ in }, moveIn: { _ in }, newGoal: {})

#Preview("Madrid") {
    AreaPage(detail: Fixtures.areaDetail, actions: previewActions, onRead: {}, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 1140)
}

#Preview("Editing Madrid") {
    AreaPage(detail: Fixtures.areaDetail, actions: previewActions, startsEditing: true)
        .background(Theme.background)
        .frame(width: 900, height: 940)
}

#Preview("A new area") {
    AreaPage(detail: Fixtures.newAreaDetail, actions: previewActions, onRead: {}, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 1040)
}
