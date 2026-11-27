import SwiftUI

/// What Route 3's screens can do, wired to FirstRunModel (and through it SeasonSetupModel) in the app, and to nothing
/// in previews and tests.
struct StepBackActions {
    var back: () -> Void = {}
    /// An area picked or left out on the first step.
    var toggleArea: (AreaPick) -> Void = { _ in }
    var continueAreas: () -> Void = {}
    /// An area's words saved and its gap named: area id, where it is, where they want it.
    var read: (String, String, String) -> Void = { _, _, _ in }
    /// On from an area that's read, or from the quests chosen.
    var next: () -> Void = {}
    /// A quest chosen or taken out.
    var choose: (String, Bool) -> Void = { _, _ in }
    /// A project or practice linked to a quest, or unlinked: quest id, goal id.
    var toggleLink: (String, String) -> Void = { _, _ in }
    /// Something new for a quest, made on Continue; or taken back off.
    var addNew: (String, QuestSuggestion) -> Void = { _, _ in }
    var removeNew: (String, QuestSuggestion) -> Void = { _, _ in }
    var continueMoves: () -> Void = {}
    /// A quest renamed on its card.
    var rename: (String, String) -> Void = { _, _ in }
    var start: () -> Void = {}
}

/// Route 3, step back first: Start a season's steps, fed by the plate, in first run's frame. Which areas to look at,
/// where each stands, the gaps as quests, what moves each, and the season.
struct FirstRunStepBack: View {
    let state: SeasonSetupState
    /// Quests renamed on the season's cards, not saved yet.
    var names: [String: String] = [:]
    var isStarted = false
    var actions = StepBackActions()

    var body: some View {
        switch state.step {
        case .areas:
            StepBackAreas(state: state, actions: actions)
        case .stand(let index):
            if let area = state.pickedAreas[safe: index] {
                StepBackStand(state: state, index: index, area: area, actions: actions).id(area.id)
            }
        case .focus:
            StepBackQuests(state: state, actions: actions)
        case .how:
            StepBackMoves(state: state, actions: actions)
        case .review:
            FirstRunSeasonReview(
                cards: state.seasonCards, season: state.span,
                subtitle: FirstRunSeasonReview.gapSubtitle(count: state.chosen.count, season: state.span),
                rest: state.seasonRest, steps: FirstRunChoice.stepBack.steps, step: 4,
                name: { id in names[id] ?? state.season.quests.first { $0.id == id }?.title ?? "" },
                isStarting: state.isBusy, isStarted: isStarted, error: state.error,
                onRename: actions.rename, onBack: actions.back, onStart: actions.start
            )
        }
    }
}

// MARK: - Areas

/// Which parts of life to look at (the design's "Areas"), in the Focus step's language: their areas from the plate,
/// then two usual ones they don't have yet, worth a look.
private struct StepBackAreas: View {
    let state: SeasonSetupState
    let actions: StepBackActions

    private var count: Int { state.picked.count }

    var body: some View {
        FirstRunFlow(
            step: 3,
            steps: FirstRunChoice.stepBack.steps,
            eyebrow: "Areas",
            title: "Which parts of your life do you want to look at?",
            subtitle: "Your areas come from what you listed. Add any others worth a look; you don’t need all of them."
        ) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(state.areas) { area in
                        let pick = AreaPick.area(area.id)
                        AreaPickCard(
                            name: area.name, icon: area.icon, color: state.color(of: area),
                            picked: state.picked.contains(pick), badges: state.goals(in: area).map(\.badge)
                        ) { actions.toggleArea(pick) }
                    }
                    ForEach(state.offered, id: \.name) { popular in
                        let pick = AreaPick.popular(popular.name)
                        AreaPickCard(
                            name: popular.name, icon: popular.icon, color: SeasonSetupState.color(named: popular.name),
                            picked: state.picked.contains(pick), line: popular.line.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        ) { actions.toggleArea(pick) }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error = state.error {
                Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack)).padding(.trailing, 8)
            }
            Text("\(count) area\(count == 1 ? "" : "s")").font(.app(13, .medium)).monospacedDigit().padding(.trailing, 8)
            FlowButton(title: "Continue", primary: true, isBusy: state.isBusy, isEnabled: count > 0, action: actions.continueAreas)
        }
    }
}

/// An area to look at: picked, a wash in its colour holding its icon and what's in it, ticked and ringed in ink; not
/// picked, grey. One they don't have yet is dashed until picked, and says it's worth a look and what it covers.
private struct AreaPickCard: View {
    let name: String
    let icon: String
    let color: String
    let picked: Bool
    var badges: [PlateBadge] = []
    /// For one they don't have yet: what it covers.
    var line: String?
    let onToggle: () -> Void

    private var yours: Bool { line == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(picked ? GoalPalette.tintBackground(color) : Theme.foreground(0.03))
                GoalIconImage(name: icon, size: 19)
                    .foregroundStyle(picked ? GoalPalette.color(color) : Theme.muted)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.card).shadow(color: .black.opacity(0.1), radius: 5, y: 3)
                    }
                    .padding(12)
                Tick(on: picked)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(12)
                Group {
                    if yours {
                        HStack(spacing: -4) {
                            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                                // Overlapping, ringed in white, on a solid base so neither the wash nor the badge under
                                // it shows through.
                                GoalBadge(icon: badge.icon, color: badge.color, size: .xs, round: badge.isPractice)
                                    .scaleEffect(22.0 / 24.0)
                                    .frame(width: 22, height: 22)
                                    .opacity(picked ? 1 : 0.6)
                                    .background(Theme.card, in: .rect(cornerRadius: badge.isPractice ? 11 : 6))
                                    .padding(2)
                                    .background(Theme.card, in: .rect(cornerRadius: badge.isPractice ? 13 : 8))
                            }
                        }
                    } else {
                        Text("Worth a look").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.card.opacity(0.8), in: .capsule)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                .padding(12)
            }
            .frame(height: 116)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground)
                // Room for two lines on every card, so the line never truncates and every card is the same height.
                Text(line ?? "\(badges.count) \(badges.count == 1 ? "thing" : "things") on your plate")
                    .font(.app(12)).lineSpacing(2).foregroundStyle(Theme.muted)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 8)
            .opacity(picked ? 1 : 0.7)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(yours || picked ? Theme.card : .clear)
                .shadow(color: .black.opacity(picked ? 0.08 : 0), radius: 14, y: 12)
        }
        .overlay {
            if picked {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5)
            } else if yours {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder)
            } else {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture(perform: onToggle)
    }
}

/// Picked: a tick in ink. Not: an empty ring.
private struct Tick: View {
    let on: Bool

    var body: some View {
        if on {
            Icon.tickBold.image(size: 12).foregroundStyle(Theme.background)
                .frame(width: 24, height: 24).background(Theme.foreground, in: .circle)
        } else {
            Circle().fill(Theme.card.opacity(0.6)).overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5))
                .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Where each stands

/// One area at a time (the design's "Areas · Where it stands"): where it is today and where they want it, then the
/// gap Supervibes names between them, with what this season could do and its track.
private struct StepBackStand: View {
    let state: SeasonSetupState
    let index: Int
    let area: Area
    let actions: StepBackActions
    @State private var now: String
    @State private var want: String

    init(state: SeasonSetupState, index: Int, area: Area, actions: StepBackActions) {
        self.state = state
        self.index = index
        self.area = area
        self.actions = actions
        _now = State(initialValue: area.now ?? "")
        _want = State(initialValue: area.want ?? "")
    }

    private var color: String { state.color(of: area) }
    private var quest: Quest? { state.candidate(for: area.id) }
    private var isReading: Bool { state.reading == area.id }
    /// Read, and the words haven't changed since.
    private var isRead: Bool {
        quest != nil && area.gap != nil && trimmed(now) == (area.now ?? "") && trimmed(want) == (area.want ?? "")
    }
    private var isLast: Bool { index == state.pickedAreas.count - 1 }

    var body: some View {
        FirstRunFlow(
            step: 3,
            steps: FirstRunChoice.stepBack.steps,
            eyebrow: "Areas",
            title: "Where does \(area.name) stand?",
            subtitle: "Say where it is today, and where you want it to be, however far off. A sentence or two each is plenty."
        ) {
            VStack(alignment: .leading, spacing: 0) {
                AreaSteps(state: state, current: index)
                HStack(alignment: .top, spacing: 16) {
                    field("Where it is today", text: $now, solid: false, prompt: "What it’s like now, honestly")
                    field("Where you want it to be", text: $want, solid: true, prompt: "Where you’d like it to get, however far off")
                }
                .padding(.top, 20)
                gap.padding(.top, 16)
            }
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error = state.error {
                Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack)).padding(.trailing, 8)
            }
            if isRead {
                FlowButton(title: isLast ? "Continue" : "Next area", primary: true, action: actions.next)
            } else {
                FlowButton(
                    title: isReading ? "Naming the gap" : quest == nil ? "Name the gap" : "Name it again", primary: true,
                    isBusy: isReading, isEnabled: !trimmed(now).isEmpty && !trimmed(want).isEmpty
                ) { actions.read(area.id, trimmed(now), trimmed(want)) }
            }
        }
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func field(_ label: String, text: Binding<String>, solid: Bool, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(GoalPalette.color(color), lineWidth: solid ? 0 : 1.5)
                    .background(Circle().fill(solid ? GoalPalette.color(color) : .clear))
                    .frame(width: 10, height: 10)
                Text(label).font(.app(12.5, .semibold)).foregroundStyle(Theme.muted)
            }
            TextField("", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(16, .medium)).tracking(-0.16).lineSpacing(5)
                .foregroundStyle(Theme.foreground)
                .lineLimit(3...5)
                .placeholder(prompt, when: text.wrappedValue.isEmpty, font: .app(16, .medium))
                .frame(minHeight: 72, alignment: .topLeading)
        }
        .padding(16).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    /// The gap, once named: its title, what this season could do, and its track. Before, what it will be.
    @ViewBuilder private var gap: some View {
        if let gap = area.gap, let quest {
            HStack(alignment: .center, spacing: 40) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("The gap").font(.app(12.5, .semibold)).foregroundStyle(GoalPalette.color(color))
                    Text(gap.title).font(.app(19, .semibold)).tracking(-0.3).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    Text(gap.body.isEmpty ? "By \(state.season.endLabel) this season could get as far as: \(quest.title)." : gap.body)
                        .font(.app(13)).lineSpacing(3).foregroundStyle(Theme.foreground(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 500, alignment: .leading).padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GapTrack(
                    reach: quest.reach, color: color, end: state.season.endLabel,
                    from: state.goals(in: area).first?.badge, labels: true
                )
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 14)
                .background(Theme.card.opacity(0.7), in: .rect(cornerRadius: 12))
                .frame(width: 340)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 16))
            .opacity(isRead ? 1 : 0.5)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("The gap").font(.app(12.5, .semibold)).foregroundStyle(Theme.muted)
                Text(isReading
                     ? "Naming the gap between them, and what this season could do…"
                     : "Once you’ve said both, Supervibes names the gap between them, and how far this season could take it.")
                    .font(.app(13)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(.horizontal, 24)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }
}

/// Where they are in the areas: the ones done ticked in their colour, the current one named in an ink ring, the rest
/// to come.
private struct AreaSteps: View {
    let state: SeasonSetupState
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.pickedAreas.enumerated()), id: \.element.id) { index, area in
                let color = state.color(of: area)
                if index == current {
                    HStack(spacing: 8) {
                        GoalIconImage(name: area.icon, size: 13)
                            .foregroundStyle(GoalPalette.color(color))
                            .frame(width: 24, height: 24)
                            .background(GoalPalette.tintBackground(color), in: .circle)
                        Text(area.name).font(.app(12.5, .semibold)).foregroundStyle(Theme.foreground)
                    }
                    .padding(.leading, 4).padding(.trailing, 12).frame(height: 32)
                    .background(Theme.card, in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.foreground, lineWidth: 1.5))
                    .fixedSize()
                } else if index < current {
                    Icon.tickBold.image(size: 12)
                        .foregroundStyle(GoalPalette.color(color))
                        .frame(width: 32, height: 32)
                        .background(GoalPalette.tintBackground(color), in: .circle)
                        .help(area.name)
                } else {
                    GoalIconImage(name: area.icon, size: 14)
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Theme.cardBorder))
                        .help(area.name)
                }
            }
            Text("\(current + 1) of \(state.pickedAreas.count)")
                .font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
                .padding(.leading, 6)
        }
    }
}

// MARK: - Quests

/// Each gap named, as a quest this season could take on (the design's "Quests"): choose up to three.
private struct StepBackQuests: View {
    let state: SeasonSetupState
    let actions: StepBackActions

    var body: some View {
        FirstRunFlow(
            step: 4,
            steps: FirstRunChoice.stepBack.steps,
            eyebrow: "Quests · \(state.season.range)",
            title: "What will you focus on?",
            subtitle: "Each gap you named could become a quest. Choose up to three; the rest wait with their areas."
        ) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(state.candidates) { quest in
                        if let area = state.area(quest.areaId) {
                            OpportunityTile(
                                quest: quest, area: area, color: state.color(of: area), end: state.season.endLabel,
                                canChoose: quest.chosen || state.chosen.count < FocusBoard.slots
                            ) { actions.choose(quest.id, !quest.chosen) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error = state.error {
                Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack)).padding(.trailing, 8)
            }
            Text("\(state.chosen.count) of \(FocusBoard.slots) chosen")
                .font(.app(13, .medium)).monospacedDigit()
                .foregroundStyle(state.chosen.isEmpty ? Theme.muted : Theme.foreground)
                .padding(.trailing, 8)
            FlowButton(title: "Continue", primary: true, isEnabled: !state.chosen.isEmpty, action: actions.next)
        }
    }
}

/// A gap that could be a quest: chosen, it takes its area's wash, a number and an ink ring; not, it stays grey with
/// an empty ring. Its track shows how much of the gap this season could close.
private struct OpportunityTile: View {
    let quest: Quest
    let area: Area
    let color: String
    let end: String
    let canChoose: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(quest.chosen ? GoalPalette.tintBackground(color) : Theme.foreground(0.03))
                HStack(spacing: 6) {
                    GoalIconImage(name: area.icon, size: 13)
                    Text(area.name).font(.app(12))
                }
                .foregroundStyle(quest.chosen ? Theme.foreground(0.65) : Theme.muted)
                .padding(12)
                Group {
                    if quest.chosen {
                        Text("\(quest.position)")
                            .font(.app(12, .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.background)
                            .frame(width: 24, height: 24)
                            .background(Theme.foreground, in: .circle)
                    } else {
                        Circle().fill(Theme.card.opacity(0.6)).overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5))
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(12)
                GapTrack(reach: quest.reach, color: quest.chosen ? color : nil, end: end)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
            .frame(height: 104)
            VStack(alignment: .leading, spacing: 2) {
                Text(quest.title).font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground)
                    .lineLimit(2, reservesSpace: true)
                Text("From \(quest.fromText.lowercasedFirst)").font(.app(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 6)
            .opacity(quest.chosen ? 1 : 0.7)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                .shadow(color: .black.opacity(quest.chosen ? 0.08 : 0), radius: 14, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(quest.chosen ? Theme.foreground : Theme.cardBorder, lineWidth: quest.chosen ? 1.5 : 1)
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { if canChoose { onToggle() } }
        .opacity(canChoose ? 1 : 0.6)
    }
}

// MARK: - What moves each

/// How each chosen quest will move (the design's "Quests · Moved by"): its card, then the projects and practices that
/// move it. What's on the plate in its area is linked to begin with; where there's nothing, a suggestion, marked New.
private struct StepBackMoves: View {
    let state: SeasonSetupState
    let actions: StepBackActions

    var body: some View {
        FirstRunFlow(
            step: 4,
            steps: FirstRunChoice.stepBack.steps,
            eyebrow: "Quests · \(state.season.range)",
            title: "How will you move each forward?",
            subtitle: "Give each quest the projects and practices that move it. Add what’s missing."
        ) {
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(state.chosen) { quest in
                        if let area = state.area(quest.areaId) {
                            MoverCard(state: state, quest: quest, area: area, actions: actions)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<max(0, FocusBoard.slots - state.chosen.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .padding(.bottom, 200)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error = state.error {
                Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack)).padding(.trailing, 8)
            }
            Text("\(state.readyCount) of \(state.chosen.count) ready")
                .font(.app(13, .medium)).monospacedDigit()
                .padding(.trailing, 8)
            FlowButton(
                title: "Continue", primary: true, isBusy: state.isBusy,
                isEnabled: state.readyCount == state.chosen.count && !state.chosen.isEmpty, action: actions.continueMoves
            )
        }
    }
}

private struct MoverCard: View {
    let state: SeasonSetupState
    let quest: Quest
    let area: Area
    let actions: StepBackActions
    @State private var isAdding = false
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var color: String { state.color(of: area) }
    private var linked: [Goal] { state.linkedGoals(quest) }
    private var added: [QuestSuggestion] { state.added[quest.id] ?? [] }

    /// What else on the plate could move it: not linked here, nor moving another chosen quest, matching the search.
    private var options: [Goal] {
        let elsewhere = Set(state.chosen.filter { $0.id != quest.id }.flatMap { state.linkedGoals($0).map(\.id) })
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        return state.goals.filter { goal in
            !linked.contains { $0.id == goal.id } && !elsewhere.contains(goal.id)
                && (term.isEmpty || goal.title.lowercased().contains(term))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(GoalPalette.tintBackground(color))
                QuestPill(number: quest.position).padding(12)
                HStack(spacing: 6) {
                    GoalIconImage(name: area.icon, size: 13)
                    Text(area.name).font(.app(12))
                }
                .foregroundStyle(Theme.foreground(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 14).padding(.trailing, 14)
                GapTrack(reach: quest.reach, color: color, end: state.season.endLabel)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
            .frame(height: 104)

            VStack(alignment: .leading, spacing: 2) {
                Text(quest.title).font(.app(15.5, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text("From \(quest.fromText.lowercasedFirst)").font(.app(12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8).padding(.top, 12)

            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8).padding(.top, 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("Moved by").font(.app(12, .semibold)).foregroundStyle(Theme.muted).padding(.bottom, 2)
                ForEach(linked) { goal in
                    MoverRow(
                        badge: goal.badge, title: goal.title, meta: goal.isPractice ? "Practice · \(SeasonSetupState.rhythm(goal.practice?.perWeek))" : "Project",
                        isNew: state.created.contains(goal.id)
                    ) { actions.toggleLink(quest.id, goal.id) }
                }
                ForEach(added, id: \.self) { suggestion in
                    MoverRow(
                        badge: PlateBadge(icon: suggestion.icon, color: suggestion.color, isPractice: suggestion.kind == .practice),
                        title: suggestion.title,
                        meta: suggestion.kind == .practice ? "Practice · \(SeasonSetupState.rhythm(suggestion.perWeek ?? 1))" : "Project",
                        isNew: true
                    ) { actions.removeNew(quest.id, suggestion) }
                }
                if linked.isEmpty && added.isEmpty && state.findingSuggestions.contains(quest.id) {
                    HStack(spacing: 8) {
                        SpinningIcon(size: 13)
                        Text("Finding something to move it").font(.app(12.5))
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(height: 44)
                }
                if isAdding { adder } else { addButton }
            }
            .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 8)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 14, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private var addButton: some View {
        Button {
            isAdding = true
            searchFocused = true
        } label: {
            HStack(spacing: 8) {
                Icon.add.image(size: 13)
                Text("Add a project or practice").font(.app(12.5, .medium))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Adding: a field to search the plate or name something new, what's on the plate to pick from, and New project or
    /// New practice.
    private var adder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Icon.add.image(size: 13).foregroundStyle(Theme.muted)
                TextField("", text: $search)
                    .textFieldStyle(.plain)
                    .font(.app(12.5))
                    .focused($searchFocused)
                    .placeholder("Search, or name something new", when: search.isEmpty, font: .app(12.5))
                    .onExitCommand { close() }
                Button(action: close) { Icon.close.image(size: 11).foregroundStyle(Theme.muted) }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 0) {
                if !options.isEmpty {
                    Text("From your plate").font(.app(11, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)
                    ForEach(options.prefix(5)) { goal in
                        AdderRow(label: goal.title, detail: state.area(goal.areaId ?? "")?.name) {
                            GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice).scaleEffect(22.0 / 24.0)
                        } action: {
                            actions.toggleLink(quest.id, goal.id)
                            close()
                        }
                    }
                    Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
                }
                ForEach([GoalKind.project, .practice], id: \.self) { kind in
                    let name = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    AdderRow(label: name.isEmpty ? "New \(kind == .practice ? "practice" : "project")" : "New \(kind == .practice ? "practice" : "project"): \(name)") {
                        Icon.add.image(size: 11).foregroundStyle(Theme.muted)
                            .frame(width: 22, height: 22).background(Theme.foreground(0.05), in: .rect(cornerRadius: 6))
                    } action: {
                        guard !name.isEmpty else { return searchFocused = true }
                        actions.addNew(quest.id, QuestSuggestion(kind: kind, title: name, line: "", perWeek: kind == .practice ? 1 : nil))
                        close()
                    }
                }
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(Theme.card).shadow(color: .black.opacity(0.14), radius: 16, y: 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        }
    }

    private func close() {
        isAdding = false
        search = ""
    }
}

/// One thing that moves a quest: its badge, name and kind, New if it's being made, and a way to take it off.
private struct MoverRow: View {
    let badge: PlateBadge
    let title: String
    let meta: String
    var isNew = false
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GoalBadge(icon: badge.icon, color: badge.color, size: .xs, round: badge.isPractice)
                .scaleEffect(28.0 / 24.0).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    if isNew { NewTag() }
                }
                Text(meta).font(.app(11.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onRemove) { Icon.close.image(size: 12).foregroundStyle(Theme.muted.opacity(0.7)) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.background, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }
}

private struct AdderRow<Mark: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var mark: Mark
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                mark.frame(width: 22, height: 22)
                Text(label).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(.app(11)).foregroundStyle(Theme.muted) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isHovered ? Theme.foreground(0.045) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension Goal {
    var badge: PlateBadge { PlateBadge(icon: icon, color: color, isPractice: isPractice) }
}

extension String {
    /// "Running rarely" as "running rarely", to follow "From".
    var lowercasedFirst: String {
        guard let first, !(dropFirst().first?.isUppercase ?? false) else { return self }
        return first.lowercased() + dropFirst()
    }
}
