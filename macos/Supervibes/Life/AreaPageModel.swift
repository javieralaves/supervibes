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
                detail = AreaDetail(api: try ok.body.json)
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
            let body = Components.Schemas.NewGoal(
                title: input.title,
                description: input.description.isEmpty ? nil : input.description,
                targetDate: input.targetDate,
                icon: .init(rawValue: input.icon) ?? .target02Icon,
                color: .init(rawValue: input.color) ?? .violet,
                areaId: id
            )
            do {
                switch try await client.createGoal(body: .json(body)) {
                case .created:
                    await refresh()
                case .badRequest(let bad):
                    error = (try? bad.body.json.error.message) ?? "Couldn’t add that goal."
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
            goalIds: area.goalIds
        )
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
            weeks: Dictionary(body.week.goals.map { ($0.goalId, GoalWeek(api: $0)) }, uniquingKeysWith: { first, _ in first })
        )
    }
}
