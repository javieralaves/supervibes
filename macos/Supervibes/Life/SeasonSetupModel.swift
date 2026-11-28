import Foundation
import Observation

/// Starting a season, against /api/v1: makes or picks up the draft, makes the areas picked from Popular areas, reads
/// where each area stands, chooses quests, links what moves them (making added suggestions), and starts it.
///
/// The draft lives on the server, so leaving and coming back picks up where it was; which areas were picked is kept
/// on this Mac beside it, keyed by the season.
@MainActor
@Observable
final class SeasonSetupModel {
    enum Load: Equatable {
        case loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .loading
    /// What the flow shows; nil until loaded.
    private(set) var state: SeasonSetupState?
    /// The season just started, for Life to open on.
    private(set) var started: Season?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    private var seasonAPI: SeasonAPI { SeasonAPI(client: client, auth: auth) }
    private var areaAPI: AreaAPI { AreaAPI(client: client, auth: auth) }

    // MARK: Loading

    /// The draft (made if there's none), the person's areas and goals, and where they were.
    func start() async {
        load = .loading
        do {
            async let current = seasonAPI.current()
            async let areas = areaAPI.list()
            async let goals = seasonAPI.goals()
            let seasons = try await current
            guard seasons.active == nil else {
                load = .failed("\(seasons.active!.name) is running. A new season can start once it ends.")
                return
            }
            let draft: Season
            if let existing = seasons.draft { draft = existing } else { draft = try await seasonAPI.createDraft() }
            var state = SeasonSetupState(
                season: draft, today: seasons.today, areas: try await areas, goals: try await goals,
                popular: seasons.popularAreas, picked: []
            )
            resume(&state)
            self.state = state
            load = .loaded
        } catch {
            load = .failed((error as? AreaAPIError)?.message ?? "Couldn’t start a season.")
        }
    }

    /// Picks up where the draft was: its picked areas, then the first step not done.
    private func resume(_ state: inout SeasonSetupState) {
        let saved = (UserDefaults.standard.stringArray(forKey: pickedKey(state.season.id)) ?? []).filter { id in
            state.areas.contains { $0.id == id }
        }
        // Areas read before, even if not saved here, were picked.
        let read = state.areas.map(\.id).filter { id in state.season.quests.contains { $0.areaId == id } }
        let picked = saved + read.filter { !saved.contains($0) }
        guard !picked.isEmpty else {
            // A new draft: every area of yours is in, to start.
            state.picked = state.areas.map { .area($0.id) }
            state.step = .areas
            return
        }
        state.picked = picked.map { .area($0) }
        if let unread = state.pickedAreas.firstIndex(where: { state.candidate(for: $0.id) == nil }) {
            state.step = .stand(unread)
        } else if state.chosen.isEmpty {
            state.step = .focus
        } else if let open = state.chosen.firstIndex(where: \.goalIds.isEmpty) {
            state.step = .how(open)
        } else {
            state.step = .review
        }
    }

    private func pickedKey(_ season: String) -> String { "seasonSetup.\(season).areas" }

    private func savePicked() {
        guard let state else { return }
        UserDefaults.standard.set(state.pickedAreas.map(\.id), forKey: pickedKey(state.season.id))
    }

    // MARK: Moving through

    func back() {
        guard var state else { return }
        state.error = nil
        switch state.step {
        case .areas: return
        case .stand(let index): state.step = index == 0 ? .areas : .stand(index - 1)
        case .focus: state.step = .stand(max(0, state.pickedAreas.count - 1))
        case .how(let index): state.step = index == 0 ? .focus : .how(index - 1)
        case .review: state.step = .how(max(0, state.chosen.count - 1))
        }
        self.state = state
    }

    /// On from where each stands, the focus, or a quest (saving what moves it first).
    func next() async {
        guard var state else { return }
        state.error = nil
        switch state.step {
        case .areas:
            return
        case .stand(let index):
            state.step = index + 1 < state.pickedAreas.count ? .stand(index + 1) : .focus
            self.state = state
        case .focus:
            guard !state.chosen.isEmpty else { return }
            state.step = .how(0)
            self.state = state
            findSuggestionsIfNeeded(state.chosen[0].id)
        case .how(let index):
            guard let quest = state.chosen[safe: index] else { return }
            if await saveHow(quest) {
                guard let after = self.state else { return }
                if index + 1 < after.chosen.count {
                    self.state?.step = .how(index + 1)
                    findSuggestionsIfNeeded(after.chosen[index + 1].id)
                } else {
                    self.state?.step = .review
                }
            }
        case .review:
            return
        }
    }

    // MARK: 1. Areas

    func togglePick(_ pick: AreaPick) {
        guard var state else { return }
        if let index = state.picked.firstIndex(of: pick) {
            state.picked.remove(at: index)
        } else {
            state.picked.append(pick)
        }
        self.state = state
    }

    func addCustom(_ name: String) {
        guard var state, !state.picked.contains(.custom(name)) else { return }
        state.picked.append(.custom(name))
        self.state = state
    }

    /// Makes the picked new areas, then goes on to where the first area stands.
    func continueAreas() async {
        guard var state, !state.isBusy else { return }
        state.isBusy = true
        state.error = nil
        self.state = state
        defer { self.state?.isBusy = false }
        var picked: [AreaPick] = []
        for pick in state.picked {
            switch pick {
            case .area:
                picked.append(pick)
            case .popular(let name), .custom(let name):
                let icon = state.popular.first { $0.name == name }?.icon ?? AreaInput.defaultIcon
                do {
                    let area = try await areaAPI.create(AreaInput(name: name, icon: icon))
                    self.state?.areas.append(area)
                    picked.append(.area(area.id))
                } catch {
                    self.state?.picked = picked + Array(state.picked.drop(while: { $0 != pick }))
                    self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t add \(name)."
                    return
                }
            }
        }
        // Keep the areas' own order for those of yours, then the new ones as they were added.
        guard let areas = self.state?.areas else { return }
        let ids = picked.compactMap { if case .area(let id) = $0 { id } else { nil } }
        self.state?.picked = areas.filter { ids.contains($0.id) }.map { .area($0.id) }
        self.state?.popular.removeAll { popular in areas.contains { $0.name == popular.name } }
        savePicked()
        guard let after = self.state else { return }
        self.state?.step = .stand(after.pickedAreas.firstIndex { after.candidate(for: $0.id) == nil } ?? 0)
    }

    // MARK: 2. Where each stands

    /// Saves the area's words if they changed, then reads where it stands for the draft.
    func read(areaId: String, now: String, want: String) async {
        guard let state, state.reading == nil, let area = state.area(areaId) else { return }
        self.state?.reading = areaId
        self.state?.error = nil
        defer { self.state?.reading = nil }
        do {
            if now != (area.now ?? "") || want != (area.want ?? "") {
                var input = AreaInput(editing: area)
                input.now = now
                input.want = want
                if let problem = input.problem {
                    self.state?.error = problem
                    return
                }
                let saved = try await areaAPI.update(areaId, input)
                replaceArea(saved, keepingGap: area.gap)
            }
            // Asked again once there's a gap, so it's named afresh from their words rather than kept.
            let (gap, quest) = try await seasonAPI.readStand(season: state.season.id, area: areaId, rename: area.gap != nil)
            if let index = self.state?.areas.firstIndex(where: { $0.id == areaId }) { self.state?.areas[index].gap = gap }
            replaceQuest(quest)
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t read \(area.name)."
        }
    }

    /// Guesses, for the picked areas not asked about yet, at how they'd say where each stands, to offer as they write.
    /// Quietly none if it fails: the fields keep their own prompts.
    func loadStandDrafts(plate: String?) async {
        guard let state else { return }
        let ids = state.pickedAreas.map(\.id).filter { !state.draftsAsked.contains($0) }
        guard !ids.isEmpty else { return }
        self.state?.draftsAsked.formUnion(ids)
        do {
            let drafts = try await seasonAPI.draftStands(season: state.season.id, areaIds: ids, plate: plate)
            self.state?.standDrafts.merge(drafts) { _, new in new }
        } catch {
            Log.app.error("Stand drafts: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saves the gap and what the season could reach as the person wrote them; true once saved.
    func editGap(areaId: String, gap input: GapInput, reach title: String) async -> Bool {
        guard let state, let area = state.area(areaId) else { return false }
        if let problem = input.problem {
            self.state?.error = problem
            return false
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            self.state?.error = "Say what this season could reach."
            return false
        }
        self.state?.error = nil
        do {
            if GapInput(editing: area.gap) != input {
                let gap = try await seasonAPI.writeGap(area: areaId, input)
                if let index = self.state?.areas.firstIndex(where: { $0.id == areaId }) { self.state?.areas[index].gap = gap }
            }
            if let quest = state.candidate(for: areaId), title != quest.title {
                replaceQuest(try await seasonAPI.updateQuest(quest.id, title: title))
            }
            return true
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t save the gap."
            return false
        }
    }

    func editQuest(_ id: String, title: String, fromText: String) async -> Bool {
        do {
            replaceQuest(try await seasonAPI.updateQuest(id, title: title, fromText: fromText))
            return true
        } catch {
            state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t save the quest."
            return false
        }
    }

    // MARK: 3. Focus

    func choose(_ id: String, _ chosen: Bool) async {
        guard let state, !state.isBusy else { return }
        self.state?.error = nil
        do {
            _ = try await seasonAPI.updateQuest(id, chosen: chosen)
            // Choosing renumbers the others, so take the season as the server has it.
            if let season = try await seasonAPI.current().draft { self.state?.season = season }
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t choose that quest."
        }
    }

    // MARK: 4. How each moves

    func toggleLink(quest id: String, goal goalId: String) {
        guard var state, let quest = state.season.quests.first(where: { $0.id == id }) else { return }
        var linked = state.linked[id] ?? quest.goalIds
        if let index = linked.firstIndex(of: goalId) { linked.remove(at: index) } else { linked.append(goalId) }
        state.linked[id] = linked
        // A goal moves one quest a season: ticking it here takes it from another.
        for other in state.chosen where other.id != id {
            let theirs = state.linked[other.id] ?? other.goalIds
            if linked.contains(goalId), theirs.contains(goalId) {
                state.linked[other.id] = theirs.filter { $0 != goalId }
            }
        }
        self.state = state
    }

    func addSuggestion(quest id: String, _ suggestion: QuestSuggestion) {
        guard var state else { return }
        state.added[id, default: []].append(suggestion)
        self.state = state
    }

    func removeSuggestion(quest id: String, _ suggestion: QuestSuggestion) {
        state?.added[id]?.removeAll { $0 == suggestion }
    }

    func findSuggestions(_ id: String) async {
        guard let state, !state.findingSuggestions.contains(id) else { return }
        self.state?.findingSuggestions.insert(id)
        self.state?.suggestionErrors[id] = nil
        defer { self.state?.findingSuggestions.remove(id) }
        do {
            self.state?.suggestions[id] = try await seasonAPI.suggestions(for: id)
        } catch {
            self.state?.suggestionErrors[id] = (error as? AreaAPIError)?.message ?? "Couldn’t get suggestions."
        }
    }

    /// Asks for a quest's suggestions the first time its step opens: one call per quest.
    private func findSuggestionsIfNeeded(_ id: String) {
        guard let state, state.suggestions[id] == nil, state.suggestionErrors[id] == nil else { return }
        Task { await findSuggestions(id) }
    }

    /// Makes a project or practice of the person's own for a quest, in its area, and links it.
    func createGoal(quest id: String, _ input: GoalInput) async {
        guard state != nil else { return }
        self.state?.error = nil
        do {
            let goal = try await seasonAPI.createGoal(input)
            addMade(goal, to: id)
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t add that \(input.kind.noun)."
        }
    }

    /// Makes the quest's added suggestions, then saves what moves it; true once saved.
    private func saveHow(_ quest: Quest) async -> Bool {
        guard let state, !state.isBusy else { return false }
        self.state?.isBusy = true
        defer { self.state?.isBusy = false }
        do {
            for suggestion in state.added[quest.id] ?? [] {
                let goal = try await seasonAPI.createGoal(suggestion.input(areaId: quest.areaId))
                addMade(goal, to: quest.id)
                self.state?.added[quest.id]?.removeAll { $0 == suggestion }
            }
            let linked = self.state?.linked[quest.id] ?? quest.goalIds
            replaceQuest(try await seasonAPI.setQuestGoals(quest.id, linked))
            self.state?.linked[quest.id] = nil
            // Moving a goal here took it from another quest on the server too.
            for other in self.state?.chosen ?? [] where other.id != quest.id {
                if let theirs = self.state?.linked[other.id] { self.state?.linked[other.id] = theirs.filter { !linked.contains($0) } }
                if other.goalIds.contains(where: linked.contains),
                   let index = self.state?.season.quests.firstIndex(where: { $0.id == other.id }) {
                    self.state?.season.quests[index].goalIds.removeAll { linked.contains($0) }
                }
            }
            return true
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t save what moves this quest."
            return false
        }
    }

    private func addMade(_ goal: Goal, to quest: String) {
        guard var state else { return }
        state.goals.append(goal)
        state.created.insert(goal.id)
        if let areaId = goal.areaId, let index = state.areas.firstIndex(where: { $0.id == areaId }) {
            state.areas[index].goalIds.append(goal.id)
        }
        let current = state.linked[quest] ?? state.season.quests.first { $0.id == quest }?.goalIds ?? []
        state.linked[quest] = current + [goal.id]
        self.state = state
    }

    // MARK: First run's Route 3: every quest's moves on one screen

    /// Starts each chosen quest with what's already on the plate in its area, where nothing is linked yet; where its
    /// area has nothing, finds suggestions and adds the first, to be made on Continue.
    func prefillMoves() {
        guard var state else { return }
        let taken = Set(state.chosen.flatMap { state.linked[$0.id] ?? $0.goalIds })
        var empty: [String] = []
        for quest in state.chosen where state.linked[quest.id] == nil && quest.goalIds.isEmpty && (state.added[quest.id] ?? []).isEmpty {
            let inArea = state.area(quest.areaId).map { state.goals(in: $0).map(\.id).filter { !taken.contains($0) } } ?? []
            if inArea.isEmpty { empty.append(quest.id) } else { state.linked[quest.id] = inArea }
        }
        self.state = state
        for id in empty {
            Task {
                if self.state?.suggestions[id] == nil { await findSuggestions(id) }
                guard let first = self.state?.suggestions[id]?.first, (self.state?.added[id] ?? []).isEmpty,
                      self.state?.linked[id]?.isEmpty ?? true else { return }
                addSuggestion(quest: id, first)
            }
        }
    }

    /// Saves what moves every chosen quest, making what was added; on to the review once all are saved.
    func saveAllMoves() async -> Bool {
        guard let chosen = state?.chosen else { return false }
        for quest in chosen {
            guard let current = state?.season.quests.first(where: { $0.id == quest.id }), await saveHow(current) else { return false }
        }
        state?.step = .review
        return true
    }

    /// Back to every quest's moves, from the review.
    func showMoves() {
        state?.error = nil
        state?.step = .how(0)
    }

    // MARK: 5. Review and start

    func updateSeason(_ input: SeasonInput) async -> Bool {
        guard let state else { return false }
        do {
            let season = try await seasonAPI.update(state.season.id, input)
            self.state?.season = season
            return true
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t save the season."
            return false
        }
    }

    /// Starts the season; true once it's running.
    func startSeason() async -> Bool {
        guard let state, !state.isBusy else { return false }
        self.state?.isBusy = true
        self.state?.error = nil
        defer { self.state?.isBusy = false }
        do {
            started = try await seasonAPI.start(state.season.id)
            UserDefaults.standard.removeObject(forKey: pickedKey(state.season.id))
            return true
        } catch {
            self.state?.error = (error as? AreaAPIError)?.message ?? "Couldn’t start the season."
            return false
        }
    }

    // MARK: Helpers

    private func replaceQuest(_ quest: Quest) {
        guard var state else { return }
        if let index = state.season.quests.firstIndex(where: { $0.id == quest.id }) {
            state.season.quests[index] = quest
        } else {
            state.season.quests.append(quest)
        }
        self.state = state
    }

    private func replaceArea(_ area: Area, keepingGap gap: AreaGap?) {
        guard let index = state?.areas.firstIndex(where: { $0.id == area.id }) else { return }
        var area = area
        if area.gap == nil { area.gap = gap }
        state?.areas[index] = area
    }
}
