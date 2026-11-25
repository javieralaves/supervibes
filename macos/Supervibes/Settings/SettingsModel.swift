import Foundation
import Observation

/// Loads and saves what the Settings window shows, through /api/v1.
@MainActor
@Observable
final class SettingsModel {
    enum Load: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var load: Load = .idle
    private(set) var email: String?
    private(set) var usage: UsageSummary?
    /// The person's goals, for the goal Calendar import sends events to.
    private(set) var goals: [CalendarGoal] = []
    /// What's on screen. The page calls `changed(_:)` after editing it, which saves it.
    var settings = SleepSettings.defaults
    /// The card changed last and how its save went, as the web app shows it.
    private(set) var status: (section: SettingsPage.Section, state: SaveStatusView.State)?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
    }

    /// Fetches settings and usage. Called each time the window opens, so usage is current.
    func refresh() async {
        if load != .loaded { load = .loading }
        do {
            async let meOutput = client.getMe()
            async let usageOutput = client.getUsage()
            async let goalsOutput = client.listGoals(query: .init(timeZone: TimeZone.current.identifier))

            switch try await meOutput {
            case .ok(let ok):
                let me = try ok.body.json
                email = me.user.email
                let fetched = SleepSettings(
                    sleepStart: me.settings.sleepStart,
                    wakeTime: me.settings.wakeTime,
                    clock: me.settings.clock.flatMap { Clock(rawValue: $0.rawValue) }
                )
                if saveTask == nil { settings = fetched }
            case .unauthorized:
                return await auth.sessionEnded()
            case .undocumented(let status, _):
                throw AuthError.server(status)
            }

            switch try await usageOutput {
            case .ok(let ok):
                let body = try ok.body.json
                usage = UsageSummary(calls: body.calls.map(UsageCall.init(api:)), days: body.days)
            case .unauthorized:
                return await auth.sessionEnded()
            case .undocumented(let status, _):
                throw AuthError.server(status)
            }
            // Only Calendar import's goal menu needs these, so the page loads without them.
            if case .ok(let ok) = try? await goalsOutput, let body = try? ok.body.json {
                goals = body.goals.map { CalendarGoal(goal: Goal(api: $0)) }
            }
            load = .loaded
        } catch {
            Log.app.error("Settings: \(error.localizedDescription, privacy: .public)")
            if load != .loaded { load = .failed("Couldn't load your settings. Check your connection and try again.") }
        }
    }

    /// Saves what's on screen after a change on `section`'s card.
    func changed(_ section: SettingsPage.Section) {
        saveTask?.cancel()
        if let message = settings.problem {
            status = (section, .failed(message))
            saveTask = nil
            return
        }
        status = (section, .saving)
        let toSave = settings
        saveTask = Task {
            await save(toSave, section: section)
        }
    }

    private func save(_ value: SleepSettings, section: SettingsPage.Section) async {
        defer { if !Task.isCancelled { saveTask = nil } }
        do {
            let body = Components.Schemas.Settings(
                sleepStart: value.sleepStart,
                wakeTime: value.wakeTime,
                clock: value.clock.flatMap { .init(rawValue: $0.rawValue) }
            )
            let output = try await client.putSettings(body: .json(body))
            guard !Task.isCancelled else { return }
            switch output {
            case .ok:
                status = (section, .saved)
                Log.app.info("Settings saved")
            case .badRequest(let bad):
                status = (section, .failed((try? bad.body.json.error.message) ?? "Couldn't save that."))
            case .unauthorized:
                await auth.sessionEnded()
            case .undocumented(let code, _):
                status = (section, .failed("Couldn't save (the server answered \(code))."))
            }
        } catch {
            guard !Task.isCancelled else { return }
            status = (section, .failed("Couldn't save. Check your connection."))
        }
    }
}

extension UsageCall {
    init(api call: Components.Schemas.UsageCall) {
        self.init(
            id: call.id,
            feature: Feature(rawValue: call.feature.rawValue) ?? .progressRead,
            trigger: call.trigger.rawValue,
            goalTitle: call.goalTitle,
            model: call.model,
            inputTokens: call.inputTokens,
            outputTokens: call.outputTokens,
            toolCalls: call.toolCalls,
            durationMs: call.durationMs,
            outcome: call.outcome,
            cost: call.cost,
            createdAt: call.createdAt
        )
    }
}
