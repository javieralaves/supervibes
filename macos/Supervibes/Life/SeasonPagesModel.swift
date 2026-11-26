import Foundation
import Observation

/// The season's page, through /api/v1: the season and its read, with the person's goals and areas, and its read
/// written again on Update. Renaming it or moving its end goes through the season dialog.
@MainActor
@Observable
final class SeasonPageModel {
    enum Load: Equatable {
        case loading, loaded, gone
        case failed(String)
    }

    let id: String
    private(set) var load: Load = .loading
    private(set) var data: SeasonPageData?
    private(set) var reading = false
    private(set) var readError: String?
    private(set) var editError: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(id: String, auth: AuthModel) {
        self.id = id
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    private var api: SeasonAPI { SeasonAPI(client: client, auth: auth) }
    private var areaAPI: AreaAPI { AreaAPI(client: client, auth: auth) }

    func refresh() async {
        do {
            async let detail = api.season(id)
            async let goals = api.goalsWithWeeks()
            async let areas = areaAPI.list()
            let (season, read) = try await detail
            let (list, weeks, today) = try await goals
            data = SeasonPageData(season: season, read: read, goals: list, weeks: weeks, areas: try await areas, today: today)
            load = .loaded
        } catch let failure as AreaAPIError {
            if failure.message.contains("doesn’t exist") { load = .gone } else if data == nil { load = .failed(failure.message) }
        } catch {
            if data == nil { load = .failed("Couldn’t load the season.") }
        }
    }

    func read() async {
        guard !reading else { return }
        reading = true
        readError = nil
        defer { reading = false }
        do {
            data?.read = try await api.readSeason(id)
        } catch {
            readError = (error as? AreaAPIError)?.message ?? "Couldn’t read the season."
        }
    }

    /// Renames the season or moves its end; true once saved.
    func update(_ input: SeasonInput) async -> Bool {
        editError = nil
        do {
            let season = try await api.update(id, input)
            data?.season = season
            return true
        } catch {
            editError = (error as? AreaAPIError)?.message ?? "Couldn’t save the season."
            return false
        }
    }
}

/// A quest's page, through /api/v1: the quest, its season, its area's gap and its read, with the person's goals and
/// areas; its read written again on Update, and what moves it changed from its list.
@MainActor
@Observable
final class QuestPageModel {
    let id: String
    private(set) var load: SeasonPageModel.Load = .loading
    private(set) var data: QuestPageData?
    private(set) var reading = false
    private(set) var readError: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(id: String, auth: AuthModel) {
        self.id = id
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    private var api: SeasonAPI { SeasonAPI(client: client, auth: auth) }
    private var areaAPI: AreaAPI { AreaAPI(client: client, auth: auth) }

    func refresh() async {
        do {
            async let detail = api.quest(id)
            async let goals = api.goalsWithWeeks()
            async let areas = areaAPI.list()
            let (quest, season, gap, read) = try await detail
            let (list, weeks, today) = try await goals
            data = QuestPageData(quest: quest, season: season, gap: gap, read: read, goals: list, weeks: weeks,
                                 areas: try await areas, today: today)
            load = .loaded
        } catch let failure as AreaAPIError {
            if failure.message.contains("doesn’t exist") { load = .gone } else if data == nil { load = .failed(failure.message) }
        } catch {
            if data == nil { load = .failed("Couldn’t load the quest.") }
        }
    }

    func read() async {
        guard !reading else { return }
        reading = true
        readError = nil
        defer { reading = false }
        do {
            data?.read = try await api.readQuest(id)
        } catch {
            readError = (error as? AreaAPIError)?.message ?? "Couldn’t read the quest."
        }
    }

    /// Links a goal to the quest, or unlinks it. A goal moves one quest a season, so linking it here takes it from
    /// another.
    func toggle(_ goal: Goal) async {
        guard let quest = data?.quest else { return }
        let ids = quest.goalIds.contains(goal.id) ? quest.goalIds.filter { $0 != goal.id } : quest.goalIds + [goal.id]
        readError = nil
        do {
            data?.quest = try await api.setQuestGoals(id, ids)
            // Its effort follows its goals: take it as the server counts it.
            await refresh()
        } catch {
            readError = (error as? AreaAPIError)?.message ?? "Couldn’t change what moves this quest."
        }
    }
}
