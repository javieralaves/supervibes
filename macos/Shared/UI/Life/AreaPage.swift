import SwiftUI

/// An area's own page, from its card on Life or a goal's page. Every area has the same shape, top to bottom (the
/// design's AreaPageLayout in supervibes-design, seasons-quests.tsx):
///   1. Who it is: the way back to Life, its tile and name, then one quiet line with its status.
///   2. Where it's going: where you are and where you want to be side by side, and the gap between them under them.
///   3. This season: its quest, when the running season has one here.
///   4. How it's going: Supervibes' read. Its status is in the header, so the read doesn't repeat it.
///   5. Projects & practices: one list, the season's own first and marked, each row opening its page, then a way to
///      start one in it.
///
/// The pencil edits it in place: its icon, name and words become fields, each goal can be taken out of it, another
/// goal moved in, and the area removed. Done saves. The gap is written from its own card.
struct AreaPage: View {
    let detail: AreaDetail
    /// The person's goals outside this area, to move one in.
    var otherGoals: [Goal] = []
    /// Why the last change didn't go through.
    var error: String?
    var onBack: () -> Void = {}
    var onOpenGoal: (Goal) -> Void = { _ in }
    var onOpenQuest: (Quest) -> Void = { _ in }
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
    /// Supervibes is naming its gap.
    var namingGap = false
    /// Why the gap couldn't be named or saved.
    var gapError: String?
    /// Opens with the gap being written (snapshots).
    var startsWritingGap = false
    /// The clock the read's and the gap's ages are told against.
    var now = Date()

    enum Field: Hashable { case name, now, want }

    /// Editing; nil until the pencil or Done is pressed, then it follows them.
    @State private var editing: Bool?
    /// The area as edited, until saved.
    @State private var draft: AreaInput?
    @State private var isSaving = false
    @State private var addAnchor = CGRect.zero
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
                            PrimaryButton(title: "Done", isBusy: isSaving, action: finish)
                        } else {
                            EditButton { startEditing() }
                        }
                    }
                }
                .frame(height: 32)

                identity

                if let error {
                    Banner(text: error, tone: .error).padding(.top, 20)
                }

                direction.padding(.top, 32)

                if !isEditing, let quest = detail.quest, let season = detail.season, season.state == .active {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            SectionTitle("This season")
                            HStack(spacing: 6) {
                                Icon.season.image(size: 12)
                                Text("\(season.name) · \(weekLine(season))").monospacedDigit()
                            }
                            .font(.app(13))
                            .foregroundStyle(Theme.muted)
                        }
                        AreaQuestCard(quest: quest, goals: questGoals) { onOpenQuest(quest) }
                    }
                    .padding(.top, 40)
                }

                // The read is Supervibes' to write, so it's out of the way while you edit.
                if !isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("How it’s going")
                        AreaReadCard(detail: detail, reading: reading, error: readError, now: now, onRead: onRead)
                    }
                    .padding(.top, 40)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle("Projects & practices")
                    goals
                }
                .padding(.top, 40)

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

    // MARK: Who it is

    @ViewBuilder private var identity: some View {
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
            // Its status, its goals' worst: the one place the page says it.
            Group {
                HStack(spacing: 12) {
                    if let status = area.status {
                        StatusText(status: status, basis: .target)
                            .help("The most pressing of its projects’ and practices’ statuses")
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                    if hasSeason {
                        Rectangle().fill(Theme.foreground(0.15)).frame(width: 1, height: 12)
                        HStack(spacing: 6) {
                            Icon.season.image(size: 13)
                            Text("In season")
                        }
                        .font(.app(13))
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(height: 16)
            .padding(.top, 12)
        }
    }

    /// The running season's quest here moves these.
    private var questGoals: [Goal] {
        guard let quest = detail.quest else { return [] }
        return detail.goals.filter { quest.goalIds.contains($0.id) }
    }

    private var hasSeason: Bool { detail.quest != nil && detail.season?.state == .active }

    private func season(of goal: Goal) -> InSeason {
        guard hasSeason, let quest = detail.quest else { return .none }
        return quest.goalIds.contains(goal.id) ? .moving : .outside
    }

    /// The season's own first, then the rest, each in their usual order.
    private var orderedGoals: [Goal] {
        guard hasSeason else { return detail.goals }
        return detail.goals.filter { season(of: $0) == .moving } + detail.goals.filter { season(of: $0) != .moving }
    }

    // MARK: Where it's going

    private var direction: some View {
        AreaDirectionCard {
            words(.now, text: area.now, prompt: "Where does \(area.name) stand today?")
        } want: {
            words(.want, text: area.want, prompt: "Where do you want it to be?", muted: true)
        } gap: {
            AreaGapView(
                area: area,
                hasGoals: !detail.goals.isEmpty,
                naming: namingGap,
                error: gapError,
                now: now,
                // Named or written from its own card, so not while the page's words are being edited.
                onName: isEditing ? nil : actions?.nameGap,
                onWrite: isEditing ? nil : actions?.writeGap,
                startsWriting: startsWritingGap
            )
        }
    }

    /// One side of the direction card: the words as said, a field while editing, or a prompt until said.
    @ViewBuilder
    private func words(_ field: Field, text: String?, prompt: String, muted: Bool = false) -> some View {
        if isEditing {
            TextField("", text: binding(field == .now ? \.now : \.want, max: AreaInput.maxWords), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(16, .medium))
                .tracking(-0.01 * 16)
                .lineSpacing(16 * 0.5 - 16 * 0.2)
                .foregroundStyle(muted ? Theme.foreground(0.8) : Theme.foreground)
                .lineLimit(2...8)
                .placeholder(prompt, when: (field == .now ? input.now : input.want).isEmpty, font: .app(16, .medium))
                .focused($focus, equals: field)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focus == field ? Theme.foreground(0.6) : Theme.cardBorder, lineWidth: focus == field ? 1.5 : 1))
                .padding(.horizontal, -12)
        } else if let text, !text.isEmpty {
            Text(text)
                .font(.app(16, .medium))
                .tracking(-0.01 * 16)
                .lineSpacing(16 * 0.5 - 16 * 0.2)
                .foregroundStyle(muted ? Theme.foreground(0.8) : Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            PromptLink(text: prompt, isEnabled: actions != nil) { startEditing(focusing: field) }
        }
    }

    // MARK: Projects and practices

    /// One list, in the goals' own order, then a way to start one here (or, editing, to move one in). Rows are
    /// split by hairlines; the card's edge closes the last.
    private var goals: some View {
        VStack(spacing: 0) {
            if detail.goals.isEmpty {
                Text("Nothing here yet. A project has a finish line; a practice, a rhythm.")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
            }
            ForEach(Array(orderedGoals.enumerated()), id: \.element.id) { index, goal in
                if index > 0 { hairline }
                AreaGoalRow(
                    goal: goal,
                    week: detail.weeks[goal.id],
                    season: season(of: goal),
                    onTakeOut: isEditing ? actions.map { actions in { actions.takeOut(goal) } } : nil
                ) { onOpenGoal(goal) }
            }
            if let actions {
                if isEditing || detail.goals.isEmpty {
                    hairline
                    MoveGoalHere(
                        title: detail.goals.isEmpty ? "Move one of yours here" : "Move a project or practice into \(area.name)",
                        goals: otherGoals,
                        onPick: actions.moveIn
                    )
                }
                if !isEditing {
                    hairline
                    ListActionRow(icon: .add, title: "New project or practice in \(area.name)") { showNewMenu(actions) }
                        .modifier(AnchorReader(frame: $addAnchor))
                }
            }
        }
        // With a season running, the list's own fill is a step dimmer and the season's rows fill themselves.
        .background(hasSeason ? InSeason.outside.cardFill : Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var hairline: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1)
    }

    private func showNewMenu(_ actions: AreaPageActions) {
        overlays?.showMenu(anchor: addAnchor, alignLeading: true) {
            MenuPanel(width: 220) {
                MenuItem(icon: .flag, title: "New project") {
                    overlays?.dismiss()
                    actions.newGoal(.project)
                }
                MenuItem(icon: .repeats, title: "New practice") {
                    overlays?.dismiss()
                    actions.newGoal(.practice)
                }
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
/// start a goal in it, and name or write its gap.
struct AreaPageActions {
    /// Saves the area's edits; true once saved.
    var save: (AreaInput) async -> Bool
    var remove: () -> Void
    var takeOut: (Goal) -> Void
    var moveIn: (Goal) -> Void
    /// Starts a project or a practice in the area.
    var newGoal: (GoalKind) -> Void
    /// Has Supervibes name the gap.
    var nameGap: () -> Void
    /// Saves the gap as written; true once saved.
    var writeGap: (GapInput) async -> Bool
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

/// A section's title on an area's page, one style throughout: `text-[15px] font-semibold tracking-[-0.01em]`.
private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.app(15, .semibold))
            .tracking(-0.01 * 15)
            .foregroundStyle(Theme.foreground)
    }
}

/// A quiet prompt for words not said yet, in their place on the direction card; it opens editing on them.
private struct PromptLink: View {
    let text: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Icon.edit.image(size: 14)
                Text(text).font(.app(15)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .inactive(!isEnabled)
        .onHover { isHovered = $0 && isEnabled }
    }
}

/// A row at the end of the list that does something rather than opening a goal: `h-12 px-5 text-[13px] font-medium
/// text-muted`, an icon before its words.
private struct ListActionRow: View {
    let icon: Icon
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.image(size: 14)
                Text(title).font(.app(13, .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(isHovered ? Theme.wash : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A row of the list that opens a menu of the person's other goals, to move one into the area.
private struct MoveGoalHere: View {
    let title: String
    let goals: [Goal]
    let onPick: (Goal) -> Void
    @State private var anchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    var body: some View {
        ListActionRow(icon: .arrowForward, title: title) {
            overlays?.showMenu(anchor: anchor, alignLeading: true) {
                MenuPanel(width: 320) {
                    if goals.isEmpty {
                        Text("Every project and practice is in this area already.")
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
                GoalBadge(goal: goal, size: .mini)
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

/// A project or practice in the area, the design's GoalListRow: its badge, title and a line (a practice's rhythm, a
/// project's objective this week); then, for a practice, this week's count; its status; and a way into its page.
/// While editing, an × in place of the status takes it out of the area, and the row itself doesn't open it.
private struct AreaGoalRow: View {
    let goal: Goal
    let week: GoalWeek?
    var season: InSeason = .none
    var onTakeOut: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        if let onTakeOut {
            row { AreaRemoveButton(help: "Take it out of this area", action: onTakeOut) }
        } else {
            Button(action: action) {
                row {
                    // This week, for practices: just the count, so names keep their room. Projects leave it empty.
                    Text(goal.practice.map { "\($0.week.done) of \($0.perWeek)" } ?? "")
                        .appText(.xs)
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                        .frame(width: 64, alignment: .trailing)
                    Group {
                        if let practice = goal.practice {
                            PracticeStatusText(practice: practice)
                        } else if let latest = goal.latest, let status = latest.status, let basis = latest.basis {
                            StatusText(status: status, basis: basis)
                        } else {
                            Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(minWidth: 92, alignment: .trailing)
                    Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
                }
                .background(isHovered ? Theme.wash : .clear)
                .background(season == .moving ? Theme.card : .clear)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }

    private func row(@ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            GoalBadge(goal: goal, size: .card).seasonMark(season == .moving)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.app(14, .semibold))
                    .tracking(-0.01 * 14)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                Group {
                    if let practice = goal.practice {
                        RhythmLabel(perWeek: practice.perWeek, iconSize: 11)
                    } else if let objective = week?.objective, !objective.isEmpty {
                        HStack(spacing: 6) {
                            Icon.flag.image(size: 11)
                            Text(objective).lineLimit(1)
                        }
                    }
                }
                .font(.app(12.5))
                .foregroundStyle(Theme.muted)
            }
            .padding(.leading, 2)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
    }
}

/// The area's quest this season (the design's AreaQuestCard): the route tile, its name and where it starts, its
/// effort; then its goals, the effort's reason, and Open quest.
private struct AreaQuestCard: View {
    let quest: Quest
    let goals: [Goal]
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Icon.route.image(size: 19)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 40, height: 40)
                        .background(Theme.foreground(0.06), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(quest.title)
                            .font(.app(17, .semibold)).tracking(-0.015 * 17)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(quest.fromLine).font(.app(13.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    if let effort = quest.effort {
                        StatusText(status: effort, basis: .target)
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                }
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.top, 16)
                HStack(spacing: 10) {
                    OverlappingBadges(goals: goals)
                    Text(effortLine(quest.effort, goals: goals)).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Text("Open quest")
                        Icon.arrowRight.image(size: 13)
                    }
                    .font(.app(13, .medium))
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.8))
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

@MainActor private let previewActions = AreaPageActions(save: { _ in true }, remove: {}, takeOut: { _ in }, moveIn: { _ in }, newGoal: { _ in },
                                                        nameGap: {}, writeGap: { _ in true })

#Preview("Madrid") {
    AreaPage(detail: Fixtures.areaDetail, actions: previewActions, onRead: {}, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 1140)
}

#Preview("Editing Madrid") {
    AreaPage(detail: Fixtures.areaDetail, actions: previewActions, startsEditing: true, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 940)
}

#Preview("Health, with practices") {
    AreaPage(detail: Fixtures.practiceAreaDetail, actions: previewActions, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 1000)
}

#Preview("A new area") {
    AreaPage(detail: Fixtures.newAreaDetail, actions: previewActions, onRead: {}, now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 1040)
}
