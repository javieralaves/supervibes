import Foundation

/// One goal's tasks, changed through /api/v1: add, check off or reopen, edit, delete, reorder and
/// place. Each change shows at once and saves in the background; if saving fails it's put back and
/// `onError` says why. The goal page and the planning board each hold one per goal, over their own
/// copy of its tasks, so the two work the same way.
@MainActor
final class TaskEditor {
    /// Where the goal's tasks live in the model that holds this editor.
    struct Lists {
        /// Its open tasks, in order; nil while there's nothing loaded.
        var tasks: () -> [TaskItem]?
        var setTasks: ([TaskItem]) -> Void
        /// What it finished this week, most recently first.
        var done: () -> [TaskItem]?
        var setDone: ([TaskItem]) -> Void
        /// Today, "YYYY-MM-DD", for keeping a planned day and week in step.
        var today: () -> String?
    }

    /// How a saved change came back.
    enum Outcome {
        case done
        /// Swap the task with this id for the saved one.
        case replace(String, TaskItem)
        case failed(String)
        /// The goal is gone.
        case gone
        case signedOut
    }

    let goalId: String
    private let lists: Lists
    private let client: Client
    private let auth: AuthModel
    private let onError: (String?) -> Void
    private let onGone: () -> Void

    init(goalId: String, lists: Lists, client: Client, auth: AuthModel, onError: @escaping (String?) -> Void, onGone: @escaping () -> Void = {}) {
        self.goalId = goalId
        self.lists = lists
        self.client = client
        self.auth = auth
        self.onError = onError
        self.onGone = onGone
    }

    private var tasks: [TaskItem]? { lists.tasks() }

    /// Adds a task at the end, planned for the placement's day or week, or unplanned.
    func add(_ title: String, placement: TaskPatch) {
        guard var current = tasks else { return }
        var pending = TaskItem(id: "pending-\(UUID().uuidString)", title: title, minutes: TaskItem.defaultMinutes, isPending: true)
        if let today = lists.today() {
            pending = pending.placed(plannedFor: placement.plannedFor, plannedWeek: placement.plannedWeek, today: today)
        }
        current.append(pending)
        lists.setTasks(current)
        request(undo: { [lists] in lists.setTasks((lists.tasks() ?? []).filter { $0.id != pending.id }) }) { client, goalId in
            switch try await client.addTask(path: .init(id: goalId), body: .json(.init(title: title, plannedFor: placement.plannedFor, plannedWeek: placement.plannedWeek))) {
            case .created(let created): .replace(pending.id, TaskItem(api: try created.body.json))
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t add that task.")
            case .notFound: .gone
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t add that task (the server answered \(status)).")
            }
        }
    }

    /// Checking a task off moves it to the goal's activity, so it leaves the list and joins this
    /// week's done ones. Reopening one brings it back to the end of the list.
    func toggle(_ task: TaskItem) {
        guard let open = tasks, let done = lists.done() else { return }
        if task.done {
            guard let index = done.firstIndex(where: { $0.id == task.id }) else { return }
            var reopened = task
            reopened.done = false
            var nextDone = done
            nextDone.remove(at: index)
            lists.setDone(nextDone)
            lists.setTasks(open + [reopened])
        } else {
            guard let index = open.firstIndex(where: { $0.id == task.id }) else { return }
            var finished = task
            finished.done = true
            var nextOpen = open
            nextOpen.remove(at: index)
            lists.setTasks(nextOpen)
            lists.setDone([finished] + done)
        }
        request(undo: { [lists] in
            lists.setTasks(open)
            lists.setDone(done)
        }) { client, _ in
            switch try await client.setTaskDone(path: .init(taskId: task.id), body: .json(.init(done: !task.done))) {
            case .ok: .done
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t check that off.")
            case .notFound: .failed("That task doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t check that off (the server answered \(status)).")
            }
        }
    }

    func edit(_ task: TaskItem, _ patch: TaskPatch) {
        guard var current = tasks, let index = current.firstIndex(where: { $0.id == task.id }) else { return }
        let before = current[index]
        var after = before
        if let title = patch.title { after.title = title }
        if let description = patch.description { after.description = description.isEmpty ? nil : description }
        if let minutes = patch.minutes { after.minutes = minutes }
        if patch.plannedFor != nil || patch.plannedWeek != nil, let today = lists.today() {
            after = after.placed(plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, today: today)
        }
        if let day = patch.dueOn { after.dueOn = day.isEmpty ? nil : day }
        current[index] = after
        lists.setTasks(current)
        request(undo: { [weak self] in self?.replace(task.id, with: before) }) { client, _ in
            let body = Components.Schemas.TaskPatch(
                title: patch.title, description: patch.description, minutes: patch.minutes,
                plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, dueOn: patch.dueOn
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

    func delete(_ task: TaskItem) {
        guard var current = tasks, let index = current.firstIndex(where: { $0.id == task.id }) else { return }
        current.remove(at: index)
        lists.setTasks(current)
        request(undo: { [lists] in
            var restored = lists.tasks() ?? []
            restored.insert(task, at: min(index, restored.count))
            lists.setTasks(restored)
        }) { client, _ in
            switch try await client.deleteTask(path: .init(taskId: task.id)) {
            case .noContent, .notFound: .done
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t delete that task (the server answered \(status)).")
            }
        }
    }

    /// Shows the new order at once and saves it in the background.
    func reorder(_ ids: [String]) {
        guard let current = tasks else { return }
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        lists.setTasks(ids.compactMap { byID[$0] })
        request(undo: { [lists] in lists.setTasks(current) }) { client, goalId in
            switch try await client.reorderTasks(path: .init(id: goalId), body: .json(.init(ids: ids))) {
            case .noContent: .done
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t reorder these tasks.")
            case .notFound: .gone
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t reorder (the server answered \(status)).")
            }
        }
    }

    /// Moves a task to a day, a week or Unplanned (the patch's planned day and week), just before
    /// the task `before`, or at the end. Shows it there at once and saves in the background.
    func place(_ task: TaskItem, _ patch: TaskPatch, before: String?) {
        guard let current = tasks, let index = current.firstIndex(where: { $0.id == task.id }), let today = lists.today() else { return }
        guard before != task.id else { return }
        let after = current[index].placed(plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, today: today)
        var next = current
        next.remove(at: index)
        next.insert(after, at: before.flatMap { id in next.firstIndex { $0.id == id } } ?? next.endIndex)
        lists.setTasks(next)
        request(undo: { [lists] in lists.setTasks(current) }) { client, _ in
            let body = Components.Schemas.TaskPlacement(plannedFor: patch.plannedFor, plannedWeek: patch.plannedWeek, before: before)
            return switch try await client.placeTask(path: .init(taskId: task.id), body: .json(body)) {
            case .ok(let ok): .replace(task.id, TaskItem(api: try ok.body.json, keeping: after))
            case .badRequest(let bad): .failed((try? bad.body.json.error.message) ?? "Couldn’t move that task.")
            case .notFound: .failed("That task doesn’t exist anymore.")
            case .unauthorized: .signedOut
            case .undocumented(let status, _): .failed("Couldn’t move that task (the server answered \(status)).")
            }
        }
    }

    /// Runs a request after its change is already on screen; on failure, puts it back and says why.
    /// The goal page's suggestions use it too.
    func request(undo: @escaping () -> Void, _ send: @escaping (Client, String) async throws -> Outcome) {
        onError(nil)
        Task {
            let outcome: Outcome
            do {
                outcome = try await send(client, goalId)
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
                onError(message)
            case .gone:
                onGone()
            case .signedOut:
                undo()
                await auth.sessionEnded()
            }
        }
    }

    /// Swaps the open task with this id for `task`.
    func replace(_ id: String, with task: TaskItem) {
        guard var current = tasks, let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index] = task
        lists.setTasks(current)
    }

    /// The actions a task list or the board calls, wired to this editor. `refresh` and the
    /// suggestions are left to whoever has them.
    var actions: TaskActions {
        TaskActions(
            add: { [weak self] in self?.add($0, placement: $1) },
            toggle: { [weak self] in self?.toggle($0) },
            edit: { [weak self] in self?.edit($0, $1) },
            delete: { [weak self] in self?.delete($0) },
            reorder: { [weak self] in self?.reorder($0) },
            place: { [weak self] in self?.place($0, $1, before: $2) }
        )
    }
}
