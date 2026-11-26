import SwiftUI

/// Life, the home page: a greeting for the time of day, then projects (goals with a finish line) as cards, each with
/// its week (this week's objective, and what's free or over of its session time); then practices (kept up a number
/// of times a week), each with its rhythm and this week's sessions; then the areas they sit in. A card says its area.
/// An area's card, its status and what's moving it. The plus beside Projects or Practices starts a new one; the pencil
/// beside Areas edits them in place: icons, names, removing one, adding one.
struct LifeHome: View {
    let firstName: String
    let goals: [Goal]
    /// Today, "YYYY-MM-DD".
    let today: String
    /// Each goal's week, by goal id. A goal without one (or a page without any) shows no week.
    var weeks: [String: GoalWeek] = [:]
    /// The person's areas, in order.
    var areas: [Area] = []
    var max = 12
    var error: String?
    /// For the greeting's part of the day; fixed in snapshots.
    var now = Date()
    var onOpen: (Goal) -> Void = { _ in }
    var onOpenArea: (Area) -> Void = { _ in }
    var onNew: (GoalInput) -> Void = { _ in }
    /// What a goal card's right-click menu offers besides opening it.
    var actions = GoalCardActions()
    /// What can change the areas; nil leaves them as they are (no pencil, no New area).
    var areaActions: AreaEditActions?
    /// Why the last change to an area didn't go through.
    var areaError: String?
    /// Opens with the areas being edited, and optionally a new one being named (snapshots).
    var startsEditingAreas = false
    var startsWithNewArea = false
    /// The person's seasons; nil leaves out the season panel.
    var seasons: CurrentSeasons?
    /// Opens starting a season, or picks up the one being set up.
    var onStartSeason: (() -> Void)?
    /// Opens the running season's page, or one of its quests'.
    var onOpenSeason: ((Season) -> Void)?
    var onOpenQuest: ((Quest) -> Void)?

    @State private var width: CGFloat = 1024
    /// Editing the areas; nil until the pencil or Done is pressed, then it follows them.
    @State private var editingAreas: Bool?
    /// A new area being named, until it's added or dropped; nil until New area is pressed.
    @State private var newArea: AreaInput?
    /// Whether the new area's icon has been picked yet (a plus shows until it has).
    @State private var newAreaIcon: String?
    /// Names being edited, by area id.
    @State private var names: [String: String] = [:]
    @Environment(\.overlays) private var overlays

    private var isEditingAreas: Bool { editingAreas ?? startsEditingAreas }
    private var draft: AreaInput? { newArea ?? (startsWithNewArea && editingAreas == nil ? AreaInput() : nil) }

    /// The web's grid: one column, two from 640pt (`sm`), three from 1024pt (`lg`).
    private var columns: Int { width >= 1024 ? 3 : width >= 640 ? 2 : 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // `text-5xl tracking-[-0.035em]`: one line, greeting the time of day.
                Text("Good \(Self.partOfDay(at: now)), \(firstName).")
                    .font(.app(48, .semibold))
                    .tracking(-0.035 * 48)
                    .foregroundStyle(Theme.foreground)

                // The season's place: the running one leads the page; with none, an invitation to start one.
                Group {
                    if let active = seasons?.active {
                        SeasonPanel(
                            season: active, areas: areas, goals: goals,
                            onOpenSeason: { onOpenSeason?(active) },
                            onOpenQuest: { onOpenQuest?($0) }
                        )
                    } else if let seasons, let onStartSeason {
                        NoSeasonPanel(draft: seasons.draft, ended: seasons.ended, onStart: onStartSeason)
                    }
                }
                .padding(.top, 40)
                .opacity(isEditingAreas ? 0.4 : 1)
                .allowsHitTesting(!isEditingAreas)

                Group {
                    projectsSection.padding(.top, 48)
                    if !(projects.isEmpty && practices.isEmpty) {
                        practicesSection.padding(.top, 48)
                    }
                }
                // While areas are edited, projects and practices step back.
                .opacity(isEditingAreas ? 0.4 : 1)
                .allowsHitTesting(!isEditingAreas)

                if !areas.isEmpty || areaActions != nil {
                    areasSection.padding(.top, 48)
                }
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

    // MARK: Projects and practices

    private var projects: [Goal] { seasonFirst(goals.filter { !$0.isPractice }) }
    private var practices: [Goal] { seasonFirst(goals.filter(\.isPractice)) }

    /// The goals the running season's quests move.
    private var seasonGoalIds: Set<String>? {
        seasons?.active.map { Set($0.chosen.flatMap(\.goalIds)) }
    }

    /// The season's own first, in their usual order, then the rest, in theirs.
    private func seasonFirst(_ list: [Goal]) -> [Goal] {
        guard let ids = seasonGoalIds else { return list }
        return list.filter { ids.contains($0.id) } + list.filter { !ids.contains($0.id) }
    }

    private func season(of goal: Goal) -> InSeason {
        guard let ids = seasonGoalIds else { return .none }
        return ids.contains(goal.id) ? .moving : .outside
    }

    private func season(of area: Area) -> InSeason {
        guard let active = seasons?.active else { return .none }
        return active.chosen.contains { $0.areaId == area.id } ? .moving : .outside
    }

    /// "morning" from 5:00 to 11:59, "afternoon" from 12:00 to 17:59, "evening" the rest of the night.
    static func partOfDay(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "morning"
        case 12..<18: "afternoon"
        default: "evening"
        }
    }

    /// A section's title row, the same for Projects, Practices and Areas: its title, then its button at the right,
    /// 36 tall over 12 of space.
    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack {
            Text(title).appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Spacer()
            trailing()
        }
        .frame(height: 36)
        .padding(.bottom, 12)
    }

    /// The plus beside Projects or Practices, while there's room for another of that kind.
    @ViewBuilder private func newButton(_ kind: GoalKind, count: Int) -> some View {
        if count < max {
            HeaderIconButton(icon: .add, label: kind == .practice ? "New practice" : "New project") {
                onNew(GoalInput(kind: kind))
            }
        }
    }

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let isEmpty = projects.isEmpty && practices.isEmpty
            // With nothing yet, the empty state below has its own ways to start.
            sectionHeader("Projects") {
                if !isEmpty { newButton(.project, count: projects.count) }
            }

            if let error {
                Banner(text: error, tone: .error).padding(.bottom, 16)
            }

            if isEmpty {
                EmptyGoals(onNew: onNew)
            } else {
                CardGrid(count: projects.count, columns: columns) { cell(projects[$0]) }
            }
        }
    }

    private var practicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Practices") { newButton(.practice, count: practices.count) }
            CardGrid(count: practices.count, columns: columns) { cell(practices[$0]) }
        }
    }

    @ViewBuilder private func cell(_ goal: Goal) -> some View {
        if goal.isPractice {
            PracticeCard(goal: goal, area: areas.first { $0.id == goal.areaId }, season: season(of: goal)) { onOpen(goal) }
                .contextPanel(owner: PracticeCard.menuOwner(goal), isEnabled: !goal.isPending) {
                    GoalCardMenu(goal: goal, actions: actions) { onOpen(goal) }
                }
        } else {
            GoalCard(
                goal: goal,
                week: weeks[goal.id],
                area: areas.first { $0.id == goal.areaId },
                season: season(of: goal),
                onSetObjective: actions.setObjective
            ) { onOpen(goal) }
                .contextPanel(owner: GoalCard.menuOwner(goal), isEnabled: !goal.isPending) {
                    GoalCardMenu(goal: goal, actions: actions) { onOpen(goal) }
                }
        }
    }

    // MARK: Areas

    private var areasSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Areas") {
                if areaActions != nil, !areas.isEmpty || isEditingAreas {
                    if isEditingAreas {
                        PrimaryButton(title: "Done", action: finishEditing)
                    } else {
                        HeaderIconButton(icon: .edit, iconSize: 15, label: "Edit areas") { editingAreas = true }
                    }
                }
            }

            if let areaError {
                Banner(text: areaError, tone: .error).padding(.bottom, 16)
            }

            if isEditingAreas, let areaActions {
                editingGrid(areaActions)
            } else if areas.isEmpty {
                // No areas yet: one quiet way to start.
                NewAreaTile { startNewArea() }
                    .frame(maxWidth: columns == 1 ? .infinity : 320)
            } else {
                CardGrid(count: areas.count, columns: columns) { index in
                    let area = areas[index]
                    AreaCard(area: area, goals: goals(in: area), season: season(of: area)) { onOpenArea(area) }
                }
            }
        }
    }

    private enum EditCell { case area(Area), draft, add }

    private func editingGrid(_ actions: AreaEditActions) -> some View {
        let cells: [EditCell] = areas.map { .area($0) }
            + (draft != nil ? [.draft] : [])
            + (draft == nil && areas.count < 12 ? [.add] : [])
        return CardGrid(count: cells.count, columns: columns) { index in
            switch cells[index] {
            case .area(let area):
                EditableAreaCard(
                    area: area,
                    goals: goals(in: area),
                    name: Binding(get: { names[area.id] ?? area.name }, set: { names[area.id] = $0 }),
                    onIcon: { icon in
                        var input = AreaInput(editing: area)
                        input.icon = icon
                        input.name = names[area.id] ?? area.name
                        actions.update?(area, input)
                    },
                    onCommitName: { commitName(of: area, actions) },
                    onRemove: { confirmRemove(area, actions) }
                )
            case .draft:
                NewAreaCard(
                    name: Binding(get: { draft?.name ?? "" }, set: { newArea = (draft ?? AreaInput()).with(name: $0) }),
                    icon: newAreaIcon,
                    onIcon: { newAreaIcon = $0 },
                    onCommit: { addNewArea(actions) },
                    onDrop: { dropNewArea() }
                )
            case .add:
                NewAreaTile { startNewArea() }
            }
        }
    }

    private func goals(in area: Area) -> [Goal] {
        area.goalIds.compactMap { id in goals.first { $0.id == id } }
    }

    private func startNewArea() {
        editingAreas = true
        newArea = AreaInput()
        newAreaIcon = nil
    }

    private func dropNewArea() {
        newArea = nil
        newAreaIcon = nil
        // Keep startsWithNewArea from bringing it back.
        if editingAreas == nil { editingAreas = isEditingAreas }
    }

    private func addNewArea(_ actions: AreaEditActions) {
        guard var input = draft, !input.name.trimmingCharacters(in: .whitespaces).isEmpty, let create = actions.create else { return }
        input.icon = newAreaIcon ?? AreaInput.defaultIcon
        Task {
            if await create(input) { dropNewArea() }
        }
    }

    private func commitName(of area: Area, _ actions: AreaEditActions) {
        guard let name = names[area.id], name != area.name else { return }
        var input = AreaInput(editing: area)
        input.name = name
        actions.update?(area, input)
        names[area.id] = nil
    }

    /// Done: names still being typed are saved, and a new area with a name is added.
    private func finishEditing() {
        if let actions = areaActions {
            for area in areas { commitName(of: area, actions) }
            if let draft, !draft.name.trimmingCharacters(in: .whitespaces).isEmpty { addNewArea(actions) } else { dropNewArea() }
        }
        editingAreas = false
    }

    private func confirmRemove(_ area: Area, _ actions: AreaEditActions) {
        guard let overlays else { return }
        overlays.showDialog {
            removeAreaDialog(area.name, onCancel: { overlays.dismiss() }) {
                overlays.dismiss()
                actions.remove?(area)
            }
        }
    }
}

/// What Life can do to areas: each nil leaves that out.
struct AreaEditActions {
    /// Adds an area; true once it's saved.
    var create: ((AreaInput) async -> Bool)?
    var update: ((Area, AreaInput) -> Void)?
    /// Removes it, once the person has said yes.
    var remove: ((Area) -> Void)?
}

extension AreaInput {
    func with(name: String) -> AreaInput {
        var copy = self
        copy.name = String(name.replacingOccurrences(of: "\n", with: " ").prefix(Self.maxName))
        return copy
    }
}

/// A section title's button, `size-8 rounded-lg border bg-card`: the plus beside Projects and Practices, the pencil
/// beside Areas.
private struct HeaderIconButton: View {
    let icon: Icon
    var iconSize: CGFloat = 16
    /// Its tooltip and what VoiceOver reads.
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.image(size: iconSize)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.8))
                .frame(width: 32, height: 32)
                .background(Theme.card, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// An area's card while editing: its icon a button for the picker, its name a field, a remove button where its
/// status was. Its goals stay as they are.
private struct EditableAreaCard: View {
    let area: Area
    let goals: [Goal]
    @Binding var name: String
    let onIcon: (String) -> Void
    let onCommitName: () -> Void
    let onRemove: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                AreaIconButton(icon: area.icon, onPick: onIcon)
                Spacer(minLength: 12)
                AreaRemoveButton(help: "Remove \(area.name)", action: onRemove)
            }
            AreaNameField(name: $name, placeholder: "Name this area", focused: $nameFocused, onCommit: onCommitName)
                .padding(.top, 12)
                .onChange(of: nameFocused) { _, focused in if !focused { onCommitName() } }

            Spacer(minLength: 20)

            AreaGoalsLine(goals: goals)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 148)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

/// A new area being named: its icon still to pick, its name focused. Return adds it; × drops it.
private struct NewAreaCard: View {
    @Binding var name: String
    let icon: String?
    let onIcon: (String) -> Void
    let onCommit: () -> Void
    let onDrop: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                AreaIconButton(icon: icon, onPick: onIcon)
                Spacer(minLength: 12)
                AreaRemoveButton(help: "Don’t add it", action: onDrop)
            }
            AreaNameField(name: $name, placeholder: "Name this area", focused: $nameFocused, onCommit: onCommit)
                .padding(.top, 12)
            Spacer(minLength: 20)
            Text("Add projects and practices from its page").appText(.xs).foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: 148)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        // A beat later than appearing: the card can appear with the other cards' fields, and macOS hands the
        // window's first field focus after onAppear, which would take it from this one.
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            nameFocused = true
        }
        .onEscape(perform: onDrop)
    }
}

/// An area's name as a field, on its card: the name's own type, in a box that darkens while typing.
private struct AreaNameField: View {
    @Binding var name: String
    let placeholder: String
    var focused: FocusState<Bool>.Binding
    let onCommit: () -> Void

    var body: some View {
        TextField("", text: Binding(get: { name }, set: { name = String($0.prefix(AreaInput.maxName)) }))
            .textFieldStyle(.plain)
            .font(.app(15.2, .semibold))
            .tracking(-0.01 * 15.2)
            .foregroundStyle(Theme.foreground)
            .placeholder(placeholder, when: name.isEmpty, font: .app(15.2, .medium))
            .focused(focused)
            .onSubmit(onCommit)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(focused.wrappedValue ? Theme.card : Theme.foreground(0.035), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused.wrappedValue ? Theme.foreground(0.6) : .clear, lineWidth: 1.5))
            .padding(.horizontal, -8)
    }
}

/// An area's projects then practices as their badges (a practice's round, a project's square), which say what's in
/// it without a count; an area with nothing in it says so.
private struct AreaGoalsLine: View {
    let goals: [Goal]

    private var ordered: [Goal] { goals.filter { !$0.isPractice } + goals.filter(\.isPractice) }

    var body: some View {
        if goals.isEmpty {
            Text("Nothing in it yet")
                .appText(.xs)
                .foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 6) {
                ForEach(ordered) { goal in
                    GoalBadge(goal: goal, size: .mini)
                }
            }
        }
    }
}

/// `min-h-[84px] rounded-2xl border border-dashed`: adds an area.
private struct NewAreaTile: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Icon.add.image(size: 18)
                Text("New area").appText(.sm, .medium)
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

/// Cards in rows of `columns`, each row as tall as its tallest card, a short last row keeping full-width cards.
private struct CardGrid<Content: View>: View {
    let count: Int
    let columns: Int
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: count, by: columns)), id: \.self) { start in
                GridRow(alignment: .top) {
                    ForEach(start..<min(start + columns, count), id: \.self) { index in
                        content(index)
                    }
                    // Keep a short last row's cards the same width as the rest.
                    ForEach(0..<(start + columns - min(start + columns, count)), id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

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
            // A practice has no tasks to plan and no read to update: it's counted.
            if let plan = actions.plan, !goal.isPractice {
                MenuItem(icon: .calendarSmall, title: "Plan tasks") { run { plan(goal) } }
            }
            if let updateStatus = actions.updateStatus, !goal.isPractice {
                MenuItem(icon: .refresh, title: "Update status") { run { updateStatus(goal) } }
            }
            if let edit = actions.edit {
                MenuSeparator()
                MenuItem(icon: .edit, title: "Edit \(goal.kind.noun)") { run { edit(goal) } }
            }
            if let delete = actions.delete {
                MenuItem(icon: .delete, title: "Delete \(goal.kind.noun)", isDestructive: true) { run { delete(goal) } }
            }
        }
    }

    private func run(_ action: () -> Void) {
        overlays?.dismiss()
        action()
    }
}

/// `rounded-2xl border bg-card p-5`, hover `border-line-strong`. Its badge with its status at the top right, the
/// title with this week's objective under it; pinned to the bottom, one footer line: its week's ring and what's free
/// or over, then its area at the right, so footers line up across a row.
struct GoalCard: View {
    let goal: Goal
    /// Its week; nil shows none.
    var week: GoalWeek?
    /// The area it sits in, if any.
    var area: Area?
    /// Whether it moves the running season: marked if so, a step dimmer if not.
    var season: InSeason = .none
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
                HStack(alignment: .center) {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .card).seasonMark(season == .moving)
                    Spacer(minLength: 12)
                    if let latest = goal.latest, let status = latest.status, let basis = latest.basis {
                        StatusText(status: status, basis: basis)
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                }

                Text(goal.title)
                    .font(.app(15.2, .semibold))
                    .tracking(-0.01 * 15.2)
                    .lineSpacing(15.2 * 0.375 - 15.2 * 0.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)
                if let week {
                    WeekObjectiveLine(week: week, onSet: onSetObjective.map { set in { set(goal) } })
                        .padding(.top, 4)
                }

                Spacer(minLength: 16)

                // One line, as a practice card's pips then area: its week on the left, its area on the right.
                HStack(spacing: 12) {
                    if let week {
                        WeekTimeLine(week: week, color: goal.color)
                    }
                    Spacer(minLength: 0)
                    if let area {
                        // A long week line ("4 h 30 min this week, nothing planned") gives way before the area's
                        // name, which says nothing once it's cut to a letter.
                        AreaLabel(name: area.name, icon: area.icon).layoutPriority(1)
                    }
                }
                .appText(.xs)
                .foregroundStyle(Theme.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(season.cardFill, in: .rect(cornerRadius: 16))
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

/// An area on Life, in the goal cards' shape: its tile with its status at the top right, its name, and pinned to the
/// bottom the goals moving it as their badges.
private struct AreaCard: View {
    let area: Area
    /// Its goals, in order.
    let goals: [Goal]
    /// With a season running: whether one of its quests is this area's.
    var season: InSeason = .none
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    AreaTile(icon: area.icon)
                    Spacer(minLength: 12)
                    AreaStatusText(status: area.status)
                }
                Text(area.name)
                    .font(.app(15.2, .semibold))
                    .tracking(-0.01 * 15.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .padding(.top, 12)
                if season == .moving {
                    HStack(spacing: 6) {
                        Icon.season.image(size: 11)
                        Text("In season")
                    }
                    .font(.app(12.5))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                }

                Spacer(minLength: 20)

                AreaGoalsLine(goals: goals)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 148)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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

/// The start of a project card's footer: its week's time. A ring in the goal's colour, then what's left of the
/// session time ("2 h free", "Just fits", or "30 min over" in amber); or the session time with nothing planned yet;
/// or, with no session time, the reserved time, or that there's none.
private struct WeekTimeLine: View {
    let week: GoalWeek
    let color: String

    var body: some View {
        HStack(spacing: 6) {
            CapacityRing(planned: week.sessionMinutes > 0 ? week.plannedMinutes : 0, protected: week.sessionMinutes, color: color, size: 14)
            if week.sessionMinutes > 0, week.plannedMinutes > 0 {
                Text(week.remaining < 0 ? "\(BoardDuration.text(-week.remaining)) over"
                     : week.remaining == 0 ? "Just fits" : "\(BoardDuration.text(week.remaining)) free")
                    .foregroundStyle(week.remaining < 0 ? Theme.amber : Theme.muted)
            } else {
                Text(emptyLine).foregroundStyle(Theme.muted)
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

/// For someone with nothing yet: a prompt, a project and a practice to start from, and a way to start either.
private struct EmptyGoals: View {
    let onNew: (GoalInput) -> Void

    private static let suggestions = [
        GoalInput(title: "Turn Supervibes into a world-class experience", icon: "SparklesIcon", color: "violet"),
        GoalInput(kind: .practice, title: "Work out", icon: "Dumbbell01Icon", color: "green", perWeek: 3),
    ]

    var body: some View {
        Card(padding: 32) {
            Text("What are you working toward?").appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
            Text("Add a handful of projects, things you’re finishing, and practices, things you keep up a few times a week. Start from scratch or pick one below.")
                .appText(.sm).foregroundStyle(Theme.muted)
                .frame(maxWidth: 448, alignment: .leading)
                .padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.title) { suggestion in
                    SuggestionRow(input: suggestion) { onNew(suggestion) }
                }
            }
            .padding(.top, 24)
            HStack(spacing: 8) {
                PrimaryButton(title: "New project", icon: .add) { onNew(GoalInput()) }
                GhostButton(title: "New practice") { onNew(GoalInput(kind: .practice)) }
            }
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
                    GoalBadge(icon: input.icon, color: input.color, round: input.kind == .practice)
                    Text(input.title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                    if input.kind == .practice {
                        RhythmLabel(perWeek: input.perWeek).appText(.xs).foregroundStyle(Theme.muted)
                    }
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

#Preview("Life") {
    LifeHome(firstName: "Javier", goals: Fixtures.lifeGoals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
             areas: Fixtures.areas, now: Fixtures.referenceNow, actions: GoalCardActions(setObjective: { _ in }))
        .background(Theme.background)
        .frame(width: 1180, height: 1300)
}

#Preview("No areas yet") {
    LifeHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
             now: Fixtures.referenceNow, actions: GoalCardActions(setObjective: { _ in }))
        .background(Theme.background)
        .frame(width: 1180, height: 900)
}

#Preview("No goals yet") {
    LifeHome(firstName: "Javier", goals: [], today: "2026-11-18", now: Fixtures.referenceNow)
        .background(Theme.background)
        .frame(width: 900, height: 760)
}
