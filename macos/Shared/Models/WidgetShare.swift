import Foundation

/*
 * How the widget gets real data. The app already fetches today's blocks for the menu bar; it writes
 * them to its App Group's container and asks WidgetKit to reload. The widget reads them back and
 * lays its timeline out around each block's start and end, so it stays right between fetches
 * without ever holding the sign-in token.
 */

/// Today's blocks as the app last fetched them.
struct SharedToday: Codable, Hashable, Sendable {
    var signedIn: Bool
    var fetchedAt: Date
    var blocks: [Block]
}

enum WidgetShare {
    /// The widget's kind, for reloading its timelines.
    static let kind = "CurrentBlock"

    /// The App Group both the app and the widget belong to: the team ID, then the app's bundle ID
    /// (set from the build settings in each target's Info.plist).
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SupervibesAppGroup") as? String
    }

    private static var fileURL: URL? {
        guard let groupID, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return nil
        }
        return container.appending(path: "today.json")
    }

    static func read() -> SharedToday? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SharedToday.self, from: data)
    }

    /// Writes what the widget should show. Returns false when there's no App Group to write to.
    @discardableResult
    static func write(_ today: SharedToday) -> Bool {
        guard let fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(today).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// The widget's timeline: what's on at each moment it should redraw.
enum WidgetTimeline {
    struct Moment: Hashable, Sendable {
        let date: Date
        let current: Block?
        let next: Block?
    }

    /// Every minute for the next hour (for the time left), plus each block's start and end over
    /// the next day, so a block shows up the moment it starts even if the app isn't running.
    static func moments(blocks: [Block], from now: Date) -> [Moment] {
        let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        var dates: Set<Date> = [now]
        for step in 1...60 { dates.insert(minute.addingTimeInterval(Double(step) * 60)) }
        let horizon = now.addingTimeInterval(24 * 3600)
        for block in blocks {
            for date in [block.start, block.end] where date > now && date < horizon {
                dates.insert(date)
            }
        }
        return dates.sorted().map { date in
            Moment(
                date: date,
                current: blocks.first { $0.isHappening(at: date) },
                next: blocks.filter { $0.start > date }.min { $0.start < $1.start }
            )
        }
    }
}
