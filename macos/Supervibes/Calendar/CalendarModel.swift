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
    /// Which days show: the day stepped into, and the first column of the multi-day views.
    private(set) var window: CalendarWindow
    /// The day shown, in days from today.
    var offset: Int { window.offset }
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

    init(auth: AuthModel, span: CalendarSpan = .day) {
        self.auth = auth
        window = CalendarWindow(span: span, now: Date())
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
                let before = self.now
                self.now = Date()
                // Past midnight: the days move on, and what's loaded is fetched for the new day.
                let days = CalendarDayMath.dayOffset(self.now, from: before)
                if days != 0 {
                    self.window.dayChanged(by: days, before: before, now: self.now)
                    await self.refresh()
                    sincePoll = .zero
                    continue
                }
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
                window.setLoaded(range)
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

    /// The day back or forward (Day's arrows); a multi-day view moves to show it if it isn't shown.
    func step(_ by: Int) {
        window.step(by, now: now)
    }

    /// The multi-day views' first column by that many days: their arrows (a page) and scrolling.
    func scroll(_ by: Int) {
        window.scroll(by)
    }

    /// Today, and in a multi-day view, its first column back where it starts.
    func goToToday() {
        window.today(now: now)
    }

    /// Day, Next N days or Week.
    func setSpan(_ span: CalendarSpan) {
        window.setSpan(span, now: now)
    }

    /// Shows the day a block is on, for opening it from a notice. False if it isn't loaded.
    func show(_ blockId: String) -> Bool {
        guard let block = block(blockId) else { return false }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: block.startsAt)).day ?? 0
        window.show(day: days, now: now)
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
    /// Draw a block: a session, reserved time, or time for a task (an open one, or a new one titled
    /// with the block's title).
    func create(day: Int, start: Int, end: Int, goalId: String, title: String?, kind: NewBlockKind = .session) {
        let midnight = CalendarDayMath.midnight(day, from: now)
        let startsAt = midnight.addingTimeInterval(Double(start) * 60)
        let endsAt = midnight.addingTimeInterval(Double(end) * 60)
        var pending = CalendarBlock(id: "pending-\(UUID().uuidString)", goalId: goalId, title: title, startsAt: startsAt, endsAt: endsAt, isPending: true)
        let apiKind: Components.Schemas.NewBlock.KindPayload
        var taskId: String?
        switch kind {
        case .session:
            apiKind = .session
        case .reserved:
            apiKind = .reserved
            pending.reserved = true
        case .task(let id):
            apiKind = .task
            taskId = id
            // An open task brings its own goal and title.
            if let id, let task = data.tasks.first(where: { $0.id == id }) {
                pending.goalId = task.goalId
                pending.title = task.title
            } else if id != nil {
                return
            }
            pending.taskId = id ?? "pending-task-\(UUID().uuidString)"
        }
        UserDefaults.standard.set(pending.goalId, forKey: Self.lastGoalKey)
        data.blocks.append(pending)
        let pendingId = pending.id
        let isNewTask = kind == .task(id: nil)
        write(undo: { [weak self] in self?.data.blocks.removeAll { $0.id == pendingId } }) { client in
            let body = Components.Schemas.NewBlock(
                goalId: goalId, title: title, startsAt: Self.iso(startsAt), endsAt: Self.iso(endsAt), kind: apiKind, taskId: taskId
            )
            switch try await client.createBlock(body: .json(body)) {
            case .created(let created):
                let block = CalendarBlock(api: try created.body.json)
                return .apply { model in
                    model.replace(pendingId, with: block)
                    // A new task joins the open tasks on the next load.
                    if isNewTask { Task { await model.refresh() } }
                }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that block.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That goal doesn’t exist anymore.")
            // Only an import sends an event, and drawing a block never does.
            case .conflict(let taken): return .failed((try? taken.body.json.error.message) ?? "That event is already on your calendar.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that block (the server answered \(status)).")
            }
        }
    }

    // MARK: - Importing events

    /// Imports an event from the person's Google calendars as a session or reserved time in a goal.
    /// It shows straight away, as a drawn block does, and remembers the event it came from.
    func importEvent(_ event: ExternalEvent, goalId: String, kind: ImportKind) {
        guard !data.blocks.contains(where: { $0.source?.key == event.key }) else { return }
        let title = ImportCheck.blockTitle(event.title)
        let times = ImportCheck.blockTimes(event.start, event.end)
        let source = EventSource(key: event.key, calendar: event.calendarName, snapshot: event.snapshot)
        var pending = CalendarBlock(
            id: "pending-\(UUID().uuidString)", goalId: goalId, title: title.isEmpty ? nil : title,
            startsAt: times.start, endsAt: times.end, isPending: true
        )
        pending.reserved = kind == .reserved
        pending.source = source
        data.blocks.append(pending)
        let pendingId = pending.id
        Log.app.info("Calendar import: importing an event as \(kind.rawValue, privacy: .public)")
        write(undo: { [weak self] in self?.data.blocks.removeAll { $0.id == pendingId } }) { client in
            let body = Components.Schemas.NewBlock(
                goalId: goalId,
                title: title.isEmpty ? nil : title,
                startsAt: Self.iso(times.start),
                endsAt: Self.iso(times.end),
                kind: kind == .reserved ? .reserved : .session,
                taskId: nil,
                source: .init(
                    key: event.key,
                    calendar: event.calendarName,
                    snapshot: .init(title: String(event.title.prefix(1000)), startsAt: event.start, endsAt: event.end)
                )
            )
            switch try await client.createBlock(body: .json(body)) {
            case .created(let created):
                let block = CalendarBlock(api: try created.body.json)
                return .apply { model in model.replace(pendingId, with: block) }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t import that event.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That goal doesn’t exist anymore.")
            case .conflict(let taken): return .failed((try? taken.body.json.error.message) ?? "That event is already on your calendar.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t import that event (the server answered \(status)).")
            }
        }
    }

    /// The block imported from the event with this key, if there is one.
    func importedBlock(_ key: String) -> CalendarBlock? {
        data.blocks.first { $0.source?.key == key }
    }

    // MARK: - Changes to imported events

    /// Compares each imported block with its event as the feed has it now: what to offer, by block.
    /// An event missing from the feed only counts as gone when its calendar is still being read,
    /// so unticking a calendar never offers to remove its blocks. Where the block already matches
    /// the event, the baseline catches up without asking.
    func importChanges(events: [ExternalEvent], isReading: (String) -> Bool) -> [String: ImportChange] {
        let byKey = Dictionary(events.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [String: ImportChange] = [:]
        for block in data.blocks where !block.isPending {
            guard let source = block.source else { continue }
            let event = byKey[source.key]
            if event == nil, !isReading(source.calendar) { continue }
            switch ImportCheck.check(source, title: block.title, start: block.startsAt, end: block.endsAt, event: event) {
            case .inStep: break
            case .catchUp(let snapshot): catchUp(block.id, to: snapshot)
            case .changed(let change): changes[block.id] = change
            }
        }
        return changes
    }

    /// Baselines being caught up, so each is sent once.
    @ObservationIgnored private var catchingUp: Set<String> = []

    private func catchUp(_ blockId: String, to snapshot: EventSource.Snapshot) {
        guard !catchingUp.contains(blockId) else { return }
        catchingUp.insert(blockId)
        Task {
            defer { catchingUp.remove(blockId) }
            let body = Components.Schemas.BlockSourceSync(snapshot: Self.snapshot(snapshot))
            guard case .ok(let ok) = try? await client.syncBlockSource(path: .init(blockId: blockId), body: .json(body)),
                  let saved = try? ok.body.json else { return }
            replace(blockId, with: CalendarBlock(api: saved))
            Log.app.info("Calendar import: caught up an imported block with its event")
        }
    }

    /// Takes a change: its title and times go on the block, or, for an event that's gone, the block
    /// is removed. The event as it is now becomes the baseline.
    func takeChange(_ blockId: String, _ change: ImportChange) {
        guard let before = block(blockId), let event = change.event else { return remove(blockId) }
        update(blockId) { block in
            if let title = change.title { block.title = title.isEmpty ? nil : title }
            if let times = change.times {
                block.startsAt = times.start
                block.endsAt = times.end
            }
            block.source = block.source.map { EventSource(key: $0.key, calendar: $0.calendar, snapshot: event) }
        }
        syncSource(blockId, before: before, change: change, snapshot: event, take: true)
    }

    /// Keeps the block as it is: the event as it is now becomes the baseline, or, for an event
    /// that's gone, the block lets go of it and stays.
    func keepBlock(_ blockId: String, _ change: ImportChange) {
        guard let before = block(blockId) else { return }
        guard let event = change.event else {
            update(blockId) { $0.source = nil }
            write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
                switch try await client.unlinkBlockSource(path: .init(blockId: blockId)) {
                case .noContent: return .done
                case .notFound: return .gone
                case .unauthorized: return .signedOut
                case .undocumented(let status, _): return .failed("Couldn’t keep that block (the server answered \(status)).")
                }
            }
            return
        }
        update(blockId) { block in
            block.source = block.source.map { EventSource(key: $0.key, calendar: $0.calendar, snapshot: event) }
        }
        syncSource(blockId, before: before, change: change, snapshot: event, take: false)
    }

    private func syncSource(_ blockId: String, before: CalendarBlock, change: ImportChange, snapshot: EventSource.Snapshot, take: Bool) {
        let title = take ? change.title : nil
        let times = take ? change.times : nil
        write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
            let body = Components.Schemas.BlockSourceSync(
                snapshot: Self.snapshot(snapshot),
                title: title,
                startsAt: times?.start,
                endsAt: times?.end
            )
            switch try await client.syncBlockSource(path: .init(blockId: blockId), body: .json(body)) {
            case .ok(let ok):
                let block = CalendarBlock(api: try ok.body.json)
                return .apply { model in model.replace(blockId, with: block) }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that change.")
            case .notFound: return .gone
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that change (the server answered \(status)).")
            }
        }
    }

    private static func snapshot(_ snapshot: EventSource.Snapshot) -> Components.Schemas.BlockSourceSnapshot {
        .init(title: String(snapshot.title.prefix(1000)), startsAt: snapshot.startsAt, endsAt: snapshot.endsAt)
    }

    /// Rename a block or give it another goal. An intention keeps its title when it's left empty.
    func saveDetails(_ blockId: String, goalId: String, title: String?) {
        UserDefaults.standard.set(goalId, forKey: Self.lastGoalKey)
        guard let before = block(blockId) else { return }
        // A task's time is named by the task: renaming one renames the other.
        if let taskId = before.taskId, let title, title != before.title, data.task(taskId) != nil {
            editTask(taskId, TaskPatch(title: title))
        }
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

    /// Make protected time reserved (kept for its own sake) or a session again. Reserving it drops
    /// the session's agenda and draft recap, as the server does.
    func setReserved(_ blockId: String, _ reserved: Bool) {
        guard let before = block(blockId), !before.isIntention, before.reserved != reserved else { return }
        update(blockId) { block in
            block.reserved = reserved
            if reserved {
                block.hasAgenda = false
                block.agenda = nil
                block.hasRecapDraft = false
                block.recap = nil
            }
        }
        write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
            switch try await client.setBlockReserved(path: .init(blockId: blockId), body: .json(.init(reserved: reserved))) {
            case .noContent: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that block.")
            case .notFound: return .gone
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that block (the server answered \(status)).")
            }
        }
    }

    /// Make a block a session, reserved time or a task's time. Protected time becomes a task's time
    /// by making a task from its title and description; a task's time lets go of its task, which
    /// stays open.
    func setKind(_ blockId: String, _ kind: BlockKind) {
        guard let before = block(blockId), before.kind != kind else { return }
        if kind == .task, (before.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Give this block a title first: it becomes the task."
            return
        }
        update(blockId) { block in
            switch kind {
            case .task:
                block.taskId = "pending-task-\(UUID().uuidString)"
                block.reserved = false
                block.description = nil
            case .session, .reserved:
                block.taskId = nil
                block.fromSuggestion = nil
                block.taskDone = false
                block.reserved = kind == .reserved
            }
            if kind == .reserved {
                block.hasAgenda = false
                block.agenda = nil
                block.hasRecapDraft = false
                block.recap = nil
            }
        }
        let apiKind: Components.Schemas.BlockKind.KindPayload = switch kind {
        case .session: .session
        case .reserved: .reserved
        case .task: .task
        }
        write(undo: { [weak self] in self?.replace(blockId, with: before) }) { client in
            switch try await client.setBlockKind(path: .init(blockId: blockId), body: .json(.init(kind: apiKind))) {
            case .ok(let ok):
                let block = CalendarBlock(api: try ok.body.json)
                return .apply { model in
                    model.replace(blockId, with: block)
                    // A new task joins the open tasks on the next load.
                    if kind == .task { Task { await model.refresh() } }
                }
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t change that block.")
            case .notFound: return .gone
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t change that block (the server answered \(status)).")
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

    // MARK: - Giving time

    /// Give part of a session to another goal: the session ends `minutes` earlier, and that time is
    /// protected for the other goal instead.
    func giveTime(_ blockId: String, minutes: Int, to goalId: String) {
        guard minutes > 0, let block = block(blockId), !block.isIntention else { return }
        let cut = block.endsAt.addingTimeInterval(-Double(minutes) * 60)
        guard cut > block.startsAt else { return giveBlock(blockId, to: goalId) }
        let day = CalendarDayMath.dayOffset(cut, from: now)
        let start = CalendarDayMath.minutes(cut)
        move(blockId, edge: .end, delta: -minutes)
        create(day: day, start: start, end: start + minutes, goalId: goalId, title: nil)
    }

    /// Give all of a block to another goal; it keeps its time and title.
    func giveBlock(_ blockId: String, to goalId: String) {
        guard let block = block(blockId), block.goalId != goalId else { return }
        saveDetails(blockId, goalId: goalId, title: block.title)
    }

    private func editTask(_ taskId: String, _ patch: TaskPatch) {
        guard let index = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let before = data.tasks[index]
        var after = before
        if let title = patch.title { after.title = title }
        if let minutes = patch.minutes { after.minutes = minutes }
        if patch.plannedFor != nil || patch.plannedWeek != nil { after = placed(before, patch) }
        if let day = patch.dueOn { after.dueOn = day.isEmpty ? nil : day }
        data.tasks[index] = after
        write(undo: { [weak self] in self?.replaceTask(taskId, with: before) }) { client in
            let body = Components.Schemas.TaskPatch(
                title: patch.title, description: patch.description, minutes: patch.minutes,
                plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, dueOn: patch.dueOn
            )
            switch try await client.editTask(path: .init(taskId: taskId), body: .json(body)) {
            case .ok: return .done
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t save that.")
            case .notFound: return .failed("That task doesn’t exist anymore.")
            case .unauthorized: return .signedOut
            case .undocumented(let status, _): return .failed("Couldn’t save that (the server answered \(status)).")
            }
        }
    }

    /// A task with its planned day and week changed as the server will (TaskItem.placed).
    private func placed(_ task: CalendarTask, _ patch: TaskPatch) -> CalendarTask {
        let item = task.item.placed(plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, today: CalendarDay.today(now))
        var after = task
        after.plannedFor = item.plannedFor
        after.plannedWeek = item.plannedWeek
        return after
    }

    private func replaceTask(_ id: String, with task: CalendarTask) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index] = task
    }

    // MARK: - The block panel

    /// Save what the person wants out of a session. Returns an error to show, or nil.
    func setDescription(_ blockId: String, _ text: String) async -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let before = block(blockId), value != (data.description(of: before) ?? "") else { return nil }
        // A task's time is described by its task: the server saves it there.
        if let taskId = before.taskId {
            guard let index = data.tasks.firstIndex(where: { $0.id == taskId }) else { return "That task isn’t open anymore." }
            let task = data.tasks[index]
            data.tasks[index].description = value.isEmpty ? nil : value
            let error = await call { client in
                switch try await client.setBlockDescription(path: .init(blockId: blockId), body: .json(.init(description: value))) {
                case .noContent: nil
                case .badRequest(let bad): (try? bad.body.json.error.message) ?? "Couldn’t save that."
                case .notFound(let gone): (try? gone.body.json.error.message) ?? "That task doesn’t exist anymore."
                case .unauthorized: Self.signedOut
                case .undocumented(let status, _): "Couldn’t save that (the server answered \(status))."
                }
            }
            if error != nil { replaceTask(taskId, with: task) }
            return error
        }
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

    /// Suggest an aim for a session that doesn't say what it's for yet. Nothing is saved;
    /// `instead` are aims already suggested and passed over.
    func suggestFocus(_ blockId: String, when: String, instead: [String]) async -> FocusOutcome {
        var suggestion: FocusSuggestion?
        let error = await call { client in
            switch try await client.suggestFocus(
                path: .init(blockId: blockId),
                body: .json(.init(when: when, instead: instead.isEmpty ? nil : instead))
            ) {
            case .ok(let ok):
                let body = try ok.body.json
                suggestion = FocusSuggestion(aim: body.aim, why: body.why)
                return nil
            case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t suggest a focus."
            case .notFound(let gone): return (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .badGateway(let failed): return (try? failed.body.json.error.message) ?? "Couldn’t suggest a focus right now. Try again."
            case .unauthorized: return Self.signedOut
            case .undocumented(let status, _): return "Couldn’t suggest a focus (the server answered \(status))."
            }
        }
        if let suggestion { return .suggested(suggestion) }
        return .failed(error ?? "Couldn’t suggest a focus.")
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
                CalendarTask(
                    id: $0.id, goalId: $0.goalId, title: $0.title, minutes: $0.minutes,
                    plannedFor: $0.plannedFor, plannedWeek: $0.plannedWeek, dueOn: $0.dueOn, description: $0.description
                )
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
            reserved: block.reserved,
            taskDone: block.taskDone,
            hasAgenda: block.hasAgenda,
            hasRecapDraft: block.hasRecapDraft,
            recapDrafting: block.recapDrafting,
            hasRecapPost: block.hasRecapPost,
            agenda: block.agenda.map(BlockAgenda.init(api:)),
            recap: block.recap.map(RecapDraft.init(api:)),
            recapPost: block.recapPost.map { PostedRecap(body: $0.body, breadcrumbs: $0.breadcrumbs.compactMap(NoteItem.Breadcrumb.init(api:))) },
            source: block.source.map { source in
                EventSource(
                    key: source.key,
                    calendar: source.calendar,
                    snapshot: .init(title: source.snapshot.title, startsAt: source.snapshot.startsAt, endsAt: source.snapshot.endsAt)
                )
            }
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
