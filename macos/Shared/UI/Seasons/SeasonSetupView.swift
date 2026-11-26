import SwiftUI

/// What starting a season can do; the app's SeasonSetupModel does each against the server.
struct SeasonSetupActions {
    /// Leaves the flow for Life; the draft keeps where it was.
    var close: () -> Void = {}
    var back: () -> Void = {}
    var togglePick: (AreaPick) -> Void = { _ in }
    /// Adds an area of the person's own naming to the picks.
    var addCustom: (String) -> Void = { _ in }
    /// Makes the picked new areas and goes on to where each stands.
    var continueAreas: () -> Void = {}
    /// Saves an area's words and reads where it stands.
    var read: (_ areaId: String, _ now: String, _ want: String) -> Void = { _, _, _ in }
    /// Rewrites a candidate quest's words; true once saved.
    var editQuest: (_ questId: String, _ title: String, _ fromText: String) async -> Bool = { _, _, _ in true }
    /// The next area, quest or step.
    var next: () -> Void = {}
    var choose: (_ questId: String, _ chosen: Bool) -> Void = { _, _ in }
    var toggleLink: (_ questId: String, _ goalId: String) -> Void = { _, _ in }
    var addSuggestion: (_ questId: String, QuestSuggestion) -> Void = { _, _ in }
    var removeSuggestion: (_ questId: String, QuestSuggestion) -> Void = { _, _ in }
    var findSuggestions: (_ questId: String) -> Void = { _ in }
    /// Starts a project or practice of the person's own for a quest, in its area.
    var newGoal: (_ questId: String, GoalKind) -> Void = { _, _ in }
    /// Renames the season or moves its days.
    var editSeason: () -> Void = {}
    var start: () -> Void = {}
}

/// Starting a season, a full page per step (supervibes-design, seasons-quests.tsx, the "Start season" row).
struct SeasonSetupView: View {
    let state: SeasonSetupState
    var actions = SeasonSetupActions()

    var body: some View {
        switch state.step {
        case .areas:
            ChooseAreasStep(state: state, actions: actions)
        case .stand(let index):
            if let area = state.pickedAreas[safe: index] {
                AreaStandStep(state: state, area: area, index: index, actions: actions).id(area.id)
            }
        case .focus:
            ChooseFocusStep(state: state, actions: actions)
        case .how(let index):
            if let quest = state.chosen[safe: index] {
                QuestHowStep(state: state, quest: quest, index: index, actions: actions).id(quest.id)
            }
        case .review:
            SeasonReviewStep(state: state, actions: actions)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// What the bar says when something didn't go through.
private struct FlowError: View {
    let text: String?
    var body: some View {
        if let text {
            Text(text).appText(.xs).foregroundStyle(Theme.danger).lineLimit(2).frame(maxWidth: 360, alignment: .leading)
        }
    }
}

// MARK: - 1. Choose your areas

/// Which areas of life to move: the person's, all picked to start, then the usual ones they don't have, dashed until
/// picked, and Add your own. Continue makes the new ones.
struct ChooseAreasStep: View {
    let state: SeasonSetupState
    let actions: SeasonSetupActions
    @State private var naming = false
    @State private var customName = ""
    @FocusState private var nameFocused: Bool

    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)

    var body: some View {
        SeasonFlow(
            eyebrow: "A new season",
            title: "What areas of your life do you want to move?",
            subtitle: "Select the areas that matter most to you over the course of the next few months.",
            onClose: actions.close
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your areas").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(state.areas) { area in
                        PickCard(
                            icon: area.icon, name: area.name, line: nil, goals: state.goals(in: area),
                            yours: true, picked: state.picked.contains(.area(area.id))
                        ) { actions.togglePick(.area(area.id)) }
                    }
                }
                .padding(.top, 12)

                Text("Popular areas").font(.app(13, .semibold)).foregroundStyle(Theme.foreground).padding(.top, 36)
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(state.popular, id: \.name) { popular in
                        PickCard(
                            icon: popular.icon, name: popular.name, line: popular.line, goals: [],
                            yours: false, picked: state.picked.contains(.popular(popular.name))
                        ) { actions.togglePick(.popular(popular.name)) }
                    }
                    ForEach(customNames, id: \.self) { name in
                        PickCard(icon: AreaInput.defaultIcon, name: name, line: "Yours, made when you continue.", goals: [],
                                 yours: false, picked: true) { actions.togglePick(.custom(name)) }
                    }
                    addYourOwn
                }
                .padding(.top, 12)
            }
        } footer: {
            Text("\(state.picked.count) \(state.picked.count == 1 ? "area" : "areas") selected")
                .font(.app(13, .medium)).monospacedDigit().foregroundStyle(Theme.foreground)
            FlowError(text: state.error).padding(.leading, 12)
            Spacer()
            FlowButton(title: "Continue", primary: true, isBusy: state.isBusy, isEnabled: !state.picked.isEmpty, action: actions.continueAreas)
        }
    }

    private var customNames: [String] {
        state.picked.compactMap { if case .custom(let name) = $0 { name } else { nil } }
    }

    @ViewBuilder private var addYourOwn: some View {
        if naming {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: $customName)
                    .textFieldStyle(.plain)
                    .font(.app(15.2, .semibold))
                    .placeholder("Name it", when: customName.isEmpty, font: .app(15.2, .semibold))
                    .focused($nameFocused)
                    .onSubmit(addCustom)
                    .onExitCommand { naming = false; customName = "" }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    FlowSmallButton(icon: .add, title: "Add", action: addCustom)
                    FlowLink(title: "Cancel", size: 12) { naming = false; customName = "" }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5))
        } else {
            DashedTile(icon: .add, title: "Add your own") {
                naming = true
                DispatchQueue.main.async { nameFocused = true }
            }
        }
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        actions.addCustom(String(name.prefix(AreaInput.maxName)))
        customName = ""
        naming = false
    }
}

/// An area to pick, as a card (the design's AreaPickCard): its tile and the tick, then its name and a line, or its
/// projects and practices for one of yours. Picked ones get an ink border; suggestions stay dashed until picked.
private struct PickCard: View {
    let icon: String
    let name: String
    let line: String?
    let goals: [Goal]
    let yours: Bool
    let picked: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if yours || picked {
                        AreaTile(icon: icon, size: 36)
                    } else {
                        GoalIconImage(name: icon, size: 18)
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                            .background(Theme.foreground(0.04), in: .rect(cornerRadius: 11))
                    }
                    Spacer()
                    PickMark(on: picked)
                }
                Spacer(minLength: 16)
                Text(name)
                    .font(.app(15.2, .semibold))
                    .tracking(-0.01 * 15.2)
                    .foregroundStyle(yours || picked ? Theme.foreground : Theme.foreground(0.8))
                    .lineLimit(1)
                if let line {
                    Text(line)
                        .font(.app(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } else if !goals.isEmpty {
                    GoalBadgeRow(goals: goals).padding(.top, 8)
                } else {
                    Text("Nothing in it yet").font(.app(13)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background {
                if picked || yours {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.card.opacity(0.6))
                }
            }
            .overlay {
                if picked {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5)
                } else if yours {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.foreground(isHovered ? 0.3 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// A dashed tile with an icon over its words, for adding.
private struct DashedTile: View {
    let icon: Icon
    let title: String
    var minHeight: CGFloat = 132
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon.image(size: 18)
                Text(title).font(.app(13, .medium))
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: minHeight)
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

// MARK: - 2. Where each area stands

/// One area at a time: where it is and where you want it to be, prefilled from the area and saved to it, then
/// Supervibes' read of them: the track to where you want to be, inked to where the season would leave you, the gap,
/// and what the season could reach. Reading is an action: Read the area, or Read again.
struct AreaStandStep: View {
    let state: SeasonSetupState
    let area: Area
    let index: Int
    let actions: SeasonSetupActions

    @State private var now: String
    @State private var want: String
    @State private var editing = false
    @State private var title = ""
    @State private var fromText = ""
    @State private var isSaving = false
    @FocusState private var focus: Int?

    init(state: SeasonSetupState, area: Area, index: Int, actions: SeasonSetupActions) {
        self.state = state
        self.area = area
        self.index = index
        self.actions = actions
        _now = State(initialValue: area.now ?? "")
        _want = State(initialValue: area.want ?? "")
    }

    private var areas: [Area] { state.pickedAreas }
    private var quest: Quest? { state.candidate(for: area.id) }
    private var reading: Bool { state.reading == area.id }
    private var bothSaid: Bool {
        !now.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !want.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// The words on screen are the ones the read was made from.
    private var upToDate: Bool { quest != nil && now == (area.now ?? "") && want == (area.want ?? "") }
    private var isLast: Bool { index == areas.count - 1 }

    var body: some View {
        SeasonFlow(
            eyebrow: "Area \(index + 1) of \(areas.count)",
            title: "Where does \(area.name) stand?",
            subtitle: "Say where it is today, and where you want it to be, however far off that is. A sentence or two each is plenty.",
            onClose: actions.close
        ) {
            VStack(alignment: .leading, spacing: 20) {
                StepTiles(tiles: areas.map { .init(id: $0.id, name: $0.name, icon: $0.icon) }, current: index)
                card
            }
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            FlowError(text: state.error).padding(.leading, 8)
            Spacer()
            if upToDate {
                Text(isLast ? "Next: choose your focus" : "Next: \(areas[index + 1].name)")
                    .font(.app(13)).foregroundStyle(Theme.muted).padding(.trailing, 8)
                FlowButton(title: isLast ? "Continue" : "Next area", primary: true, action: actions.next)
            } else {
                if !bothSaid {
                    Text("Say both to read it").font(.app(13)).foregroundStyle(Theme.muted).padding(.trailing, 8)
                }
                FlowButton(title: reading ? "Reading…" : (quest == nil ? "Read \(area.name)" : "Read again"), primary: true,
                           isBusy: reading, isEnabled: bothSaid) { actions.read(area.id, now, want) }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AreaTile(icon: area.icon, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.name).font(.app(17, .semibold)).tracking(-0.015 * 17).foregroundStyle(Theme.foreground)
                    let goals = state.goals(in: area)
                    if goals.isEmpty {
                        Text("No projects or practices yet").font(.app(12)).foregroundStyle(Theme.muted)
                    } else {
                        GoalBadgeRow(goals: goals)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Rectangle().fill(Theme.cardBorder).frame(height: 1)

            HStack(alignment: .top, spacing: 40) {
                side(0, hollow: true, label: "Where you are", text: $now, prompt: "Where does \(area.name) stand today?")
                side(1, hollow: false, label: "Where you want to be", text: $want, prompt: "Where do you want it to be, however far off?")
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)

            if let quest {
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                assessment(quest)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .background(Theme.foreground(0.025))
                    .compositingGroup()
                    .opacity(reading ? 0.5 : 1)
            } else if reading {
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                HStack(spacing: 8) {
                    SpinningIcon(size: 13)
                    Text("Reading your words and \(area.name)’s projects and practices. This takes a few seconds.")
                }
                .appText(.xs)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.foreground(0.025))
            }
        }
        .raisedPanel()
    }

    private func side(_ field: Int, hollow: Bool, label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if hollow {
                    Circle().strokeBorder(Theme.foreground(0.55), lineWidth: 1.5).frame(width: 12, height: 12)
                } else {
                    Circle().fill(Theme.foreground).frame(width: 12, height: 12)
                }
                CardLabel(label)
                if hollow {
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 400, y: 0))
                    }
                    .stroke(Theme.foreground(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                    .clipped()
                    .padding(.leading, 4)
                    .padding(.trailing, -34)
                }
            }
            .frame(height: 20)
            TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(AreaInput.maxWords)) }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(18, .medium))
                .tracking(-0.015 * 18)
                .lineSpacing(18 * 0.5 - 18 * 0.2)
                .foregroundStyle(Theme.foreground)
                .lineLimit(3...8)
                .placeholder(prompt, when: text.wrappedValue.isEmpty, font: .app(18, .medium))
                .focused($focus, equals: field)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(minHeight: 124, alignment: .topLeading)
                .background(focus == field ? Theme.card : Theme.foreground(0.03), in: .rect(cornerRadius: 16))
                .overlay {
                    if focus == field {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func assessment(_ quest: Quest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The track: today, the season's end part of the way, and where you want to be at the far end.
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Text(state.season.endLabel)
                        .font(.app(12, .semibold)).monospacedDigit().fixedSize()
                        .position(x: geometry.size.width * CGFloat(quest.reach) / 100, y: 8)
                }
                .frame(height: 16)
                ReachTrack(reach: quest.reach).frame(height: 24).padding(.top, 2)
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Text("Today").position(x: 14, y: 7)
                        Text("This season").fixedSize().position(x: geometry.size.width * CGFloat(quest.reach) / 200, y: 7)
                        Text("Where you want to be").fixedSize().position(x: geometry.size.width - 56, y: 7)
                    }
                }
                .frame(height: 14)
                .font(.app(11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
            }

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    CardLabel("The gap")
                    if let gap = area.gap {
                        Text(gap.title).font(.app(17, .semibold)).tracking(-0.015 * 17).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if !gap.body.isEmpty {
                            Text(gap.body).font(.app(14)).lineSpacing(14 * 0.55 - 14 * 0.2).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        CardLabel("By \(state.season.endLabel)")
                        Text("· \(quest.reachWords)").font(.app(11)).foregroundStyle(Theme.muted)
                    }
                    if editing {
                        questFields
                    } else {
                        Text(quest.title).font(.app(17, .semibold)).tracking(-0.015 * 17).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(quest.fromLine).font(.app(14)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 24)

            HStack(spacing: 8) {
                Text("Read from your words and \(area.name)’s projects and practices")
                    .appText(.xs).foregroundStyle(Theme.muted)
                Spacer()
                if editing {
                    FlowSmallButton(icon: .tick, title: isSaving ? "Saving…" : "Save", isBusy: isSaving) { saveQuest(quest) }
                    FlowLink(title: "Cancel", size: 12) { editing = false }
                } else {
                    FlowSmallButton(icon: .edit, title: "Edit") {
                        title = quest.title
                        fromText = quest.fromText
                        editing = true
                    }
                    if upToDate {
                        FlowSmallButton(icon: .refresh, title: reading ? "Reading…" : "Read again", isBusy: reading) {
                            actions.read(area.id, now, want)
                        }
                    }
                }
            }
            .padding(.top, 20)
        }
    }

    private var questFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            smallField($title, prompt: "Where it’s headed by \(state.season.endLabel)", size: 16, weight: .semibold, max: 120)
            smallField($fromText, prompt: "Where it starts", size: 14, weight: .regular, max: 160)
        }
    }

    private func smallField(_ text: Binding<String>, prompt: String, size: CGFloat, weight: Font.Weight, max: Int) -> some View {
        TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(max)) }), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.app(size, weight))
            .foregroundStyle(Theme.foreground)
            .lineLimit(1...3)
            .placeholder(prompt, when: text.wrappedValue.isEmpty, font: .app(size, weight))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
    }

    private func saveQuest(_ quest: Quest) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromText = fromText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !fromText.isEmpty else { return }
        isSaving = true
        Task {
            if await actions.editQuest(quest.id, title, fromText) { editing = false }
            isSaving = false
        }
    }
}

// MARK: - 3. Choose your focus

/// One possible quest per area, each the part of its gap the season could close; choose one to three, numbered in
/// the order chosen.
struct ChooseFocusStep: View {
    let state: SeasonSetupState
    let actions: SeasonSetupActions

    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        let chosen = state.chosen.count
        SeasonFlow(
            eyebrow: "Your season",
            title: "What will you focus on?",
            subtitle: "Choose up to three quests for the next three months.",
            onClose: actions.close
        ) {
            LazyVGrid(columns: grid, spacing: 12) {
                ForEach(state.candidates) { quest in
                    let number = quest.chosen ? (state.chosen.firstIndex { $0.id == quest.id }).map { $0 + 1 } : nil
                    QuestChoiceCard(
                        quest: quest, area: state.area(quest.areaId), end: state.season.endLabel, number: number,
                        isFull: chosen >= 3
                    ) { actions.choose(quest.id, !quest.chosen) }
                }
            }
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            FlowError(text: state.error).padding(.leading, 8)
            Spacer()
            Text("\(chosen) of 3 chosen").font(.app(13, .medium)).monospacedDigit().foregroundStyle(Theme.foreground).padding(.trailing, 8)
            FlowButton(title: "Continue", primary: true, isBusy: state.isBusy, isEnabled: (1...3).contains(chosen), action: actions.next)
        }
    }
}

/// A possible quest (the design's OpportunityCard): its area and its mark, its name, where it starts, and the
/// labelled timeline.
private struct QuestChoiceCard: View {
    let quest: Quest
    let area: Area?
    let end: String
    let number: Int?
    /// Three are chosen already: one more can't be.
    let isFull: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var on: Bool { number != nil }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let area {
                        HStack(spacing: 6) {
                            GoalIconImage(name: area.icon, size: 14)
                            Text(area.name)
                        }
                        .font(.app(13))
                        .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    PickMark(on: on, number: number)
                }
                Text(quest.title)
                    .font(.app(19, .semibold))
                    .tracking(-0.02 * 19)
                    .lineSpacing(19 * 0.3 - 19 * 0.2)
                    .foregroundStyle(on ? Theme.foreground : Theme.foreground(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(quest.fromLine)
                    .font(.app(13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Spacer(minLength: 24)
                ReachArt(reach: quest.reach, end: end, on: on)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(on ? Theme.foreground : (isHovered ? Theme.lineStrong : Theme.cardBorder), lineWidth: on ? 1.5 : 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 14, y: 12)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .inactive(!on && isFull)
        .onHover { isHovered = $0 }
        .help(!on && isFull ? "Three are chosen. Let one go to choose this one." : "")
    }
}

// MARK: - 4. How each quest moves

/// One quest at a time: what you'll take on to move it. The quest as it was chosen, then Projects and Practices side
/// by side: what's already in its area to tick, then suggestions to add, and your own.
struct QuestHowStep: View {
    let state: SeasonSetupState
    let quest: Quest
    let index: Int
    let actions: SeasonSetupActions

    private var chosen: [Quest] { state.chosen }
    private var area: Area? { state.area(quest.areaId) }
    private var linked: [String] { state.linked[quest.id] ?? quest.goalIds }
    private var added: [QuestSuggestion] { state.added[quest.id] ?? [] }
    private var isLast: Bool { index == chosen.count - 1 }
    private var canGoOn: Bool { !linked.isEmpty || !added.isEmpty }

    var body: some View {
        SeasonFlow(
            eyebrow: "Quest \(index + 1) of \(chosen.count)",
            title: "What will you take on for it?",
            subtitle: "Projects get you somewhere; practices keep you going. Link what’s already in \(area?.name ?? "its area"), take a suggestion, or start your own.",
            onClose: actions.close
        ) {
            VStack(alignment: .leading, spacing: 0) {
                StepTiles(tiles: chosen.map { .init(id: $0.id, name: $0.title, icon: nil) }, current: index, showsCount: false)

                HStack(alignment: .bottom, spacing: 40) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let area {
                            HStack(spacing: 6) {
                                GoalIconImage(name: area.icon, size: 14)
                                Text(area.name)
                            }
                            .font(.app(13)).foregroundStyle(Theme.muted)
                        }
                        Text(quest.title)
                            .font(.app(24, .semibold)).tracking(-0.025 * 24)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                        Text(quest.fromLine).font(.app(14)).foregroundStyle(Theme.muted).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ReachArt(reach: quest.reach, end: state.season.endLabel).frame(width: 360)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .raisedPanel()
                .padding(.top, 20)

                HStack(alignment: .top, spacing: 32) {
                    column(.project)
                    column(.practice)
                }
                .padding(.top, 32)
            }
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            FlowError(text: state.error).padding(.leading, 8)
            Spacer()
            Text(!canGoOn ? "Link or add at least one" : isLast ? "Next: review your season" : "Next: \(chosen[index + 1].title)")
                .font(.app(13)).foregroundStyle(Theme.muted).lineLimit(1).padding(.trailing, 8)
            FlowButton(title: isLast ? "Review" : "Next quest", primary: true, isBusy: state.isBusy, isEnabled: canGoOn, action: actions.next)
        }
    }

    @ViewBuilder private func column(_ kind: GoalKind) -> some View {
        let mine = (area.map { state.goals(in: $0) } ?? []).filter { $0.kind == kind }
        // Ones linked from elsewhere (made here, or moved from another area) show too.
        let others = linked.compactMap { id in state.goals.first { $0.id == id } }.filter { $0.kind == kind && !mine.contains($0) }
        let addedHere = added.filter { $0.kind == kind }
        let suggestions = (state.suggestions[quest.id] ?? []).filter { s in s.kind == kind && !added.contains(s) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(kind == .project ? "Projects" : "Practices").font(.app(15, .semibold)).tracking(-0.01 * 15).foregroundStyle(Theme.foreground)
                Text(kind == .project ? "Something to finish" : "Something to keep up").font(.app(13)).foregroundStyle(Theme.muted)
            }
            VStack(spacing: 8) {
                ForEach(mine + others) { goal in
                    HowGoalRow(goal: goal, line: line(for: goal), linked: linked.contains(goal.id), isNew: state.created.contains(goal.id)) {
                        actions.toggleLink(quest.id, goal.id)
                    }
                }
                ForEach(addedHere, id: \.self) { suggestion in
                    HowSuggestionRow(suggestion: suggestion, added: true) { actions.removeSuggestion(quest.id, suggestion) }
                }
                if mine.isEmpty && others.isEmpty && addedHere.isEmpty {
                    Text(kind == .project ? "None in \(area?.name ?? "this area") yet." : "None kept up in \(area?.name ?? "this area") yet.")
                        .font(.app(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .padding(.top, 12)

            CardLabel("Suggested for this quest").padding(.top, 20)
            VStack(spacing: 8) {
                if state.findingSuggestions.contains(quest.id) {
                    HStack(spacing: 8) {
                        SpinningIcon(size: 13)
                        Text("Finding a few that fit…")
                    }
                    .font(.app(13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                } else if let error = state.suggestionErrors[quest.id] {
                    HStack(spacing: 8) {
                        Text(error).appText(.xs).foregroundStyle(Theme.danger)
                        Spacer()
                        FlowSmallButton(icon: .refresh, title: "Try again") { actions.findSuggestions(quest.id) }
                    }
                    .padding(.vertical, 8)
                } else if state.suggestions[quest.id] == nil {
                    FlowSmallButton(icon: .route, title: "Suggest a few") { actions.findSuggestions(quest.id) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if suggestions.isEmpty {
                    Text("Nothing more to suggest.").font(.app(13)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    HowSuggestionRow(suggestion: suggestion, added: false) { actions.addSuggestion(quest.id, suggestion) }
                }
                FlowLink(icon: .add, title: kind == .project ? "New project" : "New practice") { actions.newGoal(quest.id, kind) }
                    .frame(height: 44)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(for goal: Goal) -> String {
        // Linked to another of this season's quests: ticking it here moves it.
        if let other = chosen.first(where: { $0.id != quest.id && (state.linked[$0.id] ?? $0.goalIds).contains(goal.id) }) {
            return "Moves \(other.title) now"
        }
        if let practice = goal.practice { return Practice.rhythm(practice.perWeek) }
        if let target = goal.targetDate { return "By \(CalendarDay.format(target, today: state.today))" }
        return goal.areaId == quest.areaId ? "In \(area?.name ?? "this area")" : "Project"
    }
}

/// A project or practice to link: a card with its badge and a tick; ringed in ink when linked.
private struct HowGoalRow: View {
    let goal: Goal
    let line: String
    let linked: Bool
    let isNew: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .card, round: goal.isPractice)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(goal.title).font(.app(14, .semibold)).tracking(-0.01 * 14).foregroundStyle(Theme.foreground).lineLimit(1)
                        if isNew { NewPill() }
                    }
                    Text(line).font(.app(12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                PickMark(on: linked)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(linked ? Theme.foreground : (isHovered ? Theme.lineStrong : Theme.cardBorder), lineWidth: linked ? 1.5 : 1)
            )
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A suggestion: dashed with Add until added; then a linked card marked New, made when the step is left.
private struct HowSuggestionRow: View {
    let suggestion: QuestSuggestion
    let added: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if added {
                    GoalBadge(icon: suggestion.icon, color: suggestion.color, size: .card, round: suggestion.kind == .practice)
                } else {
                    GoalIconImage(name: suggestion.icon, size: 16)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .background(Theme.foreground(0.04), in: suggestion.kind == .practice ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: 10)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(suggestion.title).font(.app(14, .semibold)).tracking(-0.01 * 14)
                            .foregroundStyle(added ? Theme.foreground : Theme.foreground(0.8)).lineLimit(1)
                        if added { NewPill() }
                    }
                    Text(lineText).font(.app(12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                if added {
                    PickMark(on: true)
                } else {
                    HStack(spacing: 4) {
                        Icon.add.image(size: 12)
                        Text("Add").font(.app(12, .medium))
                    }
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.card, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(added ? Theme.card : .clear, in: .rect(cornerRadius: 16))
            .overlay {
                if added {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.foreground(isHovered ? 0.3 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(added ? "Take it back out" : "Add it to this quest; it’s made when you continue")
    }

    private var lineText: String {
        if suggestion.kind == .practice, let perWeek = suggestion.perWeek {
            return "\(Practice.rhythm(perWeek)) · \(suggestion.line)"
        }
        return suggestion.line
    }
}

// MARK: - 5. Review

/// The whole season on one panel, shaped like Life's season panel, so what you start is what you'll see: its name,
/// days and weeks, then a column per quest with its timeline and what moves it.
struct SeasonReviewStep: View {
    let state: SeasonSetupState
    let actions: SeasonSetupActions

    private var season: Season { state.season }

    var body: some View {
        SeasonFlow(
            eyebrow: "Your season",
            title: "Ready for \(season.name)?",
            subtitle: "\(numberWord(state.chosen.count).capitalized) \(state.chosen.count == 1 ? "quest" : "quests"), and what you’ll take on for each. You can change what moves them once it’s running.",
            onClose: actions.close
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Icon.season.image(size: 15).foregroundStyle(Theme.muted)
                        Text("Your next season").font(.app(13, .medium)).foregroundStyle(Theme.muted)
                        Spacer()
                        FlowLink(icon: .edit, title: "Rename or change dates", size: 12, action: actions.editSeason)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(season.name).font(.app(32, .semibold)).tracking(-0.03 * 32).foregroundStyle(Theme.foreground)
                        Text("\(season.range) · \(season.weeks) weeks").font(.app(15)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 4)
                    HStack(spacing: 4) {
                        ForEach(0..<season.weeks, id: \.self) { _ in
                            Capsule().fill(Theme.foreground(0.08)).frame(height: 6)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 24)

                Rectangle().fill(Theme.cardBorder).frame(height: 1)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(state.chosen.enumerated()), id: \.element.id) { index, quest in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(width: 1) }
                        column(quest, number: index + 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .raisedPanel()
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            FlowError(text: state.error).padding(.leading, 8)
            Spacer()
            Text(startsLine).font(.app(13)).foregroundStyle(Theme.muted).padding(.trailing, 8)
            FlowButton(title: "Start season", primary: true, isBusy: state.isBusy, action: actions.start)
        }
    }

    private var startsLine: String {
        season.startsOn <= state.today ? "Starts today" : "Starts \(CalendarDay.weekdayMonthDay(season.startsOn))"
    }

    private func column(_ quest: Quest, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(number)").font(.app(11, .semibold)).monospacedDigit().foregroundStyle(Theme.background)
                    .frame(width: 20, height: 20).background(Theme.foreground, in: .rect(cornerRadius: 6))
                if let area = state.area(quest.areaId) {
                    GoalIconImage(name: area.icon, size: 14)
                    Text(area.name)
                }
            }
            .font(.app(13)).foregroundStyle(Theme.muted)
            Text(quest.title)
                .font(.app(19, .semibold)).tracking(-0.02 * 19)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text(quest.fromLine).font(.app(13.5)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 6)
            ReachArt(reach: quest.reach, end: season.endLabel).padding(.top, 24)
            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.top, 24)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.linkedGoals(quest)) { goal in
                    HStack(spacing: 10) {
                        GoalBadge(icon: goal.icon, color: goal.color, size: .card, round: goal.isPractice)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(goal.title).font(.app(13.5, .medium)).tracking(-0.01 * 13.5).foregroundStyle(Theme.foreground).lineLimit(1)
                            HStack(spacing: 6) {
                                if let practice = goal.practice {
                                    Icon.repeats.image(size: 11)
                                    Text(Practice.rhythm(practice.perWeek))
                                } else if let target = goal.targetDate {
                                    Text("Project · by \(CalendarDay.format(target, today: state.today))")
                                } else {
                                    Text("Project")
                                }
                                if state.created.contains(goal.id) { NewPill() }
                            }
                            .font(.app(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func numberWord(_ n: Int) -> String {
        switch n {
        case 1: "one"
        case 2: "two"
        case 3: "three"
        default: "\(n)"
        }
    }
}
