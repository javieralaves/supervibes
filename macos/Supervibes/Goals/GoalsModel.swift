import Foundation
import Observation

/// Loads Life's goals and areas, and adds new goals, through /api/v1.
@MainActor
@Observable
final class GoalsModel {
    enum Load: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .idle
    private(set) var goals: [Goal] = []
    /// The person's areas, in order. Empty until they make one, or if they couldn't be loaded.
    private(set) var areas: [Area] = []
    /// Each goal's week, by goal id.
    private(set) var weeks: [String: GoalWeek] = [:]
    private(set) var today = CalendarDay.today()
    private(set) var max = 12
    private(set) var error: String?
    /// Why the last change to an area didn't go through; shown above the areas.
    private(set) var areaError: String?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    private var areaAPI: AreaAPI { AreaAPI(client: client, auth: auth) }

    func refresh() async {
        if load != .loaded { load = .loading }
        // Areas load beside the goals; if they don't come, the goals still show.
        async let areasLoaded = loadAreas()
        do {
            switch try await client.listGoals(query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                let body = try ok.body.json
                goals = body.goals.map(Goal.init(api:))
                weeks = Dictionary(body.week.goals.map { ($0.goalId, GoalWeek(api: $0)) }, uniquingKeysWith: { first, _ in first })
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
        if let loaded = await areasLoaded { areas = loaded }
    }

    /// The person's areas, or nil if they couldn't be loaded (the goals show without them).
    private func loadAreas() async -> [Area]? {
        do {
            switch try await client.listAreas(query: .init(timeZone: TimeZone.current.identifier)) {
            case .ok(let ok):
                return try ok.body.json.areas.map(Area.init(api:))
            case .unauthorized:
                return nil
            case .badRequest, .undocumented:
                return nil
            }
        } catch {
            Log.app.error("Areas: \(error.localizedDescription, privacy: .public)")
            return nil
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
            areaId: input.areaId,
            isPending: true,
            kind: input.kind,
            autoRecaps: input.autoRecaps,
            practice: input.kind == .practice
                ? Practice(perWeek: input.perWeek, minMinutes: input.minMinutes, week: .init(start: CalendarDay.weekStart(today), done: 0, planned: 0))
                : nil
        ))

        Task {
            let body = Components.Schemas.NewGoal(new: input, areaId: input.areaId)
            do {
                switch try await client.createGoal(body: .json(body)) {
                case .created(let created):
                    let saved = Goal(api: try created.body.json)
                    goals = goals.map { $0.id == pendingID ? saved : $0 }
                    Log.app.info("Goal created")
                    if saved.areaId != nil { await refreshAreas() }
                case .badRequest(let bad):
                    fail(pendingID, (try? bad.body.json.error.message) ?? "Couldn’t add that \(input.kind.noun).")
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

    /// Saves a goal's edits from its card, showing them right away and going back if the server says no.
    func update(_ goal: Goal, _ input: GoalInput) {
        error = nil
        let before = goals
        goals = goals.map { current in
            guard current.id == goal.id else { return current }
            var edited = current
            edited.title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            edited.description = input.description.isEmpty ? nil : input.description
            edited.targetDate = input.targetDate
            edited.icon = input.icon
            edited.color = input.color
            edited.autoRecaps = input.autoRecaps
            if edited.isPractice {
                edited.targetDate = nil
                edited.practice?.perWeek = input.perWeek
                edited.practice?.minMinutes = input.minMinutes
            }
            return edited
        }
        Task {
            let body = Components.Schemas.GoalInput(edited: input, isPractice: goal.isPractice)
            do {
                switch try await client.updateGoal(path: .init(id: goal.id), body: .json(body)) {
                case .ok(let ok):
                    let saved = Goal(api: try ok.body.json)
                    goals = goals.map { $0.id == saved.id ? saved : $0 }
                    if input.areaId != goal.areaId { await setArea(of: saved, to: input.areaId) }
                case .badRequest(let bad):
                    goals = before
                    error = (try? bad.body.json.error.message) ?? "Couldn’t save that."
                case .notFound:
                    goals.removeAll { $0.id == goal.id }
                case .unauthorized:
                    goals = before
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    goals = before
                    error = "Couldn’t save (the server answered \(status))."
                }
            } catch {
                goals = before
                self.error = "Couldn’t save. Check your connection."
            }
        }
    }

    /// Deletes a goal from its card: it goes right away, and comes back if the server says no.
    func delete(_ goal: Goal) {
        error = nil
        let before = goals
        goals.removeAll { $0.id == goal.id }
        Task {
            do {
                switch try await client.deleteGoal(path: .init(id: goal.id)) {
                case .noContent, .notFound:
                    Log.app.info("Goal deleted")
                case .unauthorized:
                    goals = before
                    await auth.sessionEnded()
                case .undocumented(let status, _):
                    goals = before
                    error = "Couldn’t delete that goal (the server answered \(status))."
                }
            } catch {
                goals = before
                self.error = "Couldn’t delete that goal. Check your connection."
            }
        }
    }

    // MARK: Areas

    /// Reloads the areas, whose goals and statuses follow the goals moving between them.
    func refreshAreas() async {
        if let loaded = await loadAreas() { areas = loaded }
    }

    /// Adds an area; true once it's saved. Its card shows when the server has it.
    func createArea(_ input: AreaInput) async -> Bool {
        areaError = nil
        if let problem = input.problem {
            areaError = problem
            return false
        }
        do {
            areas.append(try await areaAPI.create(input))
            return true
        } catch let failure as AreaAPIError {
            areaError = failure.message
            return false
        } catch {
            return false
        }
    }

    /// Saves an area's edits, showing them right away and going back if the server says no.
    func updateArea(_ area: Area, _ input: AreaInput) {
        areaError = nil
        if let problem = input.problem {
            areaError = problem
            return
        }
        let before = areas
        areas = areas.map { $0.id == area.id ? input.applied(to: $0) : $0 }
        Task {
            do {
                let saved = try await areaAPI.update(area.id, input)
                areas = areas.map { $0.id == saved.id ? saved : $0 }
            } catch {
                areas = before
                areaError = (error as? AreaAPIError)?.message ?? "Couldn’t save that area."
            }
        }
    }

    /// Removes an area right away; its goals stay, with no area. Comes back if the server says no.
    func deleteArea(_ area: Area) {
        areaError = nil
        let (areasBefore, goalsBefore) = (areas, goals)
        areas.removeAll { $0.id == area.id }
        goals = goals.map { goal in
            var goal = goal
            if goal.areaId == area.id { goal.areaId = nil }
            return goal
        }
        Task {
            do {
                try await areaAPI.delete(area.id)
            } catch {
                areas = areasBefore
                goals = goalsBefore
                areaError = (error as? AreaAPIError)?.message ?? "Couldn’t remove that area."
            }
        }
    }

    /// Places a goal in an area, or takes it out with nil, then reloads the areas for their goals and statuses.
    func setArea(of goal: Goal, to areaId: String?) async {
        let before = goals
        goals = goals.map { current in
            var current = current
            if current.id == goal.id { current.areaId = areaId }
            return current
        }
        do {
            try await areaAPI.setGoalArea(goalId: goal.id, areaId: areaId)
            await refreshAreas()
        } catch {
            goals = before
            self.error = (error as? AreaAPIError)?.message ?? "Couldn’t move that goal."
        }
    }

    private func fail(_ pendingID: String, _ message: String) {
        goals.removeAll { $0.id == pendingID }
        error = message
    }
}

extension GoalWeek {
    init(api week: Components.Schemas.GoalWeek) {
        self.init(
            objective: week.objective,
            sessionMinutes: week.sessionMinutes,
            reservedMinutes: week.reservedMinutes,
            plannedMinutes: week.plannedMinutes
        )
    }
}

extension Components.Schemas.NewGoal {
    /// A new project or practice as the API takes it: a practice sends its rhythm and no target date.
    init(new input: GoalInput, areaId: String?) {
        let isPractice = input.kind == .practice
        self.init(
            title: input.title,
            description: input.description.isEmpty ? nil : input.description,
            targetDate: isPractice ? nil : input.targetDate,
            icon: .init(rawValue: input.icon) ?? .target02Icon,
            color: .init(rawValue: input.color) ?? .violet,
            areaId: areaId,
            kind: .init(rawValue: input.kind.rawValue),
            perWeek: isPractice ? input.perWeek : nil,
            minMinutes: isPractice ? input.minMinutes : nil,
            autoRecaps: input.autoRecaps
        )
    }
}

extension Components.Schemas.GoalInput {
    /// The edit as the API takes it: a practice sends its own fields (0 clears its minimum), a project its target date.
    init(edited input: GoalInput, isPractice: Bool) {
        self.init(
            title: input.title,
            description: input.description.isEmpty ? nil : input.description,
            targetDate: isPractice ? nil : input.targetDate,
            icon: .init(rawValue: input.icon) ?? .target02Icon,
            color: .init(rawValue: input.color) ?? .violet,
            perWeek: isPractice ? input.perWeek : nil,
            minMinutes: isPractice ? (input.minMinutes ?? 0) : nil,
            autoRecaps: input.autoRecaps
        )
    }
}

extension Practice {
    init(api practice: Components.Schemas.Practice) {
        let week = practice.week
        self.init(
            perWeek: practice.perWeek,
            minMinutes: practice.minMinutes,
            week: Week(start: week.start, done: week.done, planned: week.planned, paused: week.paused, beforeStart: week.beforeStart),
            status: practice.status.flatMap { status in
                GoalStatus(rawValue: status.status.rawValue).map {
                    Status(status: $0, done: status.done, expected: status.expected, weeks: status.weeks, reason: status.reason)
                }
            },
            paused: practice.paused.map { Pause(startsOn: $0.startsOn, resumesOn: $0.resumesOn) }
        )
    }
}

extension Practice.Week {
    init(api week: Components.Schemas.PracticeWeek) {
        self.init(start: week.start, done: week.done, planned: week.planned, paused: week.paused, beforeStart: week.beforeStart)
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
            },
            areaId: goal.areaId,
            updatedAt: goal.updatedAt,
            kind: GoalKind(rawValue: goal.kind.rawValue) ?? .project,
            autoRecaps: goal.autoRecaps,
            practice: goal.practice.map(Practice.init(api:))
        )
    }
}
