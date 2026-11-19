import Foundation

/*
 * What happens as a session starts, undone once it's over, as picked in Settings: turn on Do Not
 * Disturb, quit distracting apps (and reopen them after), and run the person's own Shortcuts for
 * anything else. Supervibes does the common cases itself; Shortcuts is for the rest.
 *
 * macOS has no public way for an app to switch Focus modes, but a Shortcut can, so the app ships
 * two ready-made, signed ones (Supervibes/Shortcuts, made by scripts/focus-shortcuts.sh) that the
 * person adds with one click.
 *
 * Sessions close together count as one stretch, so back-to-back blocks don't run the routine
 * between them. When to start and end is worked out here, without doing anything, so it can be
 * tested; the app's SessionRoutineRunner does the work. Like notices, the choice belongs to this
 * Mac and lives in UserDefaults.
 */

/// What to do as a session starts and once it's over.
struct SessionRoutine: Codable, Hashable, Sendable {
    /// An app to quit as a session starts.
    struct App: Codable, Hashable, Sendable, Identifiable {
        let bundleId: String
        let name: String
        var id: String { bundleId }
    }

    var doNotDisturb = false
    var quitApps: [App] = []
    /// Reopen the apps it quit once the session's over.
    var reopenApps = true
    /// The person's own Shortcut to run as a session starts, by name.
    var start: String?
    /// And once it's over.
    var end: String?

    static let defaults = SessionRoutine()

    /// The Shortcuts the app ships, by the names they're added under.
    static let focusOn = "Supervibes Do Not Disturb On"
    static let focusOff = "Supervibes Do Not Disturb Off"

    var isEmpty: Bool { !doNotDisturb && quitApps.isEmpty && start == nil && end == nil }

    init(doNotDisturb: Bool = false, quitApps: [App] = [], reopenApps: Bool = true, start: String? = nil, end: String? = nil) {
        self.doNotDisturb = doNotDisturb
        self.quitApps = quitApps
        self.reopenApps = reopenApps
        self.start = start
        self.end = end
    }

    /// Missing fields take their defaults, so a choice saved by an older build still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        doNotDisturb = try c.decodeIfPresent(Bool.self, forKey: .doNotDisturb) ?? false
        quitApps = try c.decodeIfPresent([App].self, forKey: .quitApps) ?? []
        reopenApps = try c.decodeIfPresent(Bool.self, forKey: .reopenApps) ?? true
        start = try c.decodeIfPresent(String.self, forKey: .start)
        end = try c.decodeIfPresent(String.self, forKey: .end)
    }

    // MARK: Stored on this Mac

    static let storageKey = "sv-session-routine"

    static func load(from defaults: UserDefaults = .standard) -> SessionRoutine {
        guard let data = defaults.data(forKey: storageKey),
              let routine = try? JSONDecoder().decode(SessionRoutine.self, from: data) else { return .defaults }
        return routine
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Sessions with no more than a short gap between them: one start, one end.
struct SessionStretch: Hashable, Sendable {
    let start: Date
    let end: Date
    let blockIds: Set<String>

    func contains(_ date: Date) -> Bool { start <= date && date < end }
}

enum SessionStretches {
    /// A gap this short or shorter between sessions doesn't end the stretch.
    static let joiningGap: TimeInterval = 5 * 60

    /// Today's blocks as stretches, earliest first.
    static func all(_ blocks: [Block]) -> [SessionStretch] {
        var result: [SessionStretch] = []
        for block in blocks.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, block.start.timeIntervalSince(last.end) <= joiningGap {
                result[result.count - 1] = SessionStretch(
                    start: last.start,
                    end: max(last.end, block.end),
                    blockIds: last.blockIds.union([block.id])
                )
            } else {
                result.append(SessionStretch(start: block.start, end: block.end, blockIds: [block.id]))
            }
        }
        return result
    }

    enum Action: Hashable, Sendable {
        case start
        case end
    }

    /// What to do now, given the stretch that was last started (its blocks, or empty if none is
    /// on), and which blocks count as started afterwards.
    ///
    /// A stretch is the one that was started if it shares a block with it, so one that grows (a
    /// block added right after, or the session extended) doesn't start again. Waking up inside a
    /// session starts it; waking up after one that was started ends it.
    static func step(blocks: [Block], now: Date, started: Set<String>) -> (action: Action?, started: Set<String>) {
        let current = all(blocks).first { $0.contains(now) }
        switch (current, started.isEmpty) {
        case (let stretch?, true):
            return (.start, stretch.blockIds)
        case (let stretch?, false):
            if stretch.blockIds.isDisjoint(with: started) {
                // One stretch ended and the next began between two looks (the Mac slept through
                // the gap). Starting is what matters now; ending would only undo it.
                return (.start, stretch.blockIds)
            }
            return (nil, stretch.blockIds)
        case (nil, false):
            return (.end, [])
        case (nil, true):
            return (nil, [])
        }
    }
}
