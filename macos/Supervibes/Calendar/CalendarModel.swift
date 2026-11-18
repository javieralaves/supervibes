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
}

extension CalendarData {
    init(api body: Components.Schemas.Calendar) {
        self.init(
            blocks: body.blocks.map { block in
                CalendarBlock(
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
            },
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
