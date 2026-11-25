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

// MARK: - A task's menu

/// What a task's menu on the strip can offer beyond the usual rows. A task within its goal's time:
/// when its turn in the goal's sessions is (to schedule it there). A task past it: the first place
/// with room for it and the free time that day next to the goal's sessions (the board's Make it fit,
/// for one task). Either way, what moving it to the top would push out.
struct TaskSuggestions: Sendable {
    /// Its turn in the goal's sessions ahead: start and end, in minutes from midnight, and the
    /// session's start.
    var turn: (start: Int, end: Int, session: Int)?
    /// Past its goal's time: where it would go on its own, and free time to protect for it.
    var move: Fit.Move?
    var protect: Fit.Slot?
    /// The first task that would stop fitting if it went to the top, if any.
    var pushesOut: String?
    /// Already first in its list.
    var isFirst = false
    /// Past its goal's time that day.
    var isPastTime = false
}

extension CalendarData {
    /// The calendar as the planning board has it, for Fit: each goal's open tasks (with when they're
    /// next on the calendar), its blocks that aren't reserved, and every block.
    func board(now: Date) -> BoardData {
        let next = nextBlocks(now: now)
        return BoardData(
            today: CalendarDay.today(now),
            clock: clock,
            goals: goals.map { goal in
                BoardGoal(
                    id: goal.id, title: goal.title, icon: goal.icon, color: goal.color, objective: nil,
                    tasks: tasks.filter { $0.goalId == goal.id }.map { task in
                        var item = task.item
                        item.scheduledAt = next[task.id]?.startsAt
                        return item
                    },
                    done: [],
                    protectedBlocks: blocks.filter { $0.goalId == goal.id && !$0.reserved }.map { ProtectedBlock(start: $0.startsAt, end: $0.endsAt) }
                )
            },
            blocks: blocks.map { BoardBlock(id: $0.id, goalId: $0.goalId, start: $0.startsAt, end: $0.endsAt, reserved: $0.reserved, taskId: $0.taskId) },
            wakeTime: wakeTime,
            sleepStart: sleepStart
        )
    }

    /// What `taskId`'s menu on `day`'s strip can offer; nil when it isn't on the strip.
    func suggestions(for taskId: String, day: Int, now: Date, calendar: Calendar = .current) -> TaskSuggestions? {
        guard let row = goalRows(day: day, now: now, calendar: calendar).first(where: { $0.items.contains { $0.task.id == taskId } }),
              let item = row.items.first(where: { $0.task.id == taskId }) else { return nil }
        var suggestions = TaskSuggestions()
        let past = row.pastTime
        suggestions.isPastTime = past.contains(taskId)
        suggestions.isFirst = row.items.first?.task.id == taskId
        if !suggestions.isFirst {
            let order = row.items(moving: taskId, to: 0)
            let newlyPast = row.pastTime(in: order).subtracting(past)
            suggestions.pushesOut = order.first { newlyPast.contains($0.task.id) }?.task.title
        }
        // Only the tasks counted for the day have a turn, a place to move from, or time to protect.
        guard item.task.plannedFor == row.day, day >= 0 else { return suggestions }
        if suggestions.isPastTime {
            let board = board(now: now)
            if let goal = board.goal(row.goal.id), let task = goal.tasks.first(where: { $0.id == taskId }) {
                suggestions.move = Fit.destination(for: task, of: goal, day: row.day, today: board.today, now: now)
                suggestions.protect = Fit.freeSlots(for: goal, day: row.day, in: board, now: now, need: task.minutes, calendar: calendar).first
            }
        } else {
            suggestions.turn = turn(of: taskId, in: row, day: day, now: now, calendar: calendar)
        }
        return suggestions
    }

    /// When a task within its goal's time would happen, done in the goal's order: each counted task
    /// takes the next stretch of the goal's sessions ahead long enough for it, a session's leftover
    /// too short for the next one going unused.
    private func turn(of taskId: String, in row: DayGoalRow, day: Int, now: Date, calendar: Calendar) -> (start: Int, end: Int, session: Int)? {
        let midnight = CalendarDayMath.midnight(day, from: now)
        let nowMinutes = day == 0 ? CalendarDayMath.minutes(now) : 0
        let sessions = blocks
            .filter { $0.goalId == row.goal.id && !$0.reserved && $0.taskId == nil && calendar.isDate($0.startsAt, inSameDayAs: midnight) }
            .map { (start: CalendarDayMath.minutes($0.startsAt), end: CalendarDayMath.minutes($0.endsAt)) }
            .filter { $0.end > nowMinutes }
            .sorted { $0.start < $1.start }
        let past = row.pastTime
        var index = 0
        // Under way: from now, on the next quarter hour.
        var cursor = sessions.first.map { max($0.start, (nowMinutes + 14) / 15 * 15) } ?? 0
        for item in row.items where item.task.plannedFor == row.day && !past.contains(item.task.id) {
            while index < sessions.count, cursor + item.task.minutes > sessions[index].end {
                index += 1
                if index < sessions.count { cursor = max(sessions[index].start, cursor) }
            }
            guard index < sessions.count else { return nil }
            if item.task.id == taskId { return (cursor, cursor + item.task.minutes, sessions[index].start) }
            cursor += item.task.minutes
        }
        return nil
    }
}
