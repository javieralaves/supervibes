import Foundation

/*
 * What the Calendar shows, and where in time. Day is one day. Next N days are 3, 5 or 7 days with
 * today first. Week is Monday to Sunday. The multi-day views scroll a day at a time, so their first
 * column can be any day; Today brings back where each one starts.
 *
 * Days are counted from today, as the views draw them. When the day changes under an open Calendar,
 * a view that was where Today puts it moves on with the day, and one that was scrolled or stepped
 * elsewhere stays on its dates.
 *
 * What the Calendar opens on is picked in Settings and kept on this Mac, like the Calendar's other
 * view state.
 */

enum CalendarSpan: Hashable, Sendable {
    case day
    /// The next few days, today first: 3, 5 or 7.
    case days(Int)
    /// Monday to Sunday.
    case week

    /// How many days Next N days can show.
    static let dayCounts = [3, 5, 7]
    /// In the order the switch and Settings list them.
    static let all: [CalendarSpan] = [.day] + dayCounts.map { .days($0) } + [.week]

    /// How many columns it shows.
    var count: Int {
        switch self {
        case .day: 1
        case .days(let n): n
        case .week: 7
        }
    }

    var isMultiDay: Bool { self != .day }

    /// The count for Next N days, or nil for Day and Week.
    var dayCount: Int? {
        if case .days(let n) = self { return n }
        return nil
    }

    /// Where Today puts the first column, in days from today: today, or this week's Monday.
    func home(now: Date) -> Int {
        self == .week ? CalendarDayMath.monday(of: 0, from: now) : 0
    }

    /// "Day", "3 days", "Week".
    var label: String {
        switch self {
        case .day: "Day"
        case .days(let n): "\(n) days"
        case .week: "Week"
        }
    }

    /// "Next 3 days", for menus.
    var title: String {
        switch self {
        case .day: "Day"
        case .days(let n): "Next \(n) days"
        case .week: "Week"
        }
    }
}

extension CalendarSpan: RawRepresentable {
    /// "day", "days-3", "week": "day" and "week" are what the Calendar's switch saved before.
    init?(rawValue: String) {
        switch rawValue {
        case "day": self = .day
        case "week": self = .week
        default:
            guard rawValue.hasPrefix("days-"), let n = Int(rawValue.dropFirst(5)), Self.dayCounts.contains(n) else { return nil }
            self = .days(n)
        }
    }

    var rawValue: String {
        switch self {
        case .day: "day"
        case .days(let n): "days-\(n)"
        case .week: "week"
        }
    }
}

// MARK: - Kept on this Mac

extension CalendarSpan {
    /// What the Calendar opens on, as picked in Settings.
    static let openingKey = "sv-calendar-opens-on"
    /// The view the Calendar's switch was last left on, before Settings picked one.
    static let legacyKey = "sv-calendar-view"
    /// The count Next N days last showed, for the switch's button.
    static let dayCountKey = "sv-calendar-day-count"

    /// What the Calendar opens on: the Settings choice, or before there is one, the view it was
    /// last left on, so nobody's Calendar changes under them.
    static func opening(_ defaults: UserDefaults = .standard) -> CalendarSpan {
        for key in [openingKey, legacyKey] {
            if let raw = defaults.string(forKey: key), let span = CalendarSpan(rawValue: raw) { return span }
        }
        return .day
    }

    static func setOpening(_ span: CalendarSpan, _ defaults: UserDefaults = .standard) {
        defaults.set(span.rawValue, forKey: openingKey)
        if let n = span.dayCount { setLastDayCount(n, defaults) }
    }

    /// The count Next N days last showed, 3 until there's one.
    static func lastDayCount(_ defaults: UserDefaults = .standard) -> Int {
        let n = defaults.integer(forKey: dayCountKey)
        return dayCounts.contains(n) ? n : 3
    }

    static func setLastDayCount(_ n: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(n, forKey: dayCountKey)
    }
}

// MARK: - Where the Calendar is

/// Which days the Calendar shows: the day stepped into, and the first column of the multi-day views.
/// The arrows, scrolling, Today and the day changing all go through here.
struct CalendarWindow: Equatable, Sendable {
    private(set) var span: CalendarSpan
    /// The day Day shows, in days from today. In a multi-day view, it's one of the days shown.
    private(set) var offset = 0
    /// The first column of a multi-day view, in days from today.
    private(set) var first: Int
    /// What's loaded, in days from today.
    private(set) var loaded: ClosedRange<Int>

    init(span: CalendarSpan, now: Date, loaded: ClosedRange<Int> = -36...42) {
        self.span = span
        self.loaded = loaded
        first = span.home(now: now)
        first = clampedFirst(first)
    }

    /// The days a multi-day view shows (Day's own day, in Day).
    var shown: ClosedRange<Int> { span.isMultiDay ? first...(first + span.count - 1) : offset...offset }

    /// Where the first column can go: all of its days within what's loaded.
    var firstRange: ClosedRange<Int> {
        loaded.lowerBound...max(loaded.lowerBound, loaded.upperBound - (span.count - 1))
    }

    /// Where Today would put it: today in Day, otherwise the first column back home.
    func isHome(now: Date) -> Bool {
        span.isMultiDay ? first == clampedFirst(span.home(now: now)) : offset == 0
    }

    /// Another view. A multi-day view opens where Today puts it if that shows the day you were on;
    /// otherwise it shows that day: in its Monday-to-Sunday week, or first.
    mutating func setSpan(_ span: CalendarSpan, now: Date) {
        self.span = span
        guard span.isMultiDay else { return }
        let home = clampedFirst(span.home(now: now))
        first = home
        if !shown.contains(offset) { first = clampedFirst(anchor(for: offset, now: now)) }
        holdOffset()
    }

    /// A day back or forward: Day's arrows. Leaving the days a multi-day view shows, it moves to
    /// show that day.
    mutating func step(_ by: Int, now: Date) {
        show(day: offset + by, now: now)
    }

    /// Shows a day: in a multi-day view, where it already is if it's shown, or else it moves.
    mutating func show(day: Int, now: Date) {
        offset = min(max(day, loaded.lowerBound), loaded.upperBound)
        if span.isMultiDay, !shown.contains(offset) {
            first = clampedFirst(anchor(for: offset, now: now))
            holdOffset()
        }
    }

    /// The first column by that many days: the multi-day views' arrows (a page) and scrolling (a
    /// day or more). The day stepped into moves with it.
    mutating func scroll(_ by: Int) {
        let moved = clampedFirst(first + by)
        offset += moved - first
        first = moved
        holdOffset()
    }

    /// Today, and in a multi-day view, its first column back home.
    mutating func today(now: Date) {
        offset = 0
        first = clampedFirst(span.home(now: now))
    }

    /// What's loaded changed (a refresh).
    mutating func setLoaded(_ range: ClosedRange<Int>) {
        loaded = range
        offset = min(max(offset, loaded.lowerBound), loaded.upperBound)
        first = clampedFirst(first)
        if span.isMultiDay { holdOffset() }
    }

    /// The day changed by `days` (midnight passed) between `before` and `now`. Where Today puts it
    /// moves on with the day; anywhere else stays on its dates, now a day nearer.
    mutating func dayChanged(by days: Int, before: Date, now: Date) {
        guard days != 0 else { return }
        let wasHome = isHome(now: before)
        // What's loaded stays on its dates until the next refresh.
        loaded = (loaded.lowerBound - days)...(loaded.upperBound - days)
        offset = offset == 0 ? 0 : offset - days
        first = wasHome ? span.home(now: now) : first - days
        first = clampedFirst(first)
        offset = min(max(offset, loaded.lowerBound), loaded.upperBound)
        if span.isMultiDay { holdOffset() }
    }

    /// Where a multi-day view goes to show `day`: its Monday-to-Sunday week, or that day first.
    private func anchor(for day: Int, now: Date) -> Int {
        span == .week ? CalendarDayMath.monday(of: day, from: now) : day
    }

    private func clampedFirst(_ day: Int) -> Int {
        min(max(day, firstRange.lowerBound), firstRange.upperBound)
    }

    /// Keeps the day stepped into among the days shown.
    private mutating func holdOffset() {
        offset = min(max(offset, first), first + span.count - 1)
    }
}
