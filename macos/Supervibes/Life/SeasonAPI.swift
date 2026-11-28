import Foundation

/// The season calls Life and starting a season share: the current seasons, a draft's days, reading where an area
/// stands, choosing quests and what moves them, and starting. Each throws `AreaAPIError` with a message written for
/// people, ready to show.
@MainActor
struct SeasonAPI {
    let client: Client
    let auth: AuthModel

    private var timeZone: String { TimeZone.current.identifier }

    /// The running season, the one being set up and one that just ended, and the popular areas to offer.
    func current() async throws -> CurrentSeasons {
        try await call("Couldn’t load your season") {
            switch try await client.getCurrentSeasons(query: .init(timeZone: timeZone)) {
            case .ok(let ok): return CurrentSeasons(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load your season.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t load your season (the server answered \(status)).")
            }
        }
    }

    /// Starts setting up a season, on its default days: 13 weeks from the next Monday.
    func createDraft() async throws -> Season {
        try await call("Couldn’t start a season") {
            switch try await client.createSeason() {
            case .created(let created): return Season(api: try created.body.json)
            case .unauthorized: throw await signedOut()
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t start a season.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t start a season (the server answered \(status)).")
            }
        }
    }

    func update(_ id: String, _ input: SeasonInput) async throws -> Season {
        try await call("Couldn’t save the season") {
            let body = Components.Schemas.SeasonDays(
                name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), startsOn: input.startsOn, endsOn: input.endsOn
            )
            switch try await client.updateSeason(path: .init(id: id), body: .json(body)) {
            case .ok(let ok): return Season(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t save the season.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t save the season (the server answered \(status)).")
            }
        }
    }

    /// Reads where an area stands for the draft: names its gap if it has none, and writes its candidate quest.
    /// Names the area's gap if it has none (or afresh, with `rename`) and writes its candidate quest.
    func readStand(season: String, area: String, rename: Bool = false) async throws -> (gap: AreaGap?, quest: Quest) {
        try await call("Couldn’t read this area") {
            switch try await client.readAreaStand(path: .init(id: season, areaId: area), query: .init(rename: rename ? ._true : nil)) {
            case .ok(let ok):
                let stand = try ok.body.json
                return (stand.gap.map(AreaGap.init(api:)), Quest(api: stand.quest))
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season or area doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t read this area. Try again.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t read this area (the server answered \(status)).")
            }
        }
    }

    /// Guesses at how they'd say where each area stands and where they want it, for the areas with something to go
    /// on, by area id. `plate` is what they typed in first run, for context.
    func draftStands(season: String, areaIds: [String], plate: String?) async throws -> [String: StandDraft] {
        try await call("Couldn’t guess where your areas stand") {
            let body = Components.Schemas.StandDraftsRequest(areaIds: areaIds, plate: plate.map { String($0.prefix(6000)) })
            switch try await client.draftAreaStands(path: .init(id: season), body: .json(body)) {
            case .ok(let ok):
                return Dictionary(try ok.body.json.drafts.map { ($0.areaId, StandDraft(now: $0.now, want: $0.want)) }) { first, _ in first }
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t guess where your areas stand.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t guess where your areas stand (the server answered \(status)).")
            }
        }
    }

    /// Saves an area's gap as the person wrote it, replacing any.
    func writeGap(area: String, _ input: GapInput) async throws -> AreaGap {
        try await call("Couldn’t save the gap") {
            let body = Components.Schemas.AreaGapInput(
                title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: input.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            switch try await client.writeAreaGap(path: .init(id: area), body: .json(body)) {
            case .ok(let ok): return AreaGap(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That area doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t save the gap.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t save the gap (the server answered \(status)).")
            }
        }
    }

    func updateQuest(_ id: String, title: String? = nil, fromText: String? = nil, chosen: Bool? = nil) async throws -> Quest {
        try await call("Couldn’t save the quest") {
            let body = Components.Schemas.QuestChange(title: title, fromText: fromText, chosen: chosen)
            switch try await client.updateQuest(path: .init(id: id), body: .json(body)) {
            case .ok(let ok): return Quest(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That quest doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t save the quest.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t save the quest (the server answered \(status)).")
            }
        }
    }

    /// Sets the projects and practices that move a quest, replacing the last.
    func setQuestGoals(_ id: String, _ goalIds: [String]) async throws -> Quest {
        try await call("Couldn’t save what moves the quest") {
            switch try await client.setQuestGoals(path: .init(id: id), body: .json(.init(goalIds: goalIds))) {
            case .ok(let ok): return Quest(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That quest doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t save what moves the quest.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t save what moves the quest (the server answered \(status)).")
            }
        }
    }

    /// A few projects and practices Supervibes suggests for a quest. Nothing is saved.
    func suggestions(for quest: String) async throws -> [QuestSuggestion] {
        try await call("Couldn’t get suggestions") {
            switch try await client.suggestForQuest(path: .init(id: quest)) {
            case .ok(let ok):
                return try ok.body.json.suggestions.map {
                    QuestSuggestion(kind: $0.kind == .practice ? .practice : .project, title: $0.title, line: $0.line, perWeek: $0.perWeek)
                }
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That quest doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t get suggestions. Try again.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t get suggestions (the server answered \(status)).")
            }
        }
    }

    /// Starts the draft: its unchosen quests go, and it runs from its first day.
    func start(_ id: String) async throws -> Season {
        try await call("Couldn’t start the season") {
            switch try await client.startSeason(path: .init(id: id)) {
            case .ok(let ok): return Season(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t start the season.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t start the season (the server answered \(status)).")
            }
        }
    }

    /// Makes a project or practice; it comes back as the server has it.
    func createGoal(_ input: GoalInput) async throws -> Goal {
        try await call("Couldn’t add that \(input.kind.noun)") {
            switch try await client.createGoal(body: .json(Components.Schemas.NewGoal(new: input, areaId: input.areaId))) {
            case .created(let created): return Goal(api: try created.body.json)
            case .unauthorized: throw await signedOut()
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t add that \(input.kind.noun).")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t add that \(input.kind.noun) (the server answered \(status)).")
            }
        }
    }

    /// Every goal, with this week's of each, for linking.
    func goals() async throws -> [Goal] {
        try await call("Couldn’t load your projects and practices") {
            switch try await client.listGoals(query: .init(timeZone: timeZone)) {
            case .ok(let ok): return try ok.body.json.goals.map(Goal.init(api:))
            case .unauthorized: throw await signedOut()
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load your projects and practices.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t load your projects and practices (the server answered \(status)).")
            }
        }
    }

    /// A season's page: the season, counted today, and its read.
    func season(_ id: String) async throws -> (season: Season, read: AreaRead?) {
        try await call("Couldn’t load the season") {
            switch try await client.getSeason(path: .init(id: id), query: .init(timeZone: timeZone)) {
            case .ok(let ok):
                let body = try ok.body.json
                guard let season = body.season else { throw AreaAPIError("That season doesn’t exist anymore.") }
                return (Season(api: season), body.read.map(AreaRead.init(api:)))
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load the season.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t load the season (the server answered \(status)).")
            }
        }
    }

    /// A quest's page: the quest, its season, its area's gap and its read.
    func quest(_ id: String) async throws -> (quest: Quest, season: Season, gap: AreaGap?, read: AreaRead?) {
        try await call("Couldn’t load the quest") {
            switch try await client.getQuest(path: .init(id: id), query: .init(timeZone: timeZone)) {
            case .ok(let ok):
                let body = try ok.body.json
                guard let season = body.season else { throw AreaAPIError("That quest’s season doesn’t exist anymore.") }
                return (Quest(api: body.quest), Season(api: season), body.gap.map(AreaGap.init(api:)), body.read.map(AreaRead.init(api:)))
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That quest doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load the quest.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t load the quest (the server answered \(status)).")
            }
        }
    }

    /// Writes a season's read from its quests' projects and practices and the calendar; takes a few seconds.
    func readSeason(_ id: String) async throws -> AreaRead {
        try await call("Couldn’t read the season") {
            switch try await client.readSeason(path: .init(id: id)) {
            case .ok(let ok): return AreaRead(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That season doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t read the season. Try again.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t read the season (the server answered \(status)).")
            }
        }
    }

    /// Writes a quest's read; takes a few seconds.
    func readQuest(_ id: String) async throws -> AreaRead {
        try await call("Couldn’t read the quest") {
            switch try await client.readQuest(path: .init(id: id)) {
            case .ok(let ok): return AreaRead(api: try ok.body.json)
            case .unauthorized: throw await signedOut()
            case .notFound: throw AreaAPIError("That quest doesn’t exist anymore.")
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t read the quest. Try again.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t read the quest (the server answered \(status)).")
            }
        }
    }

    /// Every goal and each one's week, by goal id.
    func goalsWithWeeks() async throws -> (goals: [Goal], weeks: [String: GoalWeek], today: String) {
        try await call("Couldn’t load your projects and practices") {
            switch try await client.listGoals(query: .init(timeZone: timeZone)) {
            case .ok(let ok):
                let body = try ok.body.json
                let weeks = Dictionary(body.week.goals.map { ($0.goalId, GoalWeek(api: $0)) }, uniquingKeysWith: { first, _ in first })
                return (body.goals.map(Goal.init(api:)), weeks, body.today)
            case .unauthorized: throw await signedOut()
            case .badRequest(let bad): throw AreaAPIError((try? bad.body.json.error.message) ?? "Couldn’t load your projects and practices.")
            case .undocumented(let status, _): throw AreaAPIError("Couldn’t load your projects and practices (the server answered \(status)).")
            }
        }
    }

    // MARK: Helpers

    /// Runs a call, turning a dropped connection into a message.
    private func call<T>(_ what: String, _ run: () async throws -> T) async throws -> T {
        do {
            return try await run()
        } catch let error as AreaAPIError {
            throw error
        } catch {
            Log.app.error("Seasons: \(error.localizedDescription, privacy: .public)")
            throw AreaAPIError("\(what). Check your connection.")
        }
    }

    private func signedOut() async -> AreaAPIError {
        await auth.sessionEnded()
        return AreaAPIError("You were signed out.")
    }
}

// MARK: - From the API

extension Season {
    init(api season: Components.Schemas.Season) {
        self.init(
            id: season.id,
            name: season.name,
            startsOn: season.startsOn,
            endsOn: season.endsOn,
            state: State(rawValue: season.state.rawValue) ?? .draft,
            week: season.week,
            weeks: season.weeks,
            status: season.status.flatMap { GoalStatus(rawValue: $0.rawValue) },
            quests: season.quests.map(Quest.init(api:))
        )
    }
}

extension Quest {
    init(api quest: Components.Schemas.Quest) {
        self.init(
            id: quest.id,
            seasonId: quest.seasonId,
            areaId: quest.areaId,
            title: quest.title,
            fromText: quest.fromText,
            reach: quest.reach,
            chosen: quest.chosen,
            position: quest.position,
            goalIds: quest.goalIds,
            effort: quest.effort.flatMap { GoalStatus(rawValue: $0.rawValue) }
        )
    }
}

extension AreaRead {
    init(api read: Components.Schemas.SeasonRead) {
        self.init(headline: read.headline, summary: read.summary, goalIds: read.goalIds, usedCalendar: read.usedCalendar, createdAt: read.createdAt)
    }
}

extension CurrentSeasons {
    init(api body: Components.Schemas.CurrentSeasons) {
        self.init(
            today: body.today,
            active: body.active.map(Season.init(api:)),
            draft: body.draft.map(Season.init(api:)),
            ended: body.ended.map(Season.init(api:)),
            popularAreas: body.popularAreas.map { PopularArea(name: $0.name, icon: $0.icon, line: $0.line) }
        )
    }
}
