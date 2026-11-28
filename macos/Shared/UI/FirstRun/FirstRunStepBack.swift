import AppKit
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
    /// Say it instead into one side of an area's stand, or stop.
    var dictate: (StandTarget) -> Void = { _ in }
    /// The gap and what the season could reach, as the person wrote them: area id, gap, reach. True once saved.
    var editGap: (String, GapInput, String) async -> Bool = { _, _, _ in true }
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
    /// Say it instead, on an area's stand.
    var voice = StandVoice()
    var actions = StepBackActions()
    /// The area's gap opens being edited (snapshots).
    var editingGap = false

    var body: some View {
        switch state.step {
        case .areas:
            StepBackAreas(state: state, actions: actions)
        case .stand(let index):
            if let area = state.pickedAreas[safe: index] {
                StepBackStand(state: state, index: index, area: area, voice: voice, actions: actions, editingGap: editingGap).id(area.id)
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
///
/// Each side offers a guess at what they'd write, from the plate and what's in the area, in place of its prompt; Tab
/// takes it. Each can be said instead of typed. The gap card is where it's named: clicked once both sides are said,
/// then edited in place or named again.
private struct StepBackStand: View {
    let state: SeasonSetupState
    let index: Int
    let area: Area
    var voice = StandVoice()
    let actions: StepBackActions
    var editingGap = false
    @State private var now: String
    @State private var want: String
    @FocusState private var focus: StandField?

    init(state: SeasonSetupState, index: Int, area: Area, voice: StandVoice = StandVoice(), actions: StepBackActions, editingGap: Bool = false) {
        self.state = state
        self.index = index
        self.area = area
        self.voice = voice
        self.actions = actions
        self.editingGap = editingGap
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
    private var draft: StandDraft? { state.standDrafts[area.id] }
    /// Listening on either side of this area.
    private var isListening: Bool { voice.dictation.isActive && voice.target?.areaId == area.id }
    /// Both sides said, and nothing still being said: there's something to name the gap from.
    private var canName: Bool { !trimmed(now).isEmpty && !trimmed(want).isEmpty && !isListening && !isReading }

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
                    StandSide(
                        label: "Where it is today", text: $now, solid: false, color: color,
                        prompt: "What it’s like now, honestly", suggestion: draft?.now,
                        voice: voice, target: StandTarget(areaId: area.id, field: .now), focus: $focus, onDictate: actions.dictate
                    )
                    StandSide(
                        label: "Where you want it to be", text: $want, solid: true, color: color,
                        prompt: "Where you’d like it to get, however far off", suggestion: draft?.want,
                        voice: voice, target: StandTarget(areaId: area.id, field: .want), focus: $focus, onDictate: actions.dictate
                    )
                }
                .padding(.top, 20)
                StandGap(
                    area: area, quest: quest, color: color, season: state.season, from: state.goals(in: area).first?.badge,
                    isRead: isRead, isReading: isReading, canName: canName, isListening: isListening,
                    startsEditing: editingGap,
                    onName: { actions.read(area.id, trimmed(now), trimmed(want)) },
                    onEdit: { gap, reach in await actions.editGap(area.id, gap, reach) }
                )
                .padding(.top, 16)
            }
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error = state.error {
                Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack)).padding(.trailing, 8)
            }
            FlowButton(title: isLast ? "Continue" : "Next area", primary: true, isEnabled: isRead, action: actions.next)
        }
        .onChange(of: voice.spoken) {
            // Words said here settle into the side they were said into.
            guard let spoken = voice.spoken, spoken.target.areaId == area.id else { return }
            switch spoken.target.field {
            case .now: now = Self.joined(now, spoken.words)
            case .want: want = Self.joined(want, spoken.words)
            }
        }
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func joined(_ text: String, _ words: String) -> String {
        text.isEmpty || text.last?.isWhitespace == true ? text + words : text + " " + words
    }
}

/// One side of an area's stand: its label and a microphone, then what they write. Empty, it shows a guess at what
/// they'd write (Tab takes it) or else its prompt. Listening, the words as they come, the unsettled ones muted.
private struct StandSide: View {
    let label: String
    @Binding var text: String
    let solid: Bool
    let color: String
    let prompt: String
    var suggestion: String?
    let voice: StandVoice
    let target: StandTarget
    var focus: FocusState<StandField?>.Binding
    let onDictate: (StandTarget) -> Void

    private var isListening: Bool { voice.isActive(target) }
    /// The guess, shown while there's nothing written.
    private var offered: String? { text.isEmpty && !isListening ? suggestion : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(GoalPalette.color(color), lineWidth: solid ? 0 : 1.5)
                    .background(Circle().fill(solid ? GoalPalette.color(color) : .clear))
                    .frame(width: 10, height: 10)
                Text(label).font(.app(12.5, .semibold)).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                MicButton(isListening: isListening, isPreparing: isListening && voice.dictation.phase == .preparing) { onDictate(target) }
            }
            .frame(height: 20)

            Group {
                if isListening {
                    Text("\(text)\(Text((text.isEmpty || voice.dictation.volatile.isEmpty ? "" : " ") + voice.dictation.volatile).foregroundStyle(Theme.muted))")
                        .font(.app(16, .medium)).tracking(-0.16).lineSpacing(5)
                        .foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty && voice.dictation.volatile.isEmpty {
                                Text(voice.dictation.phase == .preparing ? "Getting ready to listen…" : "Listening…")
                                    .font(.app(16, .medium)).foregroundStyle(Theme.muted.opacity(0.7))
                            }
                        }
                } else {
                    TextField("", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(16, .medium)).tracking(-0.16).lineSpacing(5)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(3...5)
                        .focused(focus, equals: target.field)
                        .placeholder(offered ?? prompt, when: text.isEmpty, font: .app(16, .medium))
                        // Tab takes the guess while there's nothing written; otherwise it moves on as usual.
                        .modifier(TabTakes(isOn: focus.wrappedValue == target.field && offered != nil) {
                            if let offered { text = offered }
                        })
                }
            }
            .frame(minHeight: 72, alignment: .topLeading)

            if offered != nil {
                HStack(spacing: 6) {
                    Text("tab").font(.app(10.5, .medium))
                        .padding(.horizontal, 5).frame(height: 18)
                        .background(Theme.foreground(0.05), in: .rect(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
                    Text("to use this guess").font(.app(11.5))
                }
                .foregroundStyle(Theme.muted)
                .transition(.opacity)
            }
        }
        .padding(16).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isListening ? GoalPalette.color("sky").opacity(0.6) : Theme.cardBorder, lineWidth: isListening ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.15), value: offered == nil)
    }
}

/// Catches Tab while it's on, before the text field's own handling moves focus on, and calls `action` instead. A
/// window-level key monitor, since a text field's editor sees Tab before SwiftUI's key handlers do.
private struct TabTakes: ViewModifier {
    let isOn: Bool
    let action: () -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear { update() }
            .onChange(of: isOn) { update() }
            .onDisappear { remove() }
    }

    private func update() {
        remove()
        guard isOn else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard event.keyCode == 48, modifiers.isEmpty else { return event }
            action()
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Say it instead: a microphone, lit while it listens.
private struct MicButton: View {
    let isListening: Bool
    var isPreparing = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isPreparing { Spinner(size: 13) } else { (isListening ? Icon.micBold : Icon.mic).image(size: 15) }
            }
            .foregroundStyle(isListening ? GoalPalette.color("sky") : isHovered ? Theme.foreground : Theme.muted)
            .frame(width: 28, height: 28)
            .background(isListening ? GoalPalette.tintBackground("sky") : isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isListening ? "Stop listening" : "Say it instead")
        .padding(.trailing, -6)
    }
}

/// The gap between the two sides, where it's named. Before: a dashed card that names it when clicked, once both sides
/// are said. Named: its headline and line, what this season could reach and its track, with Edit and Name it again.
/// Changed since: faded, with Name it again. Editing: the headline, the line and the reach as fields, in place.
private struct StandGap: View {
    let area: Area
    let quest: Quest?
    let color: String
    let season: Season
    let from: PlateBadge?
    let isRead: Bool
    let isReading: Bool
    let canName: Bool
    let isListening: Bool
    let onName: () -> Void
    let onEdit: (GapInput, String) async -> Bool
    @State private var editing: Bool
    @State private var draft: GapInput
    @State private var reach: String
    @State private var isSaving = false
    @State private var isHovered = false

    init(
        area: Area, quest: Quest?, color: String, season: Season, from: PlateBadge?, isRead: Bool, isReading: Bool, canName: Bool,
        isListening: Bool, startsEditing: Bool = false, onName: @escaping () -> Void, onEdit: @escaping (GapInput, String) async -> Bool
    ) {
        self.area = area
        self.quest = quest
        self.color = color
        self.season = season
        self.from = from
        self.isRead = isRead
        self.isReading = isReading
        self.canName = canName
        self.isListening = isListening
        self.onName = onName
        self.onEdit = onEdit
        _editing = State(initialValue: startsEditing && area.gap != nil && quest != nil)
        _draft = State(initialValue: GapInput(editing: area.gap))
        _reach = State(initialValue: quest?.title ?? "")
    }

    var body: some View {
        Group {
            if let gap = area.gap, let quest {
                if editing {
                    editor
                } else {
                    named(gap, quest)
                }
            } else {
                unnamed
            }
        }
        .animation(.smooth(duration: 0.2), value: editing)
    }

    // MARK: Not named yet

    private var unnamed: some View {
        Button(action: onName) {
            HStack(spacing: 14) {
                Group {
                    if isReading { Spinner(size: 15) } else { Icon.route.image(size: 16) }
                }
                .foregroundStyle(canName || isReading ? GoalPalette.color(color) : Theme.muted)
                .frame(width: 36, height: 36)
                .background(canName || isReading ? GoalPalette.tintBackground(color) : Theme.foreground(0.04), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isReading ? "Naming the gap…" : "Name the gap")
                        .font(.app(14, .semibold))
                        .foregroundStyle(canName || isReading ? Theme.foreground : Theme.muted)
                    Text(line).font(.app(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if canName {
                    Icon.arrowRight.image(size: 15)
                        .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                        .offset(x: isHovered ? 2 : 0)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(canName && isHovered ? GoalPalette.tintBackground(color).opacity(0.6) : .clear, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    canName ? GoalPalette.color(color).opacity(isHovered ? 0.7 : 0.45) : Theme.foreground(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!canName)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: canName)
    }

    private var line: String {
        if isReading { return "Between where it is and where you want it, and how far this season could take it." }
        if isListening { return "Once you’ve finished saying it, name the gap between the two." }
        if canName { return "Supervibes names the gap between where it is and where you want it, and how far this season could take it." }
        return "Say where it is today and where you want it first; then Supervibes names the gap between them."
    }

    // MARK: Named

    private func named(_ gap: AreaGap, _ quest: Quest) -> some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("The gap").font(.app(12.5, .semibold)).foregroundStyle(GoalPalette.color(color))
                    Spacer(minLength: 8)
                    if isRead {
                        GapAction(icon: .edit, title: "Edit") { startEditing(gap, quest) }
                    }
                    GapAction(icon: isReading ? nil : .refresh, title: isReading ? "Naming again…" : "Name it again",
                              prominent: !isRead && !isReading, isBusy: isReading, action: onName)
                        .disabled(!canName)
                }
                Text(gap.title).font(.app(19, .semibold)).tracking(-0.3).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                Text(gap.body.isEmpty ? "By \(season.endLabel) this season could get as far as: \(quest.title)." : gap.body)
                    .font(.app(13)).lineSpacing(3).foregroundStyle(Theme.foreground(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500, alignment: .leading).padding(.top, 6)
                if !isRead && !isReading {
                    Text("You’ve changed what you said since. Name it again to catch up.")
                        .font(.app(12)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GapTrack(reach: quest.reach, color: color, end: season.endLabel, from: from, labels: true)
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 14)
                .background(Theme.card.opacity(0.7), in: .rect(cornerRadius: 12))
                .frame(width: 340)
                .opacity(isRead ? 1 : 0.5)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .background(GoalPalette.tintBackground(color).opacity(isRead ? 1 : 0.55), in: .rect(cornerRadius: 16))
    }

    private func startEditing(_ gap: AreaGap, _ quest: Quest) {
        draft = GapInput(editing: gap)
        reach = quest.title
        editing = true
    }

    // MARK: Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The gap").font(.app(12.5, .semibold)).foregroundStyle(GoalPalette.color(color))
            EditLine(label: "In a few words", text: $draft.title, font: .app(17, .semibold), prompt: "From where it is to where you want it")
            EditLine(label: "A line or two", text: $draft.body, font: .app(13.5), prompt: "What the gap is, in your words", lines: 2...4)
            EditLine(label: "By \(season.endLabel), this season could reach", text: $reach, font: .app(14, .medium),
                     prompt: "One thing you could see by then")
            HStack(spacing: 8) {
                Spacer()
                FlowButton(title: "Cancel") { editing = false }
                FlowButton(title: "Save", primary: true, isBusy: isSaving,
                           isEnabled: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               && !reach.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task {
                        isSaving = true
                        let saved = await onEdit(draft, reach)
                        isSaving = false
                        if saved { editing = false }
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 16))
    }
}

/// One of the gap's fields while it's edited: a small label over a field on the card.
private struct EditLine: View {
    let label: String
    @Binding var text: String
    let font: Font
    let prompt: String
    var lines: ClosedRange<Int> = 1...2

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.app(11.5, .medium)).foregroundStyle(Theme.muted)
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Theme.foreground)
                .lineLimit(lines)
                .placeholder(prompt, when: text.isEmpty, font: font)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
        }
    }
}

/// The named gap's small actions: an icon and a word, muted until hovered; Name it again stands out once the words
/// have changed.
private struct GapAction: View {
    let icon: Icon?
    let title: String
    var prominent = false
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isBusy { Spinner(size: 11) } else if let icon { icon.image(size: 12) }
                Text(title).font(.app(12, .medium))
            }
            .foregroundStyle(prominent ? Theme.background : isHovered ? Theme.foreground : Theme.foreground(0.6))
            .padding(.horizontal, 9).frame(height: 26)
            .background(prominent ? Theme.foreground : isHovered ? Theme.card.opacity(0.8) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
            .opacity(isEnabled || isBusy ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                        Spinner(size: 13)
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
