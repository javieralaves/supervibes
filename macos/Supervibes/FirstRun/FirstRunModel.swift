import Foundation
import Observation

/// First run's shared start, against /api/v1 (server side in src/lib/first-run.ts): who sees it, and each step.
///
/// Someone sees it when they have no projects, practices or areas, unless they've been through it on this Mac. How
/// far they got is kept on this Mac, keyed by their email: once the plate is made, the sorted plate is kept too, so
/// coming back picks up at What matters; once they choose a way ahead, it's done. (A server-side marker can replace
/// this once first run is settled.)
@MainActor
@Observable
final class FirstRunModel {
    enum Phase: Equatable { case unknown, active, inactive }

    private(set) var phase: Phase = .unknown
    private(set) var state: FirstRunState
    /// What's typed on the plate, bound to the editor.
    var plateText = ""
    /// Called with the way ahead once first run is done, to open the nearest screen the app has.
    @ObservationIgnored var onFinish: (FirstRunChoice) -> Void = { _ in }
    /// The person's Google calendars, for Route 1's week. Set by the app.
    @ObservationIgnored var eventFeed: EventFeed?
    /// Route 1's week, once it's opened.
    private(set) var week: FirstRunWeekModel?

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    /// Whether the sorted plate has been made, so going back to it and on again doesn't make it twice.
    @ObservationIgnored private var saved = false
    @ObservationIgnored private var email: String?

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })
        state = FirstRunState(firstName: "", seasonEnd: Self.seasonEnd(from: .now))
    }

    // MARK: Who sees it

    /// Decides whether first run shows, after signing in.
    func check() async {
        guard case .signedIn(let email) = auth.state else {
            phase = .unknown
            return
        }
        self.email = email
        reset()
        switch progress {
        case "done":
            phase = .inactive
            return
        case "whatMatters", "week":
            if let plate = keptPlate {
                state.sorted = plate
                state.step = progress == "week" ? .weekIntro : .whatMatters
                saved = true
            }
        default: break
        }
        do {
            async let me = client.getMe()
            async let goals = client.listGoals(query: .init(timeZone: TimeZone.current.identifier))
            async let areas = client.listAreas(query: .init(timeZone: TimeZone.current.identifier))
            if case .ok(let ok) = try await me {
                let name = try ok.body.json.user.name
                state.firstName = name.split(separator: " ").first.map(String.init) ?? name
            }
            let goalCount = if case .ok(let ok) = try await goals { try ok.body.json.goals.count } else { 1 }
            let areaCount = if case .ok(let ok) = try await areas { try ok.body.json.areas.count } else { 1 }
            // Someone who already has things, and isn't partway through first run here, goes straight to the app.
            phase = (goalCount == 0 && areaCount == 0) || state.step.rawValue >= FirstRunStep.whatMatters.rawValue ? .active : .inactive
        } catch {
            Log.app.error("First run check: \(error.localizedDescription, privacy: .public)")
            phase = .inactive
        }
    }

    /// Debug builds' Develop menu: go through first run again from the start, whatever's on the account.
    func replay() {
        progress = nil
        reset()
        phase = .active
    }

    private func reset() {
        state = FirstRunState(firstName: state.firstName, seasonEnd: Self.seasonEnd(from: .now))
        plateText = ""
        saved = false
        week = nil
    }

    // MARK: Steps

    var actions: FirstRunActions {
        FirstRunActions(
            start: { [weak self] in self?.go(.plate) },
            back: { [weak self] in self?.back() },
            sort: { [weak self] in Task { await self?.sort() } },
            setPerWeek: { [weak self] id, perWeek in self?.state.sorted?.setPerWeek(perWeek, for: id) },
            save: { [weak self] in Task { await self?.save() } },
            choose: { [weak self] choice in self?.choose(choice) }
        )
    }

    private func go(_ step: FirstRunStep) {
        state.error = nil
        state.step = step
    }

    private func back() {
        switch state.step {
        case .welcome: break
        case .plate: go(.welcome)
        case .sorted: go(.plate)
        case .whatMatters: go(.sorted)
        case .weekIntro: go(.whatMatters)
        case .week: go(.weekIntro)
        }
    }

    /// Sends the plate to be sorted; on to Sorted with what came back.
    private func sort() async {
        let text = plateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isBusy else { return }
        state.isBusy = true
        state.error = nil
        defer { state.isBusy = false }
        do {
            let body = Components.Schemas.PlateText(text: text, timeZone: TimeZone.current.identifier)
            switch try await client.sortPlate(body: .json(body)) {
            case .ok(let ok):
                state.sorted = SortedPlate(api: try ok.body.json)
                saved = false
                go(.sorted)
            case .unauthorized: await auth.sessionEnded()
            case .badRequest(let bad): state.error = (try? bad.body.json.error.message) ?? "Couldn’t sort that. Try again."
            case .undocumented(let status, _): state.error = "Couldn’t sort that (the server answered \(status))."
            }
        } catch {
            Log.app.error("Sorting the plate: \(error.localizedDescription, privacy: .public)")
            state.error = "Couldn’t reach Supervibes. Check your connection."
        }
    }

    /// Makes the sorted plate (once), then on to What matters.
    private func save() async {
        guard let plate = state.sorted, plate.needsRhythm.isEmpty, !state.isBusy else { return }
        if saved {
            go(.whatMatters)
            return
        }
        state.isBusy = true
        state.error = nil
        defer { state.isBusy = false }
        do {
            switch try await client.savePlate(body: .json(plate.api)) {
            case .created:
                saved = true
                keptPlate = plate
                progress = "whatMatters"
                go(.whatMatters)
            case .unauthorized: await auth.sessionEnded()
            case .badRequest(let bad): state.error = (try? bad.body.json.error.message) ?? "Couldn’t save that. Try again."
            case .undocumented(let status, _): state.error = "Couldn’t save that (the server answered \(status))."
            }
        } catch {
            Log.app.error("Saving the plate: \(error.localizedDescription, privacy: .public)")
            state.error = "Couldn’t reach Supervibes. Check your connection."
        }
    }

    /// A way ahead from What matters. Just this week goes on to the week; the other two routes aren't built yet, so
    /// they finish first run and open the nearest screen the app has.
    private func choose(_ choice: FirstRunChoice) {
        guard choice == .week else { return finish(choice) }
        progress = "week"
        go(.weekIntro)
    }

    /// From the way in to the week itself.
    func openWeek() {
        guard let eventFeed else { return }
        if week == nil {
            let model = FirstRunWeekModel(auth: auth, feed: eventFeed)
            week = model
            Task { await model.start() }
        }
        go(.week)
    }

    var weekActions: WeekActions {
        var actions = week?.actions ?? WeekActions()
        actions.back = { [weak self] in self?.back() }
        actions.start = { [weak self] in self?.finish(.week) }
        return actions
    }

    private func finish(_ choice: FirstRunChoice) {
        progress = "done"
        keptPlate = nil
        week = nil
        phase = .inactive
        Log.app.info("First run done: \(choice.rawValue, privacy: .public)")
        onFinish(choice)
    }

    // MARK: Kept on this Mac

    private var progress: String? {
        get { email.flatMap { UserDefaults.standard.string(forKey: "firstRun.progress.\($0)") } }
        set { if let email { UserDefaults.standard.set(newValue, forKey: "firstRun.progress.\(email)") } }
    }

    private var keptPlate: SortedPlate? {
        get {
            email.flatMap { UserDefaults.standard.data(forKey: "firstRun.plate.\($0)") }
                .flatMap { try? JSONDecoder().decode(SortedPlate.self, from: $0) }
        }
        set {
            guard let email else { return }
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "firstRun.plate.\(email)")
        }
    }

    /// The last day of a 13-week season starting next Monday, as Start a season makes by default.
    static func seasonEnd(from now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let toMonday = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
        let monday = calendar.date(byAdding: .day, value: toMonday, to: today) ?? today
        return calendar.date(byAdding: .day, value: 13 * 7 - 1, to: monday) ?? monday
    }
}

// MARK: - To and from the API

extension SortedPlate {
    init(api: Components.Schemas.SortedPlate) {
        self.init(areas: api.areas.enumerated().map { a, area in
            PlateArea(id: "area-\(a)", name: area.name, icon: area.icon.rawValue, items: area.items.enumerated().map { i, item in
                PlateItem(
                    id: "item-\(a)-\(i)", title: item.title, kind: item.kind == .practice ? .practice : .project,
                    detail: item.detail, perWeek: item.perWeek, targetDate: item.targetDate,
                    icon: item.icon.rawValue, color: item.color.rawValue, tasks: item.tasks
                )
            })
        })
    }

    var api: Components.Schemas.SortedPlate {
        Components.Schemas.SortedPlate(areas: areas.map { area in
            Components.Schemas.SortedArea(
                name: area.name,
                icon: .init(rawValue: area.icon) ?? .target02Icon,
                items: area.items.map { item in
                    Components.Schemas.SortedItem(
                        title: item.title, kind: item.isPractice ? .practice : .project, detail: item.detail,
                        perWeek: item.perWeek, targetDate: item.targetDate,
                        icon: .init(rawValue: item.icon) ?? .target02Icon, color: .init(rawValue: item.color) ?? .violet,
                        tasks: item.tasks
                    )
                }
            )
        })
    }
}
