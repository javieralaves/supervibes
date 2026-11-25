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
    /// The day, "YYYY-MM-DD": its tasks planned for it are the ones counted.
    let day: String
    /// Session time still ahead for the counted tasks on the strip, or nil when nothing dims (no
    /// sessions at all, or a day gone by).
    let budget: Int?

    var id: String { goal.id }

    /// The tasks its session time still ahead doesn't reach.
    var pastTime: Set<String> { pastTime(in: items) }

    /// The same for the tasks in another order, as while one is dragged to a new place: done in that
    /// order, the counted task the time runs out at and every counted task after it.
    func pastTime(in order: [StripItem]) -> Set<String> {
        guard var left = budget else { return [] }
        var past: Set<String> = []
        for item in order where item.task.plannedFor == day {
            if past.isEmpty, item.task.minutes <= left {
                left -= item.task.minutes
            } else {
                past.insert(item.task.id)
            }
        }
        return past
    }

    /// Its tasks with `taskId` moved to `index` among the others.
    func items(moving taskId: String, to index: Int) -> [StripItem] {
        guard let moving = items.first(where: { $0.task.id == taskId }) else { return items }
        var others = items.filter { $0.task.id != taskId }
        others.insert(moving, at: min(max(index, 0), others.count))
        return others
    }

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
            let budget = day < 0 ? nil : timeLeft(for: items, planned: planned, capacity: capacity)
            return DayGoalRow(goal: goal, items: items, capacity: capacity, day: dayISO, budget: budget)
        }
        return rows.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank < b.element.rank : a.offset < b.offset
        }.map(\.element)
    }

    /// The session time still ahead for the counted tasks on the strip. Tasks planned for the day
    /// with a time of their own aren't on the strip, but their estimates still count, so they take
    /// their share first. A goal with no sessions has none to share (its ring says it has no time).
    private func timeLeft(for items: [StripItem], planned: [CalendarTask], capacity: Capacity) -> Int? {
        guard capacity.protected > 0 else { return nil }
        let open = planned.reduce(0) { $0 + $1.minutes }
        // Session time not yet gone by.
        let ahead = capacity.protected - (capacity.planned - open)
        let onStrip = Set(items.map(\.task.id))
        let timed = planned.filter { !onStrip.contains($0.id) }.reduce(0) { $0 + $1.minutes }
        return ahead - timed
    }

    /// A goal's open tasks in their new order once `taskId` is dropped at `index` among the others on
    /// `day`'s strip: just before the strip task it lands above, or just after the last. The goal's
    /// other tasks keep their places. Nil when it isn't on the strip or nothing would change.
    func goalOrder(moving taskId: String, toStripIndex index: Int, day: Int, now: Date, calendar: Calendar = .current) -> (goalId: String, ids: [String])? {
        guard let row = goalRows(day: day, now: now, calendar: calendar).first(where: { $0.items.contains { $0.task.id == taskId } }) else { return nil }
        let others = row.items.map(\.task.id).filter { $0 != taskId }
        let current = tasks.filter { $0.goalId == row.goal.id }.map(\.id)
        var ids = current.filter { $0 != taskId }
        if index < others.count, let at = ids.firstIndex(of: others[max(index, 0)]) {
            ids.insert(taskId, at: at)
        } else if let last = others.last, let at = ids.firstIndex(of: last) {
            ids.insert(taskId, at: at + 1)
        } else {
            return nil
        }
        return ids == current ? nil : (row.goal.id, ids)
    }
}
