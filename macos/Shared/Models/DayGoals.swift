import Foundation

/*
 * The Day view's Anytime strip, a row per goal ("The day, by goal" in supervibes-design). Each goal
 * with tasks on the strip gets its tasks, in the goal's order, and its time that day as the planning
 * board's day cell counts it: open tasks planned for the day against its sessions (Capacity.day), so
 * the two always agree. Tasks only due that day, or carried over from an earlier day, are listed but
 * not counted, as on the board.
 *
 * The tasks planned for the day are done in the goal's order, so the session time still ahead runs
 * out at some task: that one and every counted task after it are past the goal's time, and dim.
 */

/// A goal's row on a day's strip.
struct DayGoalRow: Identifiable, Hashable, Sendable {
    let goal: CalendarGoal
    /// Its tasks on the strip, in the goal's order (those planned for the day first).
    let items: [StripItem]
    /// Its tasks planned for the day against its sessions, as the board's day cell.
    let capacity: Capacity
    /// The tasks its session time still ahead doesn't reach.
    let pastTime: Set<String>

    var id: String { goal.id }

    /// Which way the goal's tasks are off its session time, and by how much.
    enum Gap: Hashable, Sendable {
        /// Its tasks run past its sessions by this much.
        case over(Int)
        /// It has tasks planned for the day and no sessions at all.
        case noSessions(Int)
        /// Time left in its sessions.
        case spare(Int)
        /// Its tasks fill its sessions exactly.
        case fits
        /// Nothing planned for the day and no sessions: only due or carried-over tasks.
        case nothingPlanned
    }

    var gap: Gap {
        if capacity.protected == 0 { return capacity.planned > 0 ? .noSessions(capacity.planned) : .nothingPlanned }
        let remaining = capacity.remaining
        return remaining < 0 ? .over(-remaining) : remaining > 0 ? .spare(remaining) : .fits
    }

    /// "Needs 1 h 30 min", "45 min spare", "Fits", "No time".
    var gapLabel: String {
        switch gap {
        case .over(let minutes), .noSessions(let minutes): "Needs \(BoardDuration.text(minutes))"
        case .spare(let minutes): "\(BoardDuration.text(minutes)) spare"
        case .fits: "Fits"
        case .nothingPlanned: "No time"
        }
    }

    /// Over its sessions: its gap is amber.
    var isOver: Bool { if case .over = gap { true } else { false } }

    /// The strip's order: over first (most over first), then goals with tasks and no sessions (most
    /// first), then the rest, each in the goals' own order otherwise.
    fileprivate var rank: (Int, Int) {
        switch gap {
        case .over(let minutes): (0, -minutes)
        case .noSessions(let minutes): (1, -minutes)
        case .nothingPlanned: (2, 0)
        case .spare, .fits: (3, 0)
        }
    }
}

extension CalendarData {
    /// The strip for `day` (days from today), a row per goal with tasks on it.
    func goalRows(day: Int, now: Date, calendar: Calendar = .current) -> [DayGoalRow] {
        let dayISO = CalendarDay.today(CalendarDayMath.midnight(day, from: now))
        let strip = strip(day: day, today: now)
        let rows = goals.compactMap { goal -> DayGoalRow? in
            let items = strip.filter { $0.task.goalId == goal.id }
            guard !items.isEmpty else { return nil }
            // As the board: open tasks planned for the day, against the goal's blocks that aren't reserved.
            let planned = tasks.filter { $0.goalId == goal.id && $0.plannedFor == dayISO }
            let open = planned.reduce(0) { $0 + $1.minutes }
            let sessions = blocks.filter { $0.goalId == goal.id && !$0.reserved }.map { ProtectedBlock(start: $0.startsAt, end: $0.endsAt) }
            let capacity = Capacity.day(dayISO, open: open, blocks: sessions, now: now, calendar: calendar)
            return DayGoalRow(goal: goal, items: items, capacity: capacity, pastTime: pastTime(items, planned: planned, capacity: capacity, onPastDay: day < 0, dayISO: dayISO))
        }
        return rows.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map(\.element)
    }

    /// The counted tasks on the strip that the goal's session time still ahead doesn't reach. Tasks
    /// planned for the day with a time of their own aren't on the strip, but their estimates still
    /// count, so they take their share first. A goal with no sessions dims nothing (it has no time at
    /// all, which its ring says), and neither does a day gone by.
    private func pastTime(_ items: [StripItem], planned: [CalendarTask], capacity: Capacity, onPastDay: Bool, dayISO: String) -> Set<String> {
        guard capacity.protected > 0, !onPastDay else { return [] }
        let open = planned.reduce(0) { $0 + $1.minutes }
        // Session time not yet gone by.
        let ahead = capacity.protected - (capacity.planned - open)
        let onStrip = Set(items.map(\.task.id))
        let timed = planned.filter { !onStrip.contains($0.id) }.reduce(0) { $0 + $1.minutes }
        var left = ahead - timed
        var past: Set<String> = []
        for item in items where item.task.plannedFor == dayISO {
            if past.isEmpty, item.task.minutes <= left {
                left -= item.task.minutes
            } else {
                past.insert(item.task.id)
            }
        }
        return past
    }
}
