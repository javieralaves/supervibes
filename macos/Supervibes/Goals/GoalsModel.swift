import Foundation
import Observation

/// Loads the goals and adds new ones through /api/v1.
@MainActor
@Observable
final class GoalsModel {
    enum Load: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .idle
    private(set) var goals: [Goal] = []
    private(set) var today = CalendarDay.today()
    private(set) var max = 12
    private(set) var error: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func refresh() async {
        if load != .loaded { load = .loading }
        do {
            switch try await client.listGoals(query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                let body = try ok.body.json
                goals = body.goals.map(Goal.init(api:))
                today = body.today
                max = body.max
                load = .loaded
            case .unauthorized:
                await auth.sessionEnded()
            case .badRequest(let bad):
                throw AuthError.server((try? bad.body.json).map { _ in 400 } ?? 400)
            case .undocumented(let status, _):
                throw AuthError.server(status)
            }
        } catch {
            Log.app.error("Goals: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn’t load your goals. Check your connection and try again.") }
        }
    }

    /// Adds the goal right away, faded, and swaps in the saved one when the server has it.
    func create(_ input: GoalInput) {
        error = nil
        let pendingID = "pending-\(UUID().uuidString)"
        goals.append(Goal(
            id: pendingID,
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: input.description.isEmpty ? nil : input.description,
            targetDate: input.targetDate,
            icon: input.icon,
            color: input.color,
            trajectory: [],
            isPending: true
        ))

        Task {
            let body = Components.Schemas.GoalInput(
                title: input.title,
                description: input.description.isEmpty ? nil : input.description,
                targetDate: input.targetDate,
                icon: .init(rawValue: input.icon) ?? .target02Icon,
                color: .init(rawValue: input.color) ?? .violet
            )
            do {
                switch try await client.createGoal(body: .json(body)) {
                case .created(let created):
                    let saved = Goal(api: try created.body.json)
                    goals = goals.map { $0.id == pendingID ? saved : $0 }
                    Log.app.info("Goal created")
                case .badRequest(let bad):
                    fail(pendingID, (try? bad.body.json.error.message) ?? "Couldn’t add that goal.")
                case .unauthorized:
                    goals.removeAll { $0.id == pendingID }
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    fail(pendingID, "Couldn’t add that goal (the server answered \(status)).")
                }
            } catch {
                fail(pendingID, "Couldn’t add that goal. Check your connection.")
            }
        }
    }

    private func fail(_ pendingID: String, _ message: String) {
        goals.removeAll { $0.id == pendingID }
        error = message
    }
}

extension Goal {
    init(api goal: Components.Schemas.Goal) {
        self.init(
            id: goal.id,
            title: goal.title,
            description: goal.description,
            targetDate: goal.targetDate,
            icon: goal.icon,
            color: goal.color,
            trajectory: goal.trajectory.map {
                TrajectoryDay(
                    day: $0.day,
                    status: $0.status.flatMap { GoalStatus(rawValue: $0.rawValue) },
                    basis: $0.basis.flatMap { StatusBasis(rawValue: $0.rawValue) },
                    reason: $0.reason,
                    carried: $0.carried
                )
            }
        )
    }
}
