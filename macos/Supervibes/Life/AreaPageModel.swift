import Foundation
import Observation

/// One area's page: its words, its status over the last weeks and its goals, through /api/v1. It edits the area,
/// moves goals in and out of it, starts new goals in it, and removes it.
@MainActor
@Observable
final class AreaPageModel {
    enum Load: Equatable {
        case loading, loaded, gone
        case failed(String)
    }

    let id: String
    private(set) var load: Load = .loading
    private(set) var detail: AreaDetail?
    /// The person's goals in other areas or none, to move one in.
    private(set) var otherGoals: [Goal] = []
    /// Why the last change didn't go through.
    private(set) var error: String?
    /// The area's read is being written.
    private(set) var reading = false
    /// Why the last read didn't come back.
    private(set) var readError: String?
    /// Supervibes is naming the area's gap.
    private(set) var namingGap = false
    /// Why the gap couldn't be named or saved.
    private(set) var gapError: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(id: String, auth: AuthModel) {
        self.id = id
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    private var areaAPI: AreaAPI { AreaAPI(client: client, auth: auth) }

    func refresh() async {
        do {
            switch try await client.getArea(path: .init(id: id), query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                var loaded = AreaDetail(api: try ok.body.json)
                // Its quest this season, if it has one; the page shows without it if it can't be loaded.
                if let questId = loaded.area.questId,
                   let found = try? await SeasonAPI(client: client, auth: auth).quest(questId) {
                    loaded.quest = found.quest
                    loaded.season = found.season
                }
                detail = loaded
                load = .loaded
                await loadOtherGoals()
            case .notFound:
                detail = nil
                load = .gone
            case .unauthorized:
                await auth.sessionEnded()
            case .badRequest:
                if detail == nil { load = .failed("Couldn’t load this area.") }
            case .undocumented(let status, _):
                if detail == nil { load = .failed("Couldn’t load this area (the server answered \(status)).") }
            }
        } catch {
            Log.app.error("Area: \(error.localizedDescription, privacy: .public)")
            if detail == nil { load = .failed("Couldn’t load this area. Check your connection and try again.") }
        }
    }

    // MARK: Read

    /// Writes the area's read from its goals' reads and the calendar; it takes a few seconds and replaces the last.
    func read() async {
        guard !reading else { return }
        reading = true
        readError = nil
        defer { reading = false }
        do {
            switch try await client.readArea(path: .init(id: id)) {
            case .ok(let ok):
                detail?.read = AreaRead(api: try ok.body.json)
            case .badRequest(let bad):
                readError = (try? bad.body.json.error.message) ?? "Couldn’t read this area. Try again."
            case .notFound:
                detail = nil
                load = .gone
            case .unauthorized:
                await auth.sessionEnded()
            case .undocumented(let status, _):
                readError = "Couldn’t read this area (the server answered \(status))."
            }
        } catch {
            Log.app.error("Area read: \(error.localizedDescription, privacy: .public)")
            readError = "Couldn’t read this area. Check your connection and try again."
        }
    }

    // MARK: The gap

    /// Has Supervibes name the gap between where the area is and where the person wants it, replacing any. It takes a
    /// few seconds, and needs both said.
    func nameGap() async {
        guard !namingGap else { return }
        namingGap = true
        gapError = nil
        defer { namingGap = false }
        do {
            switch try await client.nameAreaGap(path: .init(id: id)) {
            case .ok(let ok):
                detail?.area.gap = AreaGap(api: try ok.body.json)
            case .badRequest(let bad):
                gapError = (try? bad.body.json.error.message) ?? "Couldn’t name the gap. Try again."
            case .notFound:
                detail = nil
                load = .gone
            case .unauthorized:
                await auth.sessionEnded()
            case .undocumented(let status, _):
                gapError = "Couldn’t name the gap (the server answered \(status))."
            }
        } catch {
            Log.app.error("Area gap: \(error.localizedDescription, privacy: .public)")
            gapError = "Couldn’t name the gap. Check your connection and try again."
        }
    }

    /// Saves the gap as the person wrote it, replacing any; true once saved.
    func writeGap(_ input: GapInput) async -> Bool {
        gapError = nil
        if let problem = input.problem {
            gapError = problem
            return false
        }
        if let gap = detail?.area.gap, GapInput(editing: gap) == input { return true }
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = input.body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch try await client.writeAreaGap(path: .init(id: id), body: .json(.init(title: title, body: body))) {
            case .ok(let ok):
                detail?.area.gap = AreaGap(api: try ok.body.json)
                return true
            case .badRequest(let bad):
                gapError = (try? bad.body.json.error.message) ?? "Couldn’t save the gap."
            case .notFound:
                detail = nil
                load = .gone
            case .unauthorized:
                await auth.sessionEnded()
            case .undocumented(let status, _):
                gapError = "Couldn’t save the gap (the server answered \(status))."
            }
        } catch {
            Log.app.error("Area gap: \(error.localizedDescription, privacy: .public)")
            gapError = "Couldn’t save the gap. Check your connection and try again."
        }
        return false
    }

    // MARK: Changes

    /// Saves the area's name, icon and words; true once saved.
    func save(_ input: AreaInput) async -> Bool {
        error = nil
        if let problem = input.problem {
            error = problem
            return false
        }
        guard let current = detail?.area else { return false }
        if input == AreaInput(editing: current) { return true }
        detail?.area = input.applied(to: current)
        do {
            detail?.area = try await areaAPI.update(id, input)
            return true
        } catch {
            detail?.area = current
            self.error = (error as? AreaAPIError)?.message ?? "Couldn’t save this area."
            return false
        }
    }

    /// Removes the area; true when it's gone. Its goals stay, with no area.
    func remove() async -> Bool {
        error = nil
        do {
            try await areaAPI.delete(id)
            return true
        } catch {
            self.error = (error as? AreaAPIError)?.message ?? "Couldn’t remove this area."
            return false
        }
    }

    /// Takes a goal out of the area. It keeps going, with no area.
    func takeOut(_ goal: Goal) {
        move(goal, to: nil)
    }

    /// Moves one of the person's other goals into the area.
    func moveIn(_ goal: Goal) {
        move(goal, to: id)
    }

    /// Starts a goal in this area; it shows once the server has it.
    func createGoal(_ input: GoalInput) {
        error = nil
        Task {
            let body = Components.Schemas.NewGoal(new: input, areaId: id)
            do {
                switch try await client.createGoal(body: .json(body)) {
                case .created:
                    await refresh()
                case .badRequest(let bad):
                    error = (try? bad.body.json.error.message) ?? "Couldn’t add that \(input.kind.noun)."
                case .unauthorized:
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    error = "Couldn’t add that goal (the server answered \(status))."
                }
            } catch {
                self.error = "Couldn’t add that goal. Check your connection."
            }
        }
    }

    private func move(_ goal: Goal, to areaId: String?) {
        error = nil
        let before = detail
        if areaId == nil { detail?.goals.removeAll { $0.id == goal.id } }
        Task {
            do {
                try await areaAPI.setGoalArea(goalId: goal.id, areaId: areaId)
                await refresh()
            } catch {
                detail = before
                self.error = (error as? AreaAPIError)?.message ?? "Couldn’t move that goal."
            }
        }
    }

    /// The person's goals outside this area, for "Move a goal here". Quietly empty if they can't be loaded.
    private func loadOtherGoals() async {
        do {
            if case .ok(let ok) = try await client.listGoals(query: .init(timeZone: TimeZone.current.identifier)) {
                otherGoals = try ok.body.json.goals.map(Goal.init(api:)).filter { $0.areaId != id }
            }
        } catch {
            Log.app.error("Area goals: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Area {
    init(api area: Components.Schemas.Area) {
        self.init(
            id: area.id,
            name: area.name,
            icon: area.icon,
            now: area.now,
            want: area.want,
            status: area.status.flatMap { GoalStatus(rawValue: $0.rawValue) },
            goalIds: area.goalIds,
            gap: area.gap.map(AreaGap.init(api:)),
            questId: area.questId ?? nil
        )
    }
}

extension AreaGap {
    init(api gap: Components.Schemas.AreaGap) {
        self.init(title: gap.title, body: gap.body, by: gap.by == .you ? .you : .supervibes, at: gap.at)
    }
}

extension AreaDetail {
    init(api body: Components.Schemas.AreaDetail) {
        self.init(
            area: Area(api: body.area),
            today: body.today,
            trajectory: body.trajectory.map {
                AreaTrajectoryDay(day: $0.day, status: $0.status.flatMap { GoalStatus(rawValue: $0.rawValue) }, carried: $0.carried)
            },
            goals: body.goals.map(Goal.init(api:)),
            weeks: Dictionary(body.week.goals.map { ($0.goalId, GoalWeek(api: $0)) }, uniquingKeysWith: { first, _ in first }),
            read: body.read.map(AreaRead.init(api:))
        )
    }
}

extension AreaRead {
    init(api read: Components.Schemas.AreaRead) {
        self.init(headline: read.headline, summary: read.summary, goalIds: read.goalIds, usedCalendar: read.usedCalendar, createdAt: read.createdAt)
    }
}
