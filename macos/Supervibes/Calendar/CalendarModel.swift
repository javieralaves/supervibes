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

    /// Shows the day a block is on, for opening it from a notice. False if it isn't loaded.
    func show(_ blockId: String) -> Bool {
        guard let block = block(blockId) else { return false }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: block.startsAt)).day ?? 0
        offset = min(max(days, range.lowerBound), range.upperBound)
        return true
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

    /// Move a block, or change its length, by `delta` minutes (and, moving it, `days` days):
    /// `edge` says which end moves.
    func move(_ blockId: String, edge: BlockEdge, delta: Int, days: Int = 0) {
        guard delta != 0 || days != 0, let before = block(blockId) else { return }
        // Days by the calendar, so a daylight-saving change keeps the clock time; then minutes.
        func shifted(_ date: Date, _ moves: Bool) -> Date {
            guard moves else { return date }
            let day = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
            return day.addingTimeInterval(Double(delta) * 60)
        }
        setTimes(before, startsAt: shifted(before.startsAt, edge != .end), endsAt: shifted(before.endsAt, edge != .start))
    }

    /// A goal's objective for a week; empty clears it. Returns an error to show, or nil.
    func setObjective(_ goalId: String, weekStart: String, _ text: String) async -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = data.objectives
        data.objectives.removeAll { $0.goalId == goalId && $0.weekStart == weekStart }
        if !value.isEmpty { data.objectives.append(.init(goalId: goalId, weekStart: weekStart, objective: value)) }
        let error = await call { client in
            switch try await client.setWeekObjective(path: .init(id: goalId, weekStart: weekStart), body: .json(.init(objective: value))) {
            case .noContent: nil
            case .badRequest(let bad): (try? bad.body.json.error.message) ?? "Couldn’t save that."
            case .notFound: "That goal doesn’t exist anymore."
            case .unauthorized: Self.signedOut
            case .undocumented(let status, _): "Couldn’t save that (the server answered \(status))."
            }
        }
        if error != nil { data.objectives = before }
        return error
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

    // MARK: - Tasks on the calendar

    /// A task dropped on `day` at `start`: a new intention, or its next block moved there.
    func place(_ taskId: String, day: Int, start: Int, minutes: Int) {
        let clockNow = Date()
        guard let task = data.tasks.first(where: { $0.id == taskId }) else { return }
        let startsAt = CalendarDayMath.midnight(day, from: now).addingTimeInterval(Double(start) * 60)
        let endsAt = startsAt.addingTimeInterval(Double(minutes) * 60)
        if let block = data.nextBlocks(now: clockNow)[taskId] {
            if block.startsAt != startsAt { setTimes(block, startsAt: startsAt, endsAt: endsAt) }
            return
        }
        let pending = CalendarBlock(
            id: "pending-\(UUID().uuidString)",
            goalId: task.goalId,
            title: task.title,
            startsAt: startsAt,
            endsAt: endsAt,
            taskId: task.id,
            isPending: true
        )
        data.blocks.append(pending)
        write(undo: { [weak self] in self?.data.blocks.removeAll { $0.id == pending.id } }) { client in
            let body = Components.Schemas.BlockTimes(startsAt: startsAt, endsAt: endsAt)
            switch try await client.scheduleTask(path: .init(taskId: taskId), body: .json(body)) {
            case .created(let created):
                let block = CalendarBlock(api: try created.body.json)
                return .apply { $0.replace(pending.id, with: block) }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t schedule that task.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That task doesn’t exist anymore.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t schedule that task (the server answered \(status)).")
            }
        }
    }

    /// Plan a task for `day` without a time, or take it off its day (nil). A time it had that
    /// hasn't started yet goes: the day is now the plan.
    func plan(_ taskId: String, day: Int?) {
        let clockNow = Date()
        guard let index = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let before = data.tasks[index]
        let dayISO = day.map { CalendarDay.today(CalendarDayMath.midnight($0, from: now)) }
        let unschedule = data.nextBlocks(now: clockNow)[taskId].flatMap { $0.startsAt > clockNow ? $0 : nil }
        if before.plannedFor == dayISO, unschedule == nil { return }
        let blockIndex = unschedule.flatMap { block in data.blocks.firstIndex { $0.id == block.id } }
        data.tasks[index].plannedFor = dayISO
        if let unschedule { data.blocks.removeAll { $0.id == unschedule.id } }
        write(undo: { [weak self] in
            guard let self else { return }
            if let i = self.data.tasks.firstIndex(where: { $0.id == taskId }) { self.data.tasks[i] = before }
            if let unschedule, let blockIndex { self.data.blocks.insert(unschedule, at: min(blockIndex, self.data.blocks.count)) }
        }) { client in
            let body = Components.Schemas.PlanTask(day: dayISO ?? "", unscheduleBlockId: unschedule?.id)
            switch try await client.planTask(path: .init(taskId: taskId), body: .json(body)) {
            case .noContent: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t plan that task.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That task doesn’t exist anymore.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t plan that task (the server answered \(status)).")
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

    // MARK: - The block panel

    /// Save what the person wants out of a session. Returns an error to show, or nil.
    func setDescription(_ blockId: String, _ text: String) async -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let before = block(blockId), value != (before.description ?? "") else { return nil }
        update(blockId) { $0.description = value.isEmpty ? nil : value }
        let error = await call { client in
            switch try await client.setBlockDescription(path: .init(blockId: blockId), body: .json(.init(description: value))) {
            case .noContent: nil
            case .badRequest(let bad): (try? bad.body.json.error.message) ?? "Couldn’t save that."
            case .notFound(let gone): (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .unauthorized: Self.signedOut
            case .undocumented(let status, _): "Couldn’t save that (the server answered \(status))."
            }
        }
        if error != nil { update(blockId) { $0.description = before.description } }
        return error
    }

    /// Prepare (or prepare again) a session's agenda. `when` is how the block reads here.
    func prepareAgenda(_ blockId: String, when: String) async -> String? {
        await call { client in
            switch try await client.prepareAgenda(path: .init(blockId: blockId), body: .json(.init(when: when))) {
            case .ok(let ok):
                let agenda = BlockAgenda(api: try ok.body.json)
                self.update(blockId) { $0.agenda = agenda; $0.hasAgenda = true }
                return nil
            case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t prepare an agenda."
            case .notFound(let gone): return (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .badGateway(let failed): return (try? failed.body.json.error.message) ?? "Couldn’t prepare an agenda right now. Try again."
            case .unauthorized: return Self.signedOut
            case .undocumented(let status, _): return "Couldn’t prepare an agenda (the server answered \(status))."
            }
        }
    }

    /// Draft a recap of a session that's ended.
    func prepareRecap(_ blockId: String) async -> String? {
        await call { client in
            switch try await client.prepareRecap(path: .init(blockId: blockId)) {
            case .ok(let ok):
                let recap = RecapDraft(api: try ok.body.json)
                self.update(blockId) { $0.recap = recap; $0.hasRecapDraft = true; $0.recapDrafting = false }
                return nil
            case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t recap this session."
            case .notFound(let gone): return (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .badGateway(let failed): return (try? failed.body.json.error.message) ?? "Couldn’t recap this session right now. Try again."
            case .unauthorized: return Self.signedOut
            case .undocumented(let status, _): return "Couldn’t recap this session (the server answered \(status))."
            }
        }
    }

    /// Post a recap to the goal's activity, with the draft's links in `keep`.
    func postRecap(_ blockId: String, body: String, keep: [NoteItem.Breadcrumb], markTaskDone: Bool) async -> String? {
        let error = await call { client in
            let input = Components.Schemas.PostRecap(body: body, keep: keep.map(\.url.absoluteString), markTaskDone: markTaskDone)
            switch try await client.postRecap(path: .init(blockId: blockId), body: .json(input)) {
            case .noContent: return nil
            case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t post that recap."
            case .notFound(let gone): return (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .unauthorized: return Self.signedOut
            case .undocumented(let status, _): return "Couldn’t post that recap (the server answered \(status))."
            }
        }
        guard error == nil else { return error }
        update(blockId) { block in
            block.recapPost = PostedRecap(body: body.trimmingCharacters(in: .whitespacesAndNewlines), breadcrumbs: keep)
            block.hasRecapPost = true
            block.recap = nil
            block.hasRecapDraft = false
            if markTaskDone { block.taskDone = true }
        }
        await refresh()
        return nil
    }

    func discardRecap(_ blockId: String) async -> String? {
        let error = await call { client in
            switch try await client.discardRecap(path: .init(blockId: blockId)) {
            case .noContent: nil
            case .notFound(let gone): (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .unauthorized: Self.signedOut
            case .undocumented(let status, _): "Couldn’t discard that (the server answered \(status))."
            }
        }
        if error == nil { update(blockId) { $0.recap = nil; $0.hasRecapDraft = false; $0.recapDrafting = false } }
        return error
    }

    /// Check off or reopen one of an agenda's tasks.
    func setTaskDone(_ taskId: String, _ done: Bool) async -> String? {
        let error = await call { client in
            switch try await client.setTaskDone(path: .init(taskId: taskId), body: .json(.init(done: done))) {
            case .ok: nil
            case .badRequest(let bad): (try? bad.body.json.error.message) ?? "Couldn’t save that."
            case .notFound: "That task doesn’t exist anymore."
            case .unauthorized: Self.signedOut
            case .undocumented(let status, _): "Couldn’t save that (the server answered \(status))."
            }
        }
        if error == nil { await refresh() }
        return error
    }

    private static let signedOut = "Your session ended. Sign in again."

    /// A panel request: returns an error to show, or nil once done.
    private func call(_ request: (Client) async throws -> String?) async -> String? {
        do {
            let error = try await request(client)
            if error == Self.signedOut { await auth.sessionEnded() }
            return error
        } catch {
            return "Couldn’t reach Supervibes. Check your connection."
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
            hasRecapPost: block.hasRecapPost,
            agenda: block.agenda.map(BlockAgenda.init(api:)),
            recap: block.recap.map(RecapDraft.init(api:)),
            recapPost: block.recapPost.map { PostedRecap(body: $0.body, breadcrumbs: $0.breadcrumbs.compactMap(NoteItem.Breadcrumb.init(api:))) }
        )
    }
}

extension BlockAgenda {
    init(api agenda: Components.Schemas.BlockAgenda) {
        self.init(
            text: agenda.text,
            tasks: agenda.tasks.map { Task(id: $0.id, title: $0.title, minutes: $0.minutes) },
            preparedAt: agenda.preparedAt,
            keptTitle: agenda.keptTitle,
            title: agenda.title,
            description: agenda.description
        )
    }
}

extension RecapDraft {
    init(api recap: Components.Schemas.BlockRecap) {
        self.init(
            planned: recap.planned,
            happened: recap.happened,
            breadcrumbs: recap.breadcrumbs.compactMap(NoteItem.Breadcrumb.init(api:)),
            found: Found(rawValue: recap.found.rawValue) ?? .none,
            taskLooksDone: recap.taskLooksDone,
            preparedAt: recap.preparedAt,
            auto: recap.auto
        )
    }
}

extension NoteItem.Breadcrumb {
    init?(api crumb: Components.Schemas.Breadcrumb) {
        guard let provider = ConnectionItem.Provider(rawValue: crumb.provider.rawValue), let url = URL(string: crumb.url) else { return nil }
        self.init(provider: provider, title: crumb.title, url: url)
    }
}
