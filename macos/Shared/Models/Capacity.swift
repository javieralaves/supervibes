import Foundation

/*
 * Time planned against time protected, for a day or a week on the planning board. Both sides are
 * totals: planned is the open estimates plus the protected time that has already gone by (spent on
 * the goal), and protected is all of it, past or not. What's left of one after the other remains.
 */

/// A goal's time on the calendar: one of its blocks, clipped to this week and next.
struct ProtectedBlock: Hashable, Sendable {
    let start: Date
    let end: Date
}

struct Capacity: Hashable, Sendable {
    /// A day's protected block, or the part of one on that day.
    struct Block: Hashable, Sendable {
        let start: Date
        let end: Date
        /// Over by now.
        let isPast: Bool
        var minutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }
    }

    /// Open estimates, plus protected time that has already gone by.
    let planned: Int
    /// All the protected time, gone by or not.
    let protected: Int
    /// A day's blocks, earliest first; empty for a week.
    var blocks: [Block] = []
    /// A day's, rather than a week's.
    var isDay = false

    var remaining: Int { protected - planned }
    var isOver: Bool { protected > 0 && planned > protected }
    /// How far round the ring goes: planned ÷ protected (0 with nothing protected).
    var share: Double { protected > 0 ? Double(planned) / Double(protected) : 0 }

    /// The blocks still to come (or under way).
    var ahead: [Block] { blocks.filter { !$0.isPast } }

    /// `day` ("YYYY-MM-DD", in this Mac's time zone), with `open` minutes of open estimates on it.
    static func day(_ day: String, open: Int, blocks: [ProtectedBlock], now: Date, calendar: Calendar = .current) -> Capacity {
        let start = midnight(day, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return make(from: start, to: end, open: open, blocks: blocks, now: now, listsBlocks: true)
    }

    /// The week starting on the Monday `weekStart`, with `open` minutes of open estimates meant for it.
    static func week(_ weekStart: String, open: Int, blocks: [ProtectedBlock], now: Date, calendar: Calendar = .current) -> Capacity {
        let start = midnight(weekStart, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return make(from: start, to: end, open: open, blocks: blocks, now: now, listsBlocks: false)
    }

    private static func make(from start: Date, to end: Date, open: Int, blocks: [ProtectedBlock], now: Date, listsBlocks: Bool) -> Capacity {
        let pieces = blocks.compactMap { block -> Block? in
            let (s, e) = (max(block.start, start), min(block.end, end))
            return s < e ? Block(start: s, end: e, isPast: e <= now) : nil
        }
        .sorted { $0.start < $1.start }
        let minutes = { (seconds: TimeInterval) in Int((seconds / 60).rounded()) }
        let protected = pieces.reduce(0) { $0 + minutes($1.end.timeIntervalSince($1.start)) }
        // Under way, a block counts as spent up to now.
        let spent = pieces.reduce(0) { $0 + minutes(max(0, min($1.end, now).timeIntervalSince($1.start))) }
        return Capacity(planned: open + spent, protected: protected, blocks: listsBlocks ? pieces : [], isDay: listsBlocks)
    }

    private static func midnight(_ day: String, calendar: Calendar) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
    }
}

enum BoardDuration {
    /// "3 h 45 min", "2 h", "45 min": the planning board's durations.
    static func text(_ minutes: Int) -> String {
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

extension Clock {
    /// "9:00 – 11:00 AM", "11:00 AM – 1:00 PM" or "09:00 – 11:00", in this Mac's time zone.
    func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        let (from, to) = (CalendarDayMath.minutes(start, calendar: calendar), CalendarDayMath.minutes(end, calendar: calendar))
        guard self == .twelveHour, to > from, (from < 720) == (to < 720) else {
            return "\(format(minutes: from)) – \(format(minutes: to))"
        }
        // Both in the morning or both in the afternoon: the AM or PM once, at the end.
        return "\(format(minutes: from).replacingOccurrences(of: from < 720 ? " AM" : " PM", with: "")) – \(format(minutes: to))"
    }
}
