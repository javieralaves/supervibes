import Foundation
import Observation

/// Loads the planning board across goals (GET /api/v1/plan) and changes its tasks, a TaskEditor per
/// goal, the same way the goal page does.
@MainActor
@Observable
final class PlanBoardModel {
    enum Load: Equatable {
        case loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .loading
    private(set) var data: BoardData?
    private(set) var taskError: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var editors: [String: TaskEditor] = [:]

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func refresh() async {
        do {
            switch try await client.getPlan(query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                data = BoardData(api: try ok.body.json)
                load = .loaded
            case .unauthorized:
                await auth.sessionEnded()
            case .badRequest, .undocumented:
                if load != .loaded { load = .failed("Couldn’t load your plan. Try again in a moment.") }
            }
        } catch {
            Log.app.error("Plan: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn’t load your plan. Check your connection and try again.") }
        }
    }

    /// What a goal's cards and lanes can do.
    func actions(for goalId: String) -> TaskActions {
        editor(goalId).actions
    }

    private func editor(_ goalId: String) -> TaskEditor {
        if let editor = editors[goalId] { return editor }
        let editor = TaskEditor(
            goalId: goalId,
            lists: TaskEditor.Lists(
                tasks: { [weak self] in self?.data?.goal(goalId)?.tasks },
                setTasks: { [weak self] tasks in self?.update(goalId) { $0.tasks = tasks } },
                done: { [weak self] in self?.data?.goal(goalId)?.done },
                setDone: { [weak self] done in self?.update(goalId) { $0.done = done } },
                today: { [weak self] in self?.data?.today }
            ),
            client: client,
            auth: auth,
            onError: { [weak self] in self?.taskError = $0 },
            // The goal was deleted elsewhere: load the board again without it.
            onGone: { [weak self] in Task { await self?.refresh() } }
        )
        editors[goalId] = editor
        return editor
    }

    private func update(_ goalId: String, _ change: (inout BoardGoal) -> Void) {
        guard let index = data?.goals.firstIndex(where: { $0.id == goalId }) else { return }
        change(&data!.goals[index])
    }
}

extension BoardData {
    init(api plan: Components.Schemas.Plan) {
        self.init(
            today: plan.today,
            clock: plan.clock.flatMap { Clock(rawValue: $0.rawValue) },
            goals: plan.goals.map { goal in
                BoardGoal(
                    id: goal.id,
                    title: goal.title,
                    icon: goal.icon,
                    color: goal.color,
                    objective: goal.objective,
                    tasks: goal.tasks.map { TaskItem(api: $0) },
                    done: goal.done.map { TaskItem(api: $0) },
                    protectedBlocks: goal.protectedBlocks.map { ProtectedBlock(start: $0.startsAt, end: $0.endsAt) }
                )
            }
        )
    }
}
