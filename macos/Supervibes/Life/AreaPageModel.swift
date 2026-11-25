import Foundation
import Observation

/// One area's page: its words, its status over the last weeks and its goals, through /api/v1.
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

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(id: String, auth: AuthModel) {
        self.id = id
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func refresh() async {
        do {
            switch try await client.getArea(path: .init(id: id), query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                detail = AreaDetail(api: try ok.body.json)
                load = .loaded
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
