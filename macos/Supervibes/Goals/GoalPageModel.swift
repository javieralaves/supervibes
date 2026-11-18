import Foundation
import Observation

/// Loads one goal's page and acts on it through /api/v1: Update status, edit, delete, this week.
@MainActor
@Observable
final class GoalPageModel {
    enum Load: Equatable {
        case loading, loaded
        case gone
        case failed(String)
    }

    let id: String
    private(set) var load: Load = .loading
    private(set) var detail: GoalDetail?
    private(set) var requestingRead = false
    private(set) var readError: String?
    private(set) var headerError: String?
    private(set) var weekState: WeekObjectiveState = .idle

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var polling: Task<Void, Never>?

    /// How often to check whether a background read has landed, as the web page does.
    private static let pollInterval: Duration = .seconds(4)

    init(id: String, auth: AuthModel) {
        self.id = id
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func refresh() async {
        do {
            let output = try await client.getGoal(path: .init(id: id), query: .init(timeZone: TimeZone.current.identifier))
            switch output {
            case .ok(let ok):
                let next = GoalDetail(api: try ok.body.json)
                detail = next
                load = .loaded
                if !next.readPending { requestingRead = false }
                pollWhileReading()
            case .notFound:
                load = .gone
            case .unauthorized:
                await auth.sessionEnded()
            case .badRequest, .undocumented:
                if load != .loaded { load = .failed("Couldn’t load this goal. Try again in a moment.") }
            }
        } catch {
            Log.app.error("Goal: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn’t load this goal. Check your connection and try again.") }
        }
    }

    /// While a read runs on the server, check every few seconds until it lands.
    private func pollWhileReading() {
        guard detail?.readPending == true || requestingRead else {
            polling?.cancel()
            polling = nil
            return
        }
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                self.polling = nil
                await self.refresh()
                return
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    // MARK: Actions

    func updateStatus() {
        readError = nil
        requestingRead = true
        Task {
            do {
                switch try await client.requestGoalRead(path: .init(id: id)) {
                case .accepted:
                    await refresh()
                    pollWhileReading()
                case .notFound:
                    load = .gone
                case .unauthorized:
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    requestingRead = false
                    readError = "Couldn’t start a read (the server answered \(status))."
                }
            } catch {
                requestingRead = false
                readError = "Couldn’t start a read. Check your connection."
            }
        }
    }

    func save(_ input: GoalInput) {
        headerError = nil
        Task {
            let body = Components.Schemas.GoalInput(
                title: input.title,
                description: input.description.isEmpty ? nil : input.description,
                targetDate: input.targetDate,
                icon: .init(rawValue: input.icon) ?? .target02Icon,
                color: .init(rawValue: input.color) ?? .violet
            )
            do {
                switch try await client.updateGoal(path: .init(id: id), body: .json(body)) {
                case .ok(let ok):
                    detail?.goal = Goal(api: try ok.body.json)
                case .badRequest(let bad):
                    headerError = (try? bad.body.json.error.message) ?? "Couldn’t save that."
                case .notFound:
                    load = .gone
                case .unauthorized:
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    headerError = "Couldn’t save (the server answered \(status))."
                }
            } catch {
                headerError = "Couldn’t save. Check your connection."
            }
        }
    }

    /// Deletes the goal; true when it's gone.
    func delete() async -> Bool {
        do {
            switch try await client.deleteGoal(path: .init(id: id)) {
            case .noContent, .notFound:
                return true
            case .unauthorized:
                await auth.sessionEnded()
                return false
            case .undocumented(let status, _):
                headerError = "Couldn’t delete this goal (the server answered \(status))."
                return false
            }
        } catch {
            headerError = "Couldn’t delete this goal. Check your connection."
            return false
        }
    }

    func saveWeek(_ objective: String) {
        guard let week = detail?.week else { return }
        weekState = .saving
        Task {
            do {
                let output = try await client.setWeekObjective(
                    path: .init(id: id, weekStart: week.start),
                    body: .json(.init(objective: objective))
                )
                switch output {
                case .noContent:
                    detail?.week.objective = objective.isEmpty ? nil : objective
                    weekState = .idle
                case .badRequest(let bad):
                    weekState = .failed((try? bad.body.json.error.message) ?? "Couldn’t save that.")
                case .notFound:
                    load = .gone
                case .unauthorized:
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    weekState = .failed("Couldn’t save (the server answered \(status)).")
                }
            } catch {
                weekState = .failed("Couldn’t save. Check your connection.")
            }
        }
    }
}

extension GoalDetail {
    init(api body: Components.Schemas.GoalDetail) {
        self.init(
            goal: Goal(api: body.goal),
            today: body.today,
            read: body.read.map { Read(headline: $0.headline, summary: $0.summary, basedOn: $0.basedOn, createdAt: $0.createdAt) },
            status: body.status.flatMap { status in
                guard let s = GoalStatus(rawValue: status.status.rawValue), let b = StatusBasis(rawValue: status.basis.rawValue) else {
                    return nil
                }
                return Status(status: s, basis: b, reason: status.reason, at: status.at)
            },
            readsInTrajectory: body.readsInTrajectory,
            readPending: body.readPending,
            readError: body.readError,
            canRead: body.canRead,
            week: Week(start: body.week.start, objective: body.week.objective, lastWeek: body.week.lastWeek)
        )
    }
}
