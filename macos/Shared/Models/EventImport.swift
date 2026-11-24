import Foundation

/*
 * Calendar import: events from the person's Google calendars, read on this Mac through macOS
 * Calendar (EventKit, in Supervibes/Calendar/EventFeed.swift), imported one at a time as ordinary
 * blocks. These are the plain shapes and rules, with no EventKit in them, so views and tests can
 * use them. Designed in supervibes-design ("Calendar import").
 */

/// An event in one of the person's Google calendars.
struct ExternalEvent: Identifiable, Hashable, Sendable {
    /// Stable across syncs and edits (see `EventKey`).
    let key: String
    var id: String { key }
    /// The calendar's EventKit identifier, and its name ("Work").
    let calendarId: String
    let calendarName: String
    let title: String
    let start: Date
    let end: Date
    /// One of a recurring series: importing brings in this one only.
    var repeats = false

    /// The event as it is now, as an imported block's baseline.
    var snapshot: EventSource.Snapshot { .init(title: title, startsAt: start, endsAt: end) }
}

/// A Google calendar the person can pick in Settings.
struct ExternalCalendar: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

/// The stable key an imported block keeps for its event. Verified against Google calendars on
/// 2026-11-24: EventKit's own `eventIdentifier` and `calendarItemIdentifier` change when one of a
/// series is moved, so neither will do.
enum EventKey {
    /// A one-off event: its external identifier (its iCal UID), which survives moves and renames.
    /// One of a series: they all share the UID, so it's the UID plus the occurrence's original
    /// time. Google gives a moved occurrence a UID ending in `/RID=<its original time>`, which comes
    /// off, so it keeps its key.
    static func make(externalId: String, isOccurrence: Bool, occurrenceDate: Date?) -> String {
        guard isOccurrence, let occurrenceDate else { return externalId }
        let base = externalId.range(of: "/RID=").map { String(externalId[..<$0.lowerBound]) } ?? externalId
        return "\(base)|\(occurrenceDate.formatted(.iso8601))"
    }

    /// Whether a calendar account is a Google one: Google accounts are CalDAV and named after the
    /// account (an email address); iCloud is CalDAV too, but named "iCloud".
    static func isGoogleAccount(isCalDAV: Bool, title: String) -> Bool {
        isCalDAV && !title.isEmpty && title != "iCloud"
    }
}

/// Where an imported block came from: its event's key, its calendar's name, and the event as the
/// person last agreed with it.
struct EventSource: Hashable, Sendable {
    struct Snapshot: Hashable, Sendable {
        let title: String
        let startsAt: Date
        let endsAt: Date
    }

    let key: String
    let calendar: String
    let snapshot: Snapshot
}

/// How an imported event comes in: as a session to work in, or reserved time kept for itself.
enum ImportKind: String, CaseIterable, Codable, Hashable, Sendable {
    case session, reserved

    var label: String { self == .session ? "Session" : "Reserved" }
}

/// Calendar import's settings. Calendar access belongs to this Mac, so they're kept on it.
struct EventImportSettings: Codable, Hashable, Sendable {
    /// Events listed on the Calendar to import.
    var isOn = true
    /// The calendars whose events are listed, by identifier; nil until the person picks, meaning all.
    var calendarIds: Set<String>?
    /// The goal an import goes to unless another is picked; nil or gone means the first goal.
    var goalId: String?
    var kind = ImportKind.session
    var hidesAllDay = true

    static let defaults = EventImportSettings()

    func includes(_ calendar: ExternalCalendar) -> Bool {
        calendarIds?.contains(calendar.id) ?? true
    }

    /// Ticks or unticks a calendar; the first change pins the rest as they were.
    mutating func set(_ calendar: ExternalCalendar, on: Bool, among all: [ExternalCalendar]) {
        var ids = calendarIds ?? Set(all.map(\.id))
        if on { ids.insert(calendar.id) } else { ids.remove(calendar.id) }
        calendarIds = ids
    }

    /// The goal an import goes to: the one picked, while it's still there, else the first.
    func goal(among ids: [String]) -> String? {
        if let goalId, ids.contains(goalId) { return goalId }
        return ids.first
    }

    // MARK: Stored on this Mac

    static let storageKey = "sv-event-import"

    static func load(from defaults: UserDefaults = .standard) -> EventImportSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(EventImportSettings.self, from: data) else { return .defaults }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }
}

/// Whether macOS lets Supervibes read calendars.
enum CalendarAccess: Hashable, Sendable {
    /// Not asked yet; Settings asks.
    case notAsked
    case allowed
    /// Turned off for Supervibes in System Settings (or restricted).
    case denied
}

/// What a sync found for one imported block, comparing three versions: the event as last agreed
/// (the block's snapshot), the block now, and the event now.
enum ImportCheck: Hashable, Sendable {
    /// Nothing to say.
    case inStep
    /// The event changed only in ways the block already matches (both moved to the same time):
    /// the baseline catches up without asking.
    case catchUp(EventSource.Snapshot)
    /// Something to offer.
    case changed(ImportChange)

    /// The longest block title, as the server keeps it (MAX_BLOCK_TITLE).
    static let maxBlockTitle = 120

    /// An event's title as a block takes it: trimmed, and cut to the block's limit.
    static func blockTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxBlockTitle))
    }

    /// The times a block takes from an event: at least 15 minutes and at most a day, as blocks
    /// must be. A 10-minute call comes in as 15 minutes; it isn't offered as moved for that.
    static func blockTimes(_ start: Date, _ end: Date) -> (start: Date, end: Date) {
        let length = min(max(end.timeIntervalSince(start), 15 * 60), 24 * 60 * 60)
        return (start, start.addingTimeInterval(length))
    }

    /// `event` is nil when the event is gone from a calendar that's still ticked and readable.
    static func check(_ source: EventSource, title: String?, start: Date, end: Date, event: ExternalEvent?) -> ImportCheck {
        guard let event else { return .changed(ImportChange(event: nil)) }
        let base = source.snapshot
        let now = event.snapshot

        let mineTitle = title ?? ""
        let theirsTitle = blockTitle(now.title)
        let renamed = theirsTitle != blockTitle(base.title)
        let titleOffer = renamed && mineTitle != theirsTitle

        let moved = !same(now.startsAt, base.startsAt) || !same(now.endsAt, base.endsAt)
        let baseTimes = blockTimes(base.startsAt, base.endsAt)
        let theirs = blockTimes(now.startsAt, now.endsAt)
        let mineMoved = !same(start, baseTimes.start) || !same(end, baseTimes.end)
        let agrees = same(start, theirs.start) && same(end, theirs.end)
        let timesOffer = moved && !agrees

        guard titleOffer || timesOffer else { return now == base ? .inStep : .catchUp(now) }
        return .changed(ImportChange(
            event: now,
            title: titleOffer ? theirsTitle : nil,
            times: timesOffer ? theirs : nil,
            bothMoved: timesOffer && mineMoved
        ))
    }

    /// Times to the second: the server keeps milliseconds, EventKit whole seconds.
    private static func same(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1 }
}

/// A change to offer on an imported block.
struct ImportChange: Hashable, Sendable {
    /// The event as it is now, the new baseline whichever answer is given; nil when it's gone.
    let event: EventSource.Snapshot?
    /// Its new title, when it was renamed and the block doesn't have it.
    var title: String?
    /// Its new times, when it moved and the block isn't there.
    var times: (start: Date, end: Date)?
    /// The block was moved too, somewhere else: both versions are shown.
    var bothMoved = false

    var isGone: Bool { event == nil }

    static func == (a: ImportChange, b: ImportChange) -> Bool {
        a.event == b.event && a.title == b.title && a.times?.start == b.times?.start && a.times?.end == b.times?.end && a.bothMoved == b.bothMoved
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(event)
        hasher.combine(title)
        hasher.combine(times?.start)
        hasher.combine(times?.end)
        hasher.combine(bothMoved)
    }
}
