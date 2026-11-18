import Foundation
import Observation

/// Loads the calendar through /api/v1 and keeps its clock and shown day.
@MainActor
@Observable
final class CalendarModel {
    enum Load: Equatable {
        case loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .loading
    private(set) var data = CalendarData(blocks: [], goals: [], tasks: [], sleepStart: 23 * 60, wakeTime: 7 * 60, clock: nil, objectives: [])
    /// Days from today.
    private(set) var offset = 0
    /// The calendar's clock, to the minute.
    private(set) var now = Date()
    private(set) var error: String?
    /// How far back and ahead the loaded blocks go.
    private(set) var range = -36...42

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var ticking: Task<Void, Never>?

    /// How often to check for recaps drafting themselves in the background, as the web page does.
    private static let recapPoll: Duration = .seconds(15)

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    func start() async {
        await refresh()
        ticking?.cancel()
        ticking = Task { [weak self] in
            var sincePoll: Duration = .zero
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                self.now = Date()
                sincePoll += .seconds(15)
                if sincePoll >= Self.recapPoll, self.data.blocks.contains(where: \.recapDrafting) {
                    sincePoll = .zero
                    await self.refresh()
                }
            }
        }
    }

    func stop() {
        ticking?.cancel()
        ticking = nil
    }

    func refresh() async {
        do {
            switch try await client.getCalendar(query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                let body = try ok.body.json
                data = CalendarData(api: body)
                range = -body.daysBack...body.daysAhead
                now = Date()
                load = .loaded
            case .unauthorized:
                await auth.sessionEnded()
            case .badRequest, .undocumented:
                if load != .loaded { load = .failed("Couldn’t load your calendar. Try again in a moment.") }
            }
        } catch {
            Log.app.error("Calendar: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn’t load your calendar. Check your connection and try again.") }
        }
    }

    /// The arrows (and ← →): a day back or forward, within what's loaded.
    func step(_ by: Int) {
        offset = min(max(offset + by, range.lowerBound), range.upperBound)
    }

    func goToToday() {
        offset = 0
    }

    // MARK: - Changing blocks

    /// The goal a new block starts with: the last one used, else the first.
    var defaultGoalId: String? {
        let last = UserDefaults.standard.string(forKey: Self.lastGoalKey)
        return data.goals.contains { $0.id == last } ? last : data.goals.first?.id
    }

    private static let lastGoalKey = "sv-calendar-last-goal"

    /// Protect time drawn on `day` (days from today), from `start` to `end` minutes after midnight.
    func create(day: Int, start: Int, end: Int, goalId: String, title: String?) {
        UserDefaults.standard.set(goalId, forKey: Self.lastGoalKey)
        let midnight = CalendarDayMath.midnight(day, from: now)
        let pending = CalendarBlock(
            id: "pending-\(UUID().uuidString)",
            goalId: goalId,
            title: title,
            startsAt: midnight.addingTimeInterval(Double(start) * 60),
            endsAt: midnight.addingTimeInterval(Double(end) * 60),
            isPending: true
        )
        data.blocks.append(pending)
        write(undo: { [weak self] in self?.data.blocks.removeAll { $0.id == pending.id } }) { client in
            let body = Components.Schemas.NewBlock(goalId: goalId, title: title, startsAt: Self.iso(pending.startsAt), endsAt: Self.iso(pending.endsAt))
            switch try await client.createBlock(body: .json(body)) {
            case .created(let created):
                let block = CalendarBlock(api: try created.body.json)
                return .apply { $0.replace(pending.id, with: block) }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that block.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That goal doesn’t exist anymore.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that block (the server answered \(status)).")
            }
        }
    }

    /// Rename a block or give it another goal. An intention keeps its title when it's left empty.
    func saveDetails(_ blockId: String, goalId: String, title: String?) {
        UserDefaults.standard.set(goalId, forKey: Self.lastGoalKey)
        guard let before = block(blockId) else { return }
        update(blockId) { block in
            block.title = block.isIntention ? (title ?? block.title) : title
            if block.goalId != goalId {
                block.goalId = goalId
                block.hasAgenda = false
                block.hasRecapDraft = false
            }
        }
        write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
            switch try await client.updateBlock(path: .init(blockId: blockId), body: .json(.init(goalId: goalId, title: title))) {
            case .noContent: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that block.")
            case .notFound: return .gone
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that block (the server answered \(status)).")
            }
        }
    }

    /// Move a block, or change its length, by `delta` minutes: `edge` says which end moves.
    func move(_ blockId: String, edge: BlockEdge, delta: Int) {
        guard delta != 0, let before = block(blockId) else { return }
        let shift = Double(delta) * 60
        let startsAt = before.startsAt.addingTimeInterval(edge == .end ? 0 : shift)
        let endsAt = before.endsAt.addingTimeInterval(edge == .start ? 0 : shift)
        setTimes(before, startsAt: startsAt, endsAt: endsAt)
    }

    /// The same time, a day later.
    func moveToTomorrow(_ blockId: String) {
        guard let before = block(blockId) else { return }
        let calendar = Calendar.current
        setTimes(
            before,
            startsAt: calendar.date(byAdding: .day, value: 1, to: before.startsAt) ?? before.startsAt,
            endsAt: calendar.date(byAdding: .day, value: 1, to: before.endsAt) ?? before.endsAt
        )
    }

    private func setTimes(_ before: CalendarBlock, startsAt: Date, endsAt: Date) {
        update(before.id) { block in
            block.startsAt = startsAt
            block.endsAt = endsAt
        }
        write(undo: { [weak self] in self?.replace(before.id, with: before) }) { client in
            let body = Components.Schemas.BlockTimes(startsAt: startsAt, endsAt: endsAt)
            switch try await client.moveBlock(path: .init(blockId: before.id), body: .json(body)) {
            case .noContent: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t move that block.")
            case .notFound: return .gone
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t move that block (the server answered \(status)).")
            }
        }
    }

    /// Mark an intention's task done, or reopen it.
    func toggleDone(_ blockId: String) {
        guard let before = block(blockId), before.taskId != nil else { return }
        let done = !before.taskDone
        update(blockId) { $0.taskDone = done }
        write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
            switch try await client.setBlockTaskDone(path: .init(blockId: blockId), body: .json(.init(done: done))) {
            case .noContent: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That task doesn’t exist anymore.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that (the server answered \(status)).")
            }
        }
    }

    func remove(_ blockId: String) {
        guard let index = data.blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let before = data.blocks.remove(at: index)
        write(undo: { [weak self] in
            guard let self else { return }
            self.data.blocks.insert(before, at: min(index, self.data.blocks.count))
        }) { client in
            switch try await client.deleteBlock(path: .init(blockId: blockId)) {
            case .noContent, .notFound: return .done
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t remove that block (the server answered \(status)).")
            }
        }
    }

    // MARK: - Saving

    private enum Outcome {
        case done
        /// Done, with something to put on screen (a saved block in place of its pending one).
        case apply(@MainActor (CalendarModel) -> Void)
        case failed(String)
        /// The block went away somewhere else.
        case gone
        case signedOut
    }

    /// Writes in flight; the calendar reloads once they've all landed, as the web revalidates.
    @ObservationIgnored private var writes = 0

    /// Runs a request after the change is already on screen; on failure, puts it back and says why.
    private func write(undo: @escaping @MainActor () -> Void, _ request: @escaping (Client) async throws -> Outcome) {
        error = nil
        writes += 1
        Task {
            let outcome: Outcome
            do {
                outcome = try await request(client)
            } catch {
                outcome = .failed("Couldn’t save that. Check your connection.")
            }
            writes -= 1
            switch outcome {
            case .done:
                break
            case .apply(let change):
                change(self)
            case .failed(let message):
                undo()
                error = message
            case .gone:
                undo()
                error = "That block doesn’t exist anymore."
            case .signedOut:
                undo()
                await auth.sessionEnded()
                return
            }
            // Moving an intention plans its task for the new day; marking it done takes it off the strip.
            if writes == 0 { await refresh() }
        }
    }

    private func block(_ id: String) -> CalendarBlock? { data.blocks.first { $0.id == id } }

    private func update(_ id: String, _ change: (inout CalendarBlock) -> Void) {
        guard let index = data.blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&data.blocks[index])
    }

    private func replace(_ id: String, with block: CalendarBlock) {
        guard let index = data.blocks.firstIndex(where: { $0.id == id }) else { return }
        data.blocks[index] = block
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

extension CalendarData {
    init(api body: Components.Schemas.Calendar) {
        self.init(
            blocks: body.blocks.map(CalendarBlock.init(api:)),
            goals: body.goals.map { CalendarGoal(id: $0.id, title: $0.title, icon: $0.icon, color: $0.color) },
            tasks: body.tasks.map {
                CalendarTask(id: $0.id, goalId: $0.goalId, title: $0.title, minutes: $0.minutes, plannedFor: $0.plannedFor, dueOn: $0.dueOn)
            },
            sleepStart: body.settings.sleepStart,
            wakeTime: body.settings.wakeTime,
            clock: body.settings.clock.flatMap { Clock(rawValue: $0.rawValue) },
            objectives: body.objectives.map { WeekObjective(goalId: $0.goalId, weekStart: $0.weekStart, objective: $0.objective) }
        )
    }
}

extension CalendarBlock {
    init(api block: Components.Schemas.CalendarBlock) {
        self.init(
            id: block.id,
            goalId: block.goalId,
            title: block.title,
            description: block.description,
            startsAt: block.startsAt,
            endsAt: block.endsAt,
            fromSuggestion: block.fromSuggestion,
            taskId: block.taskId,
            taskDone: block.taskDone,
            hasAgenda: block.hasAgenda,
            hasRecapDraft: block.hasRecapDraft,
            recapDrafting: block.recapDrafting,
            hasRecapPost: block.hasRecapPost
        )
    }
}
