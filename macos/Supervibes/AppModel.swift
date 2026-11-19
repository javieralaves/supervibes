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

    @ObservationIgnored private let auth: AuthModel
    @ObservationIgnored private let client: Client
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var fetchedDay: DateComponents?
    @ObservationIgnored private var isFetching = false
    /// What the widget was last given, so it's only asked to reload when that changes.
    @ObservationIgnored private var shared: (signedIn: Bool, blocks: [Block])?

    /// How often today's blocks are fetched again while the app runs.
    private static let refreshInterval: TimeInterval = 5 * 60

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
        // Coming back from sleep, today may have moved on.
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
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

    /// Fetch on the next tick, for example right after signing in.
    func refreshSoon() {
        lastFetch = nil
        tick()
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
        guard signedIn else { return }

        let day = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let stale = lastFetch.map { now.timeIntervalSince($0) > Self.refreshInterval } ?? true
        if stale || day != fetchedDay {
            Task { await refresh() }
        }
    }

    private func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

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
    /// Hands today's blocks to the widget, and has it redraw when they've changed.
    private func share() {
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
            goal: block.title == nil ? "Protected time" : block.goal.title,
            start: block.startsAt,
            end: block.endsAt,
            tint: Tint(light: block.goal.color.light, dark: block.goal.color.dark)
        )
    }
}
