import Foundation

/*
 * Planning a day across goals (the Plan page): for each goal, the tasks planned for the day in its
 * order, weighed against its session time that day, with a cut line where that time runs out; and
 * how its weeks stand, for deciding where what doesn't fit goes. Reserved time isn't room for
 * tasks, as on the planning board. Designed in supervibes-design ("Cross-goal planning").
 */

/// One goal's lane on the Plan page.
struct PlanLane: Identifiable, Hashable, Sendable {
    let goal: CalendarGoal
    /// This week's objective, if it has one.
    let objective: String?
    /// Its open tasks planned for the day, in its order.
    let tasks: [TaskItem]
    /// The day's tasks against its sessions that day, as the planning board weighs a day.
    let day: Capacity
    let thisWeek: Capacity
    let nextWeek: Capacity

    var id: String { goal.id }

    /// The day's open estimates.
    var open: Int { tasks.reduce(0) { $0 + $1.minutes } }

    /// Session time still there for tasks: all of it, less what has already gone by.
    var room: Int { max(0, day.protected - (day.planned - open)) }

    /// How many of its tasks, in order, fit in the room; the cut line falls after them.
    var fitting: Int {
        var used = 0
        for (index, task) in tasks.enumerated() {
            used += task.minutes
            if used > room { return index }
        }
        return tasks.count
    }

    /// The tasks under the cut line.
    var overflow: [TaskItem] { Array(tasks.dropFirst(fitting)) }
    var overflowMinutes: Int { overflow.reduce(0) { $0 + $1.minutes } }
    /// Room left once every task is in.
    var spare: Int { room - open }

    /// Something to plan here: tasks for the day, or sessions to put them in.
    var isActive: Bool { !tasks.isEmpty || day.protected > 0 }
}

/// The waking day, split into sessions (by goal), reserved time, and what's free.
struct DayBudget: Hashable, Sendable {
    struct Share: Hashable, Sendable {
        let goalId: String
        let minutes: Int
    }

    let awake: Int
    /// Each goal's sessions, in the goals' order.
    let sessions: [Share]
    let reserved: Int

    var sessionMinutes: Int { sessions.reduce(0) { $0 + $1.minutes } }
    var free: Int { max(0, awake - sessionMinutes - reserved) }
}

/// Some of a session's time, previewed as given to another goal: the session ends `minutes` earlier
/// and that time becomes the other goal's. Or, with `whole`, all of the block changes hands.
struct GiveTime: Hashable, Sendable {
    let blockId: String
    let goalId: String
    let minutes: Int
    var whole = false
}

extension CalendarTask {
    /// As the goal page has it, for the board's rows and the planning rules they share.
    var item: TaskItem {
        TaskItem(id: id, title: title, minutes: minutes, plannedFor: plannedFor, plannedWeek: plannedWeek, dueOn: dueOn, isPending: isPending)
    }
}

extension CalendarData {
    /// A goal's protected time that tasks can go in: everything but reserved time.
    func sessionBlocks(_ goalId: String) -> [ProtectedBlock] {
        blocks.filter { $0.goalId == goalId && !$0.reserved }.map { ProtectedBlock(start: $0.startsAt, end: $0.endsAt) }
    }

    /// Every goal's lane for `day` ("YYYY-MM-DD"), in the goals' order.
    func planLanes(day: String, now: Date, calendar: Calendar = .current) -> [PlanLane] {
        let today = CalendarDay.today(now)
        let thisWeek = CalendarDay.weekStart(today)
        let nextWeek = CalendarDay.addDays(thisWeek, 7)
        let objectives = objectives(weekStart: CalendarDay.weekStart(day))
        return goals.map { goal in
            let mine = tasks.filter { $0.goalId == goal.id }.map(\.item)
            let blocks = sessionBlocks(goal.id)
            let planned = mine.filter { $0.plannedFor == day }
            func week(_ start: String) -> Capacity {
                let open = mine.filter { BoardColumn.week(of: $0, today: today) == start }.reduce(0) { $0 + $1.minutes }
                return .week(start, open: open, blocks: blocks, now: now, calendar: calendar)
            }
            return PlanLane(
                goal: goal,
                objective: objectives[goal.id],
                tasks: planned,
                day: .day(day, open: planned.reduce(0) { $0 + $1.minutes }, blocks: blocks, now: now, calendar: calendar),
                thisWeek: week(thisWeek),
                nextWeek: week(nextWeek)
            )
        }
    }

    /// The day `offset` days from `now`'s, from waking to sleep, by what its time is held for.
    func budget(day offset: Int, now: Date) -> DayBudget {
        let awake = (sleepStart - wakeTime + CalendarDayMath.dayMinutes) % CalendarDayMath.dayMinutes
        var sessions: [String: Int] = [:]
        var reserved = 0
        for block in blocks {
            for segment in DaySegment.of(block, today: now) where segment.day == offset {
                let minutes = segment.end - segment.start
                if block.reserved { reserved += minutes } else { sessions[block.goalId, default: 0] += minutes }
            }
        }
        return DayBudget(
            awake: awake == 0 ? CalendarDayMath.dayMinutes : awake,
            sessions: goals.compactMap { goal in sessions[goal.id].map { DayBudget.Share(goalId: goal.id, minutes: $0) } },
            reserved: reserved
        )
    }

    /// The calendar with `give` made: the block ends earlier and the other goal has a new block for
    /// that time (`newId`), or the whole block is the other goal's.
    func giving(_ give: GiveTime, newId: String = "giving") -> CalendarData {
        guard let index = blocks.firstIndex(where: { $0.id == give.blockId }) else { return self }
        var data = self
        if give.whole {
            data.blocks[index].goalId = give.goalId
            return data
        }
        let block = blocks[index]
        let cut = block.endsAt.addingTimeInterval(-Double(give.minutes) * 60)
        guard cut > block.startsAt else { return self }
        data.blocks[index].endsAt = cut
        data.blocks.append(CalendarBlock(id: newId, goalId: give.goalId, title: nil, startsAt: cut, endsAt: block.endsAt))
        return data
    }

    /// What a session has to spare for another goal: its goal's room left that day once its tasks
    /// are in, no more than the part of this block still ahead, in quarter hours.
    func spare(in block: CalendarBlock, lane: PlanLane?, now: Date) -> Int {
        guard !block.reserved, !block.isIntention, let lane, block.endsAt > now else { return 0 }
        let ahead = Int(block.endsAt.timeIntervalSince(max(block.startsAt, now)) / 60)
        return CalendarDayMath.snapDown(min(ahead, max(0, lane.spare)))
    }
}

/// "Monday, Nov 23": a day's full weekday and date, in US English as the app writes dates.
enum PlanDay {
    static func title(offset: Int, day: String) -> String {
        switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: weekday(day, style: .wide)
        }
    }

    static func subtitle(_ day: String) -> String {
        guard let date = CalendarDay.date(day) else { return day }
        let format = Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        return "\(date.formatted(format.weekday(.wide))), \(date.formatted(format.month(.abbreviated).day()))"
    }

    static func weekday(_ day: String, style: Date.FormatStyle.Symbol.Weekday = .abbreviated) -> String {
        guard let date = CalendarDay.date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(style))
    }
}
