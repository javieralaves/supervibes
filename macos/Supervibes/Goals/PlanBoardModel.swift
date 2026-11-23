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

    // MARK: Making a day fit

    /// Plans each moved task where the panel sends it.
    func move(_ moves: [Fit.Move], of goalId: String) {
        guard let today = data?.today else { return }
        let editor = editor(goalId)
        for move in moves { editor.edit(move.task, move.to.patch(today: today)) }
    }

    /// Protects free time for a goal: a new session there.
    func protect(_ slot: Fit.Slot, for goalId: String) {
        addSession(goalId, slot)
        Task { await saveThenRefresh { client in try await Self.create(client, goalId: goalId, slot) } }
    }

    /// Gives the end of another goal's session to this one: that session ends earlier, and the
    /// time becomes a session for this goal.
    func give(_ give: Fit.Give, to goalId: String) {
        guard let block = data?.blocks.first(where: { $0.id == give.blockId }) else { return }
        if let index = data?.blocks.firstIndex(where: { $0.id == give.blockId }) { data?.blocks[index].end = give.slot.start }
        update(give.fromGoal) { goal in
            goal.protectedBlocks = goal.protectedBlocks.map { $0.start == block.start && $0.end == block.end ? ProtectedBlock(start: block.start, end: give.slot.start) : $0 }
        }
        addSession(goalId, give.slot)
        Task {
            await saveThenRefresh { client in
                let body = Components.Schemas.BlockTimes(startsAt: block.start, endsAt: give.slot.start)
                switch try await client.moveBlock(path: .init(blockId: block.id), body: .json(body)) {
                case .noContent: break
                case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t shorten that session."
                case .notFound: return "That session doesn’t exist anymore."
                case .unauthorized: return Self.signedOut
                case .undocumented(let status, _): return "Couldn’t shorten that session (the server answered \(status))."
                }
                return try await Self.create(client, goalId: goalId, give.slot)
            }
        }
    }

    /// Shows a new session for the goal at once, until the board reloads with the saved one.
    private func addSession(_ goalId: String, _ slot: Fit.Slot) {
        data?.blocks.append(BoardBlock(id: "pending-\(UUID().uuidString)", goalId: goalId, start: slot.start, end: slot.end))
        update(goalId) { $0.protectedBlocks.append(ProtectedBlock(start: slot.start, end: slot.end)) }
    }

    private static let signedOut = "signed-out"

    private static func create(_ client: Client, goalId: String, _ slot: Fit.Slot) async throws -> String? {
        let body = Components.Schemas.NewBlock(
            goalId: goalId, title: nil, startsAt: slot.start.formatted(.iso8601), endsAt: slot.end.formatted(.iso8601), kind: .session, taskId: nil
        )
        return switch try await client.createBlock(body: .json(body)) {
        case .created: nil
        case .badRequest(let bad): (try? bad.body.json.error.message) ?? "Couldn’t protect that time."
        case .notFound(let gone): (try? gone.body.json.error.message) ?? "That goal doesn’t exist anymore."
        case .unauthorized: signedOut
        case .undocumented(let status, _): "Couldn’t protect that time (the server answered \(status))."
        }
    }

    /// Saves a change already on screen, then loads the board again, which also puts it back if
    /// saving failed.
    private func saveThenRefresh(_ save: (Client) async throws -> String?) async {
        taskError = nil
        let message: String?
        do { message = try await save(client) } catch { message = "Couldn’t save that. Check your connection." }
        if message == Self.signedOut { return await auth.sessionEnded() }
        if let message { taskError = message }
        await refresh()
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
            },
            blocks: plan.blocks.map {
                BoardBlock(id: $0.id, goalId: $0.goalId, start: $0.startsAt, end: $0.endsAt, reserved: $0.reserved, taskId: $0.taskId)
            },
            wakeTime: plan.wakeTime,
            sleepStart: plan.sleepStart
        )
    }
}
