import Foundation

/*
 * Notices before a session: a heads-up 15 minutes before, 5 minutes before and/or as it starts,
 * as the person picks in Settings. The choice belongs to this Mac (notifications are a device's
 * business), so it lives in UserDefaults rather than on the server. Which notices to send for
 * today's blocks is worked out here, without any notification APIs, so it can be tested; the app's
 * SessionNotifier hands the result to the system.
 */

/// How long before a session starts a notice goes out.
/// Cases are in the order Settings lists them.
enum NoticeLead: Int, CaseIterable, Codable, Hashable, Sendable, Comparable {
    case atStart = 0
    case five = 5
    case fifteen = 15

    var minutes: Int { rawValue }

    /// In Settings: "At start", "15 minutes before".
    var label: String {
        self == .atStart ? "At start" : "\(minutes) minutes before"
    }

    /// Leading the notification's title: "In 15 min", "Starting now".
    var heading: String {
        self == .atStart ? "Starting now" : "In \(minutes) min"
    }

    /// Earliest first: 15 min, 5 min, at start.
    static func < (a: NoticeLead, b: NoticeLead) -> Bool { a.minutes > b.minutes }
}

/// Whether notices are on, and when they go out.
struct NoticeSettings: Codable, Hashable, Sendable {
    var isOn: Bool
    /// Kept while notices are off, so turning them back on restores the choice.
    var leads: Set<NoticeLead>

    /// Off until the person turns it on; then 5 minutes before.
    static let defaults = NoticeSettings(isOn: false, leads: [.five])

    /// The leads that actually send something.
    var active: [NoticeLead] { isOn ? leads.sorted() : [] }

    /// Turns a lead on or off. Unticking the last one turns notices off, keeping that lead ticked
    /// for next time, so the card never says "on" while nothing would go out.
    mutating func toggle(_ lead: NoticeLead) {
        if leads.contains(lead) {
            if leads.count == 1 {
                isOn = false
            } else {
                leads.remove(lead)
            }
        } else {
            leads.insert(lead)
        }
    }

    /// Turning on with nothing ticked starts from the default.
    mutating func setOn(_ on: Bool) {
        isOn = on
        if on, leads.isEmpty { leads = Self.defaults.leads }
    }

    // MARK: Stored on this Mac

    static let storageKey = "sv-session-notices"

    static func load(from defaults: UserDefaults = .standard) -> NoticeSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(NoticeSettings.self, from: data) else { return .defaults }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Whether macOS lets Supervibes show notifications.
enum NoticePermission: Hashable, Sendable {
    /// Not asked yet; turning notices on asks.
    case notAsked
    case allowed
    /// Turned off for Supervibes in System Settings.
    case denied
}

/// One notice for one session.
struct SessionNotice: Hashable, Sendable {
    let blockId: String
    let lead: NoticeLead
    let fireDate: Date
    /// When the session ends, after which its notices are out of date.
    let blockEnd: Date
    let title: String
    let subtitle: String
    let body: String

    /// One per session and lead, so rescheduling replaces rather than duplicates.
    var id: String { "session-\(blockId)-\(lead.minutes)" }

    static let idPrefix = "session-"
}

enum SessionNotices {
    /// Every notice the chosen leads give today's blocks, past ones included, earliest first.
    static func all(for blocks: [Block], leads: [NoticeLead]) -> [SessionNotice] {
        blocks.flatMap { block in
            leads.map { lead in
                SessionNotice(
                    blockId: block.id,
                    lead: lead,
                    fireDate: block.start.addingTimeInterval(-Double(lead.minutes) * 60),
                    blockEnd: block.end,
                    title: "\(lead.heading) · \(block.title)",
                    subtitle: "\(Block.timeRange(block)) · \(block.goal)",
                    body: block.aim ?? ""
                )
            }
        }
        .sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
    }

    /// The notices still to send. One whose moment has passed is skipped, never sent late: a
    /// session added at 10:02 for 10:10 gets its 5-minute notice, not the 15-minute one.
    static func upcoming(for blocks: [Block], leads: [NoticeLead], now: Date) -> [SessionNotice] {
        all(for: blocks, leads: leads).filter { $0.fireDate > now }
    }

    /// Notices already shown that are out of date: an earlier one once a later one for the same
    /// session has gone out ("In 5 min" once "Starting now" has), and all of them once the session
    /// is over. Taking these out of Notification Center leaves each session its newest notice.
    static func outdated(for blocks: [Block], leads: [NoticeLead], now: Date) -> [String] {
        let sent = all(for: blocks, leads: leads).filter { $0.fireDate <= now }
        let latest = Dictionary(grouping: sent, by: \.blockId).compactMapValues { $0.max { $0.fireDate < $1.fireDate } }
        let superseded = sent.filter { latest[$0.blockId]?.id != $0.id }.map(\.id)
        // Every lead, not just the chosen ones, so a notice from before the choice changed goes too.
        let over = all(for: blocks.filter { $0.end <= now }, leads: NoticeLead.allCases).map(\.id)
        return Array(Set(superseded + over)).sorted()
    }
}
