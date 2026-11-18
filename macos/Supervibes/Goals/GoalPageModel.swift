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
    private(set) var taskError: String?
    /// Bumped when the page is clicked outside the tasks, to close an open one.
    private(set) var closeSignal = 0

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

    func backgroundTapped() {
        closeSignal += 1
    }

    // MARK: Tasks

    /// What the Tasks section can do, wired to this model.
    var taskActions: TaskActions {
        TaskActions(
            add: { [weak self] in self?.addTask($0) },
            toggle: { [weak self] in self?.toggle($0) },
            edit: { [weak self] in self?.edit($0, $1) },
            delete: { [weak self] in self?.deleteTask($0) },
            reorder: { [weak self] in self?.reorder($0) },
            acceptSuggestion: { [weak self] in self?.accept($0) },
            passOnSuggestion: { [weak self] in self?.passOn($0) },
            refresh: { [weak self] in self?.updateStatus() }
        )
    }

    private func addTask(_ title: String) {
        let pending = TaskItem(id: "pending-\(UUID().uuidString)", title: title, minutes: TaskItem.defaultMinutes, isPending: true)
        detail?.tasks.append(pending)
        taskRequest(undo: { [weak self] in self?.detail?.tasks.removeAll { $0.id == pending.id } }) { client, id in
            switch try await client.addTask(path: .init(id: id), body: .json(.init(title: title))) {
            case .created(let created): .replace(pending.id, TaskItem(api: try created.body.json))
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t add that task.")
            case .notFound: .gone
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t add that task (the server answered \(status)).")
            }
        }
    }

    /// Checking a task off moves it to the goal's activity, so it leaves the list.
    private func toggle(_ task: TaskItem) {
        guard let index = detail?.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        detail?.tasks.remove(at: index)
        taskRequest(undo: { [weak self] in self?.detail?.tasks.insert(task, at: min(index, self?.detail?.tasks.count ?? 0)) }) { client, _ in
            switch try await client.setTaskDone(path: .init(taskId: task.id), body: .json(.init(done: !task.done))) {
            case .ok: .done
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t check that off.")
            case .notFound: .failed("That task doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t check that off (the server answered \(status)).")
            }
        }
    }

    private func edit(_ task: TaskItem, _ patch: TaskPatch) {
        guard let index = detail?.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let before = detail!.tasks[index]
        var after = before
        if let title = patch.title { after.title = title }
        if let description = patch.description { after.description = description.isEmpty ? nil : description }
        if let minutes = patch.minutes { after.minutes = minutes }
        if let day = patch.plannedFor { after.plannedFor = day.isEmpty ? nil : day }
        if let day = patch.dueOn { after.dueOn = day.isEmpty ? nil : day }
        detail?.tasks[index] = after
        taskRequest(undo: { [weak self] in self?.replace(task.id, with: before) }) { client, _ in
            let body = Components.Schemas.TaskPatch(
                title: patch.title, description: patch.description, minutes: patch.minutes,
                plannedFor: patch.plannedFor, dueOn: patch.dueOn
            )
            return switch try await client.editTask(path: .init(taskId: task.id), body: .json(body)) {
            case .ok(let ok): .replace(task.id, TaskItem(api: try ok.body.json, keeping: after))
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t save that.")
            case .notFound: .failed("That task doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t save that (the server answered \(status)).")
            }
        }
    }

    private func deleteTask(_ task: TaskItem) {
        guard let index = detail?.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        detail?.tasks.remove(at: index)
        taskRequest(undo: { [weak self] in self?.detail?.tasks.insert(task, at: min(index, self?.detail?.tasks.count ?? 0)) }) { client, _ in
            switch try await client.deleteTask(path: .init(taskId: task.id)) {
            case .noContent, .notFound: .done
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t delete that task (the server answered \(status)).")
            }
        }
    }

    /// Shows the new order at once and saves it in the background.
    private func reorder(_ ids: [String]) {
        guard let tasks = detail?.tasks else { return }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        detail?.tasks = ids.compactMap { byID[$0] }
        taskRequest(undo: { [weak self] in self?.detail?.tasks = tasks }) { client, id in
            switch try await client.reorderTasks(path: .init(id: id), body: .json(.init(ids: ids))) {
            case .noContent: .done
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t reorder these tasks.")
            case .notFound: .gone
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t reorder (the server answered \(status)).")
            }
        }
    }

    /// "Add" on a suggestion: it becomes a task at the end, keeping its estimate and reason.
    private func accept(_ suggestion: TaskSuggestion) {
        let pending = TaskItem(
            id: "pending-\(UUID().uuidString)", title: suggestion.title,
            description: suggestion.why.isEmpty ? nil : suggestion.why, minutes: suggestion.minutes, isPending: true
        )
        let suggestions = detail?.suggestions ?? []
        detail?.suggestions.removeAll { $0 == suggestion }
        detail?.tasks.append(pending)
        taskRequest(undo: { [weak self] in
            self?.detail?.tasks.removeAll { $0.id == pending.id }
            self?.detail?.suggestions = suggestions
        }) { client, id in
            switch try await client.acceptSuggestion(path: .init(id: id), body: .json(.init(title: suggestion.title))) {
            case .created(let created): .replace(pending.id, TaskItem(api: try created.body.json))
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t add that suggestion.")
            case .notFound(let gone): .failed((try? gone.body.json.error.message) ?? "That suggestion doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t add that suggestion (the server answered \(status)).")
            }
        }
    }

    /// "Not now" on a suggestion: hide it, and later reads won't suggest it again.
    private func passOn(_ suggestion: TaskSuggestion) {
        let suggestions = detail?.suggestions ?? []
        detail?.suggestions.removeAll { $0 == suggestion }
        taskRequest(undo: { [weak self] in self?.detail?.suggestions = suggestions }) { client, id in
            switch try await client.passOnSuggestion(path: .init(id: id), body: .json(.init(title: suggestion.title))) {
            case .noContent: .done
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t pass on that suggestion.")
            case .notFound(let gone): .failed((try? gone.body.json.error.message) ?? "That suggestion doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t pass on that (the server answered \(status)).")
            }
        }
    }

    private enum TaskOutcome {
        case done
        case replace(String, TaskItem)
        case failed(String)
        case gone
        case signedOut
    }

    /// Runs a task request after the change is already on screen; on failure, puts it back and says why.
    private func taskRequest(undo: @escaping () -> Void, _ request: @escaping (Client, String) async throws -> TaskOutcome) {
        taskError = nil
        Task {
            let outcome: TaskOutcome
            do {
                outcome = try await request(client, id)
            } catch {
                outcome = .failed("Couldn’t save that. Check your connection.")
            }
            switch outcome {
            case .done:
                break
            case .replace(let id, let task):
                replace(id, with: task)
            case .failed(let message):
                undo()
                taskError = message
            case .gone:
                load = .gone
            case .signedOut:
                undo()
                await auth.sessionEnded()
            }
        }
    }

    private func replace(_ id: String, with task: TaskItem) {
        guard let index = detail?.tasks.firstIndex(where: { $0.id == id }) else { return }
        detail?.tasks[index] = task
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
            week: Week(start: body.week.start, objective: body.week.objective, lastWeek: body.week.lastWeek),
            tasks: body.tasks.map { TaskItem(api: $0) },
            suggestions: body.suggestions.map { TaskSuggestion(title: $0.title, why: $0.why, minutes: $0.minutes) },
            clock: body.clock.flatMap { Clock(rawValue: $0.rawValue) }
        )
    }
}

extension TaskItem {
    init(api task: Components.Schemas.Task) {
        self.init(
            id: task.id,
            title: task.title,
            description: task.description,
            minutes: task.minutes,
            done: task.doneAt != nil,
            plannedFor: task.plannedFor,
            dueOn: task.dueOn,
            scheduledAt: task.scheduledAt
        )
    }

    /// The saved task, keeping what the edit endpoint doesn't send back (when it's on the calendar).
    init(api task: Components.Schemas.Task, keeping local: TaskItem) {
        self.init(api: task)
        scheduledAt = local.scheduledAt
    }
}
