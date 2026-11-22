import AppKit
import Foundation
import Observation
import SwiftUI
import WidgetKit

/// App-wide state for the native surfaces: today's blocks from the API, and a clock.
@MainActor
@Observable
final class AppModel {
    private(set) var now = Date()
    private(set) var blocks: [Block] = []
    private(set) var isSignedIn = false
    /// Why checking off a task from the menu bar didn't save, until the next try.
    private(set) var taskError: String?
    /// The notices before sessions, scheduled from today's blocks.
    let notifier = SessionNotifier()
    /// What happens as sessions start and end: Do Not Disturb, quitting apps, Shortcuts.
    let routineRunner = SessionRoutineRunner()

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var fetchedDay: DateComponents?
    @ObservationIgnored private var isFetching = false
    /// What the widget was last given, so it's only asked to reload when that changes.
    @ObservationIgnored private var shared: (signedIn: Bool, blocks: [Block])?

    /// Asked for while a fetch was underway: that fetch may have missed it, so fetch once more.
    @ObservationIgnored private var fetchAgain = false

    /// How often today's blocks are fetched again while the app runs, for changes made elsewhere
    /// (recaps finishing on the server). Changes saved in the app are fetched straight away.
    private static let refreshInterval: TimeInterval = 2 * 60
    /// Opening the menu bar fetches again when what it has is older than this.
    private static let freshEnough: TimeInterval = 60

    init(auth: AuthModel) {
        self.auth = auth
        let store = auth.store
        self.client = APIClient.make(baseURL: auth.baseURL, token: { store.read() })

        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        // Coming back from sleep, today may have moved on. (Wake is posted on the workspace's own
        // notification center, not the default one.)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        // A block, task or goal was saved somewhere in the app.
        NotificationCenter.default.addObserver(forName: .supervibesDataChanged, object: nil, queue: .main) { [weak self] note in
            let operation = note.userInfo?["operation"] as? String ?? "?"
            MainActor.assumeIsolated {
                Log.app.info("Saved (\(operation, privacy: .public)): fetching today again")
                self?.refreshSoon()
            }
        }
    }

    var current: Block? {
        blocks.first { $0.isHappening(at: now) }
    }

    var upcoming: [Block] {
        Array(blocks.filter { $0.start > now }.prefix(3))
    }

    /// What the menu bar item reads: the time left in the current block, or the time of the next one.
    var menuBarTitle: Text {
        if let current {
            return Text("\(Image(systemName: "timer")) \(Block.remaining(minutes: current.minutesLeft(at: now)))")
        }
        if let next = upcoming.first {
            return Text("\(Image(systemName: "calendar")) \(next.start.formatted(date: .omitted, time: .shortened))")
        }
        return Text(Image(systemName: "calendar"))
    }

    /// Fetch now, for example right after signing in or saving a change. If a fetch is already
    /// underway, another follows it, since that one may have started before the change.
    func refreshSoon() {
        lastFetch = nil
        if isFetching {
            fetchAgain = true
        } else {
            tick()
        }
    }

    /// The menu bar opened: make sure what it shows is recent.
    func refreshIfStale() {
        guard let lastFetch, Date().timeIntervalSince(lastFetch) < Self.freshEnough else {
            return refreshSoon()
        }
    }

    private func tick() {
        now = Date()
        let signedIn = auth.isSignedIn
        if signedIn != isSignedIn {
            isSignedIn = signedIn
            lastFetch = nil
            if !signedIn {
                blocks = []
                share()
            }
        }
        notifier.tick(now: now)
        routineRunner.tick(now: now)
        guard signedIn else { return }

        let day = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let stale = lastFetch.map { now.timeIntervalSince($0) > Self.refreshInterval } ?? true
        if (stale || day != fetchedDay), !isFetching {
            Task { await refresh() }
        }
    }

    private func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        repeat {
            fetchAgain = false
            await fetchToday()
        } while fetchAgain && isSignedIn
        isFetching = false
    }

    private func fetchToday() async {
        do {
            let output = try await client.getToday(query: .init(timeZone: TimeZone.current.identifier))
            switch output {
            case .ok(let ok):
                let today = try ok.body.json
                blocks = today.blocks.map(Block.init(api:))
                share()
                lastFetch = Date()
                fetchedDay = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                Log.app.info("Fetched today: \(today.blocks.count) blocks")
            case .unauthorized:
                Log.app.notice("Today: session ended")
                await auth.sessionEnded()
            case .badRequest(let bad):
                let message = (try? bad.body.json.error.message) ?? "-"
                Log.app.error("Today: bad request: \(message, privacy: .public)")
                lastFetch = Date()
            case .undocumented(let status, _):
                Log.app.error("Today: server answered \(status)")
                lastFetch = Date()
            }
        } catch {
            // Offline or the server is down: keep what we have and try again next interval.
            Log.app.error("Today: \(error.localizedDescription, privacy: .public)")
            lastFetch = Date()
        }
    }
}

extension AppModel {
    /// Checks off or reopens one of an agenda's tasks from the menu bar. Shows the change straight
    /// away and puts it back if the server says no.
    func setTaskDone(_ taskId: String, _ done: Bool) {
        taskError = nil
        markTask(taskId, done: done)
        Task {
            do {
                switch try await client.setTaskDone(path: .init(taskId: taskId), body: .json(.init(done: done))) {
                case .ok:
                    Log.app.info("Task \(done ? "done" : "reopened", privacy: .public) from the menu bar")
                    return
                case .unauthorized:
                    await auth.sessionEnded()
                    return
                case .notFound:
                    taskError = "That task doesn’t exist anymore."
                case .badRequest(let bad):
                    taskError = (try? bad.body.json.error.message) ?? "Couldn’t save that."
                case .undocumented(let status, _):
                    taskError = "Couldn’t save that (the server answered \(status))."
                }
            } catch {
                taskError = "Couldn’t save that. Check your connection."
            }
            markTask(taskId, done: !done)
        }
    }

    private func markTask(_ taskId: String, done: Bool) {
        blocks = blocks.map { block in
            guard var agenda = block.agenda, agenda.tasks.contains(where: { $0.id == taskId }) else { return block }
            agenda.tasks = agenda.tasks.map { var task = $0; if task.id == taskId { task.done = done }; return task }
            var block = block
            block.agenda = agenda
            return block
        }
        share()
    }

    /// Saves what the person wants out of a session, from the menu bar; empty clears it. Shows the
    /// change straight away and puts it back if the server says no.
    func setAim(_ blockId: String, _ text: String) async -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let before = blocks.first(where: { $0.id == blockId }), value != (before.aim ?? "") else { return nil }
        updateBlock(blockId) { $0.aim = value.isEmpty ? nil : value }
        var message: String?
        do {
            switch try await client.setBlockDescription(path: .init(blockId: blockId), body: .json(.init(description: value))) {
            case .noContent: break
            case .badRequest(let bad): message = (try? bad.body.json.error.message) ?? "Couldn’t save that."
            case .notFound(let gone): message = (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .unauthorized: await auth.sessionEnded()
            case .undocumented(let status, _): message = "Couldn’t save that (the server answered \(status))."
            }
        } catch {
            message = "Couldn’t save that. Check your connection."
        }
        if message != nil { updateBlock(blockId) { $0.aim = before.aim } }
        return message
    }

    /// Prepares a session's agenda from the menu bar.
    func planSession(_ blockId: String) async -> String? {
        guard let block = blocks.first(where: { $0.id == blockId }) else { return "That block doesn’t exist anymore." }
        do {
            switch try await client.prepareAgenda(path: .init(blockId: blockId), body: .json(.init(when: Self.when(block)))) {
            case .ok(let ok):
                let agenda = try ok.body.json
                updateBlock(blockId) {
                    // The tasks it draws on are open ones; the next fetch says otherwise if that's changed.
                    $0.agenda = SessionAgenda(text: agenda.text, tasks: agenda.tasks.map { .init(id: $0.id, title: $0.title, minutes: $0.minutes, done: false) })
                }
                return nil
            case .badRequest(let bad): return (try? bad.body.json.error.message) ?? "Couldn’t prepare an agenda."
            case .notFound(let gone): return (try? gone.body.json.error.message) ?? "That block doesn’t exist anymore."
            case .badGateway(let failed): return (try? failed.body.json.error.message) ?? "Couldn’t prepare an agenda right now. Try again."
            case .unauthorized:
                await auth.sessionEnded()
                return nil
            case .undocumented(let status, _): return "Couldn’t prepare an agenda (the server answered \(status))."
            }
        } catch {
            return "Couldn’t reach Supervibes. Check your connection."
        }
    }

    /// Suggests an aim for a session that doesn't say what it's for yet. Nothing is saved.
    func suggestFocus(_ blockId: String, instead: [String]) async -> FocusOutcome {
        guard let block = blocks.first(where: { $0.id == blockId }) else { return .failed("That block doesn’t exist anymore.") }
        do {
            switch try await client.suggestFocus(
                path: .init(blockId: blockId),
                body: .json(.init(when: Self.when(block), instead: instead.isEmpty ? nil : instead))
            ) {
            case .ok(let ok):
                let body = try ok.body.json
                return .suggested(FocusSuggestion(aim: body.aim, why: body.why))
            case .badRequest(let bad): return .failed((try? bad.body.json.error.message) ?? "Couldn’t suggest a focus.")
            case .notFound(let gone): return .failed((try? gone.body.json.error.message) ?? "That block doesn’t exist anymore.")
            case .badGateway(let failed): return .failed((try? failed.body.json.error.message) ?? "Couldn’t suggest a focus right now. Try again.")
            case .unauthorized:
                await auth.sessionEnded()
                return .failed("You’ve been signed out.")
            case .undocumented(let status, _): return .failed("Couldn’t suggest a focus (the server answered \(status)).")
            }
        } catch {
            return .failed("Couldn’t reach Supervibes. Check your connection.")
        }
    }

    /// How a block reads for the agenda, as the calendar says it: "Wednesday, November 18 (today), 3:00 PM–4:30 PM".
    private static func when(_ block: Block) -> String {
        let en = Locale(identifier: "en_US")
        let date = block.start.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(en))
        let today = Calendar.current.isDateInToday(block.start) ? " (today)" : ""
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(en)
        return "\(date)\(today), \(block.start.formatted(time))–\(block.end.formatted(time))"
    }

    private func updateBlock(_ blockId: String, _ change: (inout Block) -> Void) {
        blocks = blocks.map { block in
            guard block.id == blockId else { return block }
            var block = block
            change(&block)
            return block
        }
        share()
    }

    /// Hands today's blocks to the widget, and has it redraw when they've changed.
    private func share() {
        notifier.blocksChanged(blocks)
        routineRunner.blocksChanged(blocks)
        if let shared, shared.signedIn == isSignedIn, shared.blocks == blocks { return }
        let today = SharedToday(signedIn: isSignedIn, fetchedAt: Date(), blocks: blocks)
        guard WidgetShare.write(today) else {
            Log.widgets.error("Couldn't write to the App Group \(WidgetShare.groupID ?? "(none)", privacy: .public)")
            return
        }
        shared = (isSignedIn, blocks)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.kind)
        Log.widgets.info("Shared \(self.blocks.count) blocks with the widget")
    }
}

extension Block {
    init(api block: Components.Schemas.TodayBlock) {
        self.init(
            id: block.id,
            title: block.title ?? block.goal.title,
            goal: block.title == nil ? (block.reserved ? "Reserved" : "Protected time") : block.goal.title,
            start: block.startsAt,
            end: block.endsAt,
            tint: Tint(light: block.goal.color.light, dark: block.goal.color.dark),
            // Reserved time has no aim or plan, even one kept from when it was a session.
            aim: block.reserved ? nil : block.description.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 },
            agenda: block.reserved ? nil : block.agenda.map { agenda in
                SessionAgenda(
                    text: agenda.text,
                    tasks: agenda.tasks.map { .init(id: $0.id, title: $0.title, minutes: $0.minutes, done: $0.done) }
                )
            },
            taskId: block.taskId,
            untitled: block.title == nil,
            reserved: block.reserved
        )
    }
}
