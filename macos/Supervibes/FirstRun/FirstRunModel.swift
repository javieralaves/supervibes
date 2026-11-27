import Foundation
import Observation

/// First run, against /api/v1 (server side in src/lib/first-run.ts): who sees it, and each step.
///
/// Someone sees it when they have no projects, practices or areas, unless they've been through it on this Mac. How
/// far they got is kept on this Mac, keyed by their email: once the plate is made, the sorted plate is kept too, so
/// coming back picks up at What matters; Route 2's board is kept while it's being chosen, and its quests and what
/// waits once the season starts; once the week is started, it's done. (A server-side marker can replace this once
/// first run is settled.)
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
    /// The week, once it's opened.
    private(set) var week: FirstRunWeekModel?
    /// Route 3's season being set up, as Start a season does it.
    private(set) var setup: SeasonSetupModel?
    /// Route 3's quests renamed on the season's cards, saved on Start your season.
    private(set) var questNames: [String: String] = [:]

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
        case "whatMatters", "focus", "week", "stepBack":
            if let plate = keptPlate {
                state.sorted = plate
                saved = true
                state.route = keptRoute
                switch progress {
                case "focus":
                    if let board = keptBoard {
                        state.board = board
                        state.step = .focus
                    } else {
                        state.step = .whatMatters
                    }
                case "week":
                    state.step = .weekIntro
                    if state.route != .week { state.seasonStarted = true }
                    if state.route == .season { state.board = keptBoard }
                case "stepBack":
                    state.step = .stepBack
                default:
                    state.step = .whatMatters
                }
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
            // Route 3 picks up its draft where it was.
            if phase == .active, state.step == .stepBack, setup == nil {
                if await !loadSetup() { state.step = .whatMatters }
            }
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
        setup = nil
        questNames = [:]
    }

    // MARK: Steps

    var actions: FirstRunActions {
        FirstRunActions(
            start: { [weak self] in self?.go(.plate) },
            back: { [weak self] in self?.back() },
            sort: { [weak self] in Task { await self?.sort() } },
            setPerWeek: { [weak self] id, perWeek in self?.state.sorted?.setPerWeek(perWeek, for: id) },
            save: { [weak self] in Task { await self?.save() } },
            choose: { [weak self] choice in self?.choose(choice) },
            focus: FocusActions(
                choose: { [weak self] id in self?.changeBoard { $0.choose(id) } },
                place: { [weak self] id, slot in self?.changeBoard { $0.place(id, at: slot) } },
                remove: { [weak self] id in self?.changeBoard { $0.remove(id) } },
                wait: { [weak self] id in self?.changeBoard { $0.wait(id) } },
                keep: { [weak self] id in self?.changeBoard { $0.keep(id) } }
            ),
            toSeason: { [weak self] in
                guard self?.state.board?.focus.isEmpty == false else { return }
                self?.go(.season)
            },
            rename: { [weak self] id, name in self?.changeBoard { $0.names[id] = name } },
            startSeason: { [weak self] in Task { await self?.startSeason() } }
        )
    }

    /// A change on the Focus board, kept on this Mac until the season starts.
    private func changeBoard(_ change: (inout FocusBoard) -> Void) {
        guard var board = state.board, !state.seasonStarted else { return }
        change(&board)
        state.board = board
        keptBoard = board
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
        case .focus:
            progress = "whatMatters"
            go(.whatMatters)
        case .season: if !state.seasonStarted { go(.focus) }
        case .weekIntro:
            if state.route == .season {
                go(.season)
            } else {
                progress = "whatMatters"
                go(.whatMatters)
            }
        case .week: go(.weekIntro)
        case .stepBack: stepBackBack()
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

    /// A way ahead from What matters. Just this week goes on to the week; the next few months to the Focus board, once
    /// it's loaded; Step back first isn't built yet, so it finishes first run and opens the nearest screen the app has.
    private func choose(_ choice: FirstRunChoice) {
        switch choice {
        case .week:
            state.route = .week
            keptRoute = .week
            progress = "week"
            go(.weekIntro)
        case .season:
            Task { await openBoard() }
        case .stepBack:
            Task { await openStepBack() }
        }
    }

    // MARK: Route 3, step back first

    /// Opens the season's draft (made if there's none) and Start a season's steps, in first run's frame.
    private func openStepBack() async {
        guard !state.isBusy else { return }
        state.isBusy = true
        state.error = nil
        defer { state.isBusy = false }
        guard await loadSetup() else { return }
        state.route = .stepBack
        keptRoute = .stepBack
        progress = "stepBack"
        go(.stepBack)
    }

    /// The draft and what's needed to set it up; false, with why, when it can't be.
    private func loadSetup() async -> Bool {
        let model = setup ?? SeasonSetupModel(auth: auth)
        await model.start()
        if case .failed(let message) = model.load {
            state.error = message
            return false
        }
        setup = model
        return true
    }

    var stepBackActions: StepBackActions {
        StepBackActions(
            back: { [weak self] in self?.stepBackBack() },
            toggleArea: { [weak self] in self?.setup?.togglePick($0) },
            continueAreas: { [weak self] in Task { await self?.setup?.continueAreas() } },
            read: { [weak self] id, now, want in Task { await self?.setup?.read(areaId: id, now: now, want: want) } },
            next: { [weak self] in Task { await self?.stepBackNext() } },
            choose: { [weak self] id, chosen in Task { await self?.setup?.choose(id, chosen) } },
            toggleLink: { [weak self] quest, goal in self?.setup?.toggleLink(quest: quest, goal: goal) },
            addNew: { [weak self] quest, suggestion in self?.setup?.addSuggestion(quest: quest, suggestion) },
            removeNew: { [weak self] quest, suggestion in self?.setup?.removeSuggestion(quest: quest, suggestion) },
            continueMoves: { [weak self] in Task { _ = await self?.setup?.saveAllMoves() } },
            rename: { [weak self] id, name in
                guard self?.state.seasonStarted == false else { return }
                self?.questNames[id] = name
            },
            start: { [weak self] in Task { await self?.startStepBack() } }
        )
    }

    /// On from an area that's read, or from the quests chosen to what moves each, linking what's on the plate first.
    private func stepBackNext() async {
        guard let setup, let current = setup.state else { return }
        if current.step == .focus {
            // All the quests on one screen; suggestions are only asked for where the plate has nothing to link.
            guard !current.chosen.isEmpty else { return }
            setup.showMoves()
            setup.prefillMoves()
        } else {
            await setup.next()
        }
    }

    private func stepBackBack() {
        guard let setup, let step = setup.state?.step else { return go(.whatMatters) }
        switch step {
        case .areas:
            progress = "whatMatters"
            go(.whatMatters)
        case .review:
            if !state.seasonStarted { setup.showMoves() }
        default:
            setup.back()
        }
    }

    /// Saves any quests renamed on their cards, starts the season, and on to the week; once.
    private func startStepBack() async {
        if state.seasonStarted { return go(.weekIntro) }
        guard let setup, let current = setup.state, !current.isBusy else { return }
        for quest in current.chosen {
            guard let name = questNames[quest.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != quest.title else { continue }
            guard await setup.editQuest(quest.id, title: name, fromText: quest.fromText) else { return }
        }
        guard await setup.startSeason(), let season = setup.started else { return }
        keptQuests = season.chosen.map { WeekQuest(number: $0.position, title: $0.title, goalIds: $0.goalIds) }
        state.seasonStarted = true
        progress = "week"
        Log.app.info("First run: season started from stepping back, with \(season.chosen.count) quests")
        go(.weekIntro)
    }

    // MARK: Route 2, the next few months

    /// The Focus board, from what the plate made: each project and practice with its area, in the plate's order, with
    /// what sorting heard about it. A board already being chosen is picked up as it was.
    private func openBoard() async {
        guard !state.isBusy else { return }
        if state.board == nil {
            state.isBusy = true
            defer { state.isBusy = false }
            guard let board = await loadBoard() else {
                state.error = "Couldn’t open your plate. Try again."
                return
            }
            state.board = board
        }
        state.route = .season
        keptRoute = .season
        keptBoard = state.board
        progress = "focus"
        go(.focus)
    }

    private func loadBoard() async -> FocusBoard? {
        do {
            let zone = TimeZone.current.identifier
            async let goals = client.listGoals(query: .init(timeZone: zone))
            async let areas = client.listAreas(query: .init(timeZone: zone))
            guard case .ok(let goalsOK) = try await goals, case .ok(let areasOK) = try await areas else { return nil }
            let areaList = try areasOK.body.json.areas
            let plate = state.sorted?.items ?? []
            let items: [FocusItem] = try goalsOK.body.json.goals.compactMap { goal in
                guard let areaId = goal.areaId, let area = areaList.first(where: { $0.id == areaId }) else { return nil }
                let isPractice = goal.kind == .practice
                let sorted = plate.first { $0.title == goal.title && $0.isPractice == isPractice }
                return FocusItem(
                    id: goal.id, title: goal.title, icon: goal.icon, color: goal.color, isPractice: isPractice,
                    perWeek: goal.practice?.perWeek, areaId: areaId, areaName: area.name, areaIcon: area.icon,
                    detail: sorted?.detail
                )
            }
            // In the plate's order, as it was sorted.
            let order = plate.map(\.title)
            let sorted = items.enumerated().sorted { a, b in
                (order.firstIndex(of: a.element.title) ?? order.count + a.offset) < (order.firstIndex(of: b.element.title) ?? order.count + b.offset)
            }.map(\.element)
            return FocusBoard(items: sorted)
        } catch {
            Log.app.error("Opening the Focus board: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Makes the season from the board and starts it, once; on to the week.
    private func startSeason() async {
        guard let board = state.board, !board.focus.isEmpty, !state.isBusy else { return }
        if state.seasonStarted { return go(.weekIntro) }
        state.isBusy = true
        state.error = nil
        defer { state.isBusy = false }
        do {
            let body = Components.Schemas.FirstSeasonInput(
                focus: board.focus.map { .init(goalId: $0, title: board.name($0)) },
                waiting: Array(board.waiting).sorted()
            )
            switch try await client.startFirstSeason(body: .json(body)) {
            case .created(let created):
                let season = try created.body.json
                keptQuests = season.quests.map { WeekQuest(number: $0.position, title: $0.title, goalIds: [$0.goalId]) }
                state.seasonStarted = true
                progress = "week"
                Log.app.info("First run: season started with \(season.quests.count) quests")
                go(.weekIntro)
            case .unauthorized: await auth.sessionEnded()
            case .badRequest(let bad): state.error = (try? bad.body.json.error.message) ?? "Couldn’t start your season. Try again."
            case .undocumented(let status, _): state.error = "Couldn’t start your season (the server answered \(status))."
            }
        } catch {
            Log.app.error("Starting the first season: \(error.localizedDescription, privacy: .public)")
            state.error = "Couldn’t reach Supervibes. Check your connection."
        }
    }

    /// From the way in to the week itself.
    func openWeek() {
        guard let eventFeed else { return }
        if week == nil {
            let season = state.route == .season
            let model = FirstRunWeekModel(
                auth: auth, feed: eventFeed,
                quests: state.route == .week ? [] : keptQuests,
                waiting: season ? state.board?.waiting ?? [] : [],
                steps: state.route.steps
            )
            week = model
            Task { await model.start() }
        }
        go(.week)
    }

    var weekActions: WeekActions {
        var actions = week?.actions ?? WeekActions()
        actions.back = { [weak self] in self?.back() }
        actions.start = { [weak self] in self?.finish(self?.state.route ?? .week) }
        return actions
    }

    private func finish(_ choice: FirstRunChoice) {
        progress = "done"
        keptPlate = nil
        keptBoard = nil
        keptQuests = []
        setup = nil
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

    private var keptRoute: FirstRunChoice {
        get { email.flatMap { UserDefaults.standard.string(forKey: "firstRun.route.\($0)") }.flatMap(FirstRunChoice.init) ?? .week }
        set { if let email { UserDefaults.standard.set(newValue.rawValue, forKey: "firstRun.route.\(email)") } }
    }

    /// Route 2's board: while it's chosen, and after, for what waits for next season (its projects are only kept here).
    private var keptBoard: FocusBoard? {
        get {
            email.flatMap { UserDefaults.standard.data(forKey: "firstRun.board.\($0)") }
                .flatMap { try? JSONDecoder().decode(FocusBoard.self, from: $0) }
        }
        set {
            guard let email else { return }
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "firstRun.board.\(email)")
        }
    }

    /// Route 2's quests, as the season started them, for the week.
    private var keptQuests: [WeekQuest] {
        get {
            email.flatMap { UserDefaults.standard.data(forKey: "firstRun.quests.\($0)") }
                .flatMap { try? JSONDecoder().decode([WeekQuest].self, from: $0) } ?? []
        }
        set {
            guard let email else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "firstRun.quests.\(email)")
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
