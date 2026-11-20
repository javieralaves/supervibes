import Foundation

/*
 * Planning a day across goals (the Plan page): for each goal, the tasks planned for the day in its
 * order, weighed against its session time that day, with a cut line where that time runs out; and
 * how its weeks stand, for deciding where what doesn't fit goes. Designed in supervibes-design
 * ("Cross-goal planning").
 *
 * Only sessions are room for tasks. Reserved time is kept for its own sake, and a task with a time
 * on the calendar (an intention) already has its own: it always fits, on that time, and that time
 * isn't room for anything else.
 */

/// One goal's lane on the Plan page.
struct PlanLane: Identifiable, Hashable, Sendable {
    let goal: CalendarGoal
    /// This week's objective, if it has one.
    let objective: String?
    /// Its open tasks with a time on the calendar that day, earliest first, each with that time.
    let scheduled: [TaskItem]
    /// Its other open tasks planned for the day, in its order: these need room in its sessions.
    let tasks: [TaskItem]
    /// The day's unscheduled tasks against its sessions that day.
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
    var isActive: Bool { !tasks.isEmpty || !scheduled.isEmpty || day.protected > 0 }
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
    /// A goal's sessions: the protected time its unscheduled tasks can go in. Not reserved time,
    /// and not an intention's, which is its own task's.
    func sessionBlocks(_ goalId: String) -> [ProtectedBlock] {
        blocks.filter { $0.goalId == goalId && !$0.reserved && !$0.isIntention }
            .map { ProtectedBlock(start: $0.startsAt, end: $0.endsAt) }
    }

    /// Every goal's lane for `day` ("YYYY-MM-DD"), in the goals' order.
    func planLanes(day: String, now: Date, calendar: Calendar = .current) -> [PlanLane] {
        let today = CalendarDay.today(now)
        let thisWeek = CalendarDay.weekStart(today)
        let nextWeek = CalendarDay.addDays(thisWeek, 7)
        let objectives = objectives(weekStart: CalendarDay.weekStart(day))
        // Each open task's intentions, earliest first: on the calendar, it has its own time.
        var intentions: [String: [CalendarBlock]] = [:]
        for block in blocks.sorted(by: { $0.startsAt < $1.startsAt }) {
            if let taskId = block.taskId { intentions[taskId, default: []].append(block) }
        }
        return goals.map { goal in
            let mine = tasks.filter { $0.goalId == goal.id }.map(\.item)
            let blocks = sessionBlocks(goal.id)
            // On the calendar that day: it fits, on its own time.
            let scheduled: [TaskItem] = mine.compactMap { task in
                guard let block = intentions[task.id]?.first(where: { CalendarDay.today($0.startsAt) == day }) else { return nil }
                var item = task
                item.scheduledAt = block.startsAt
                return item
            }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
            let onCalendar = Set(scheduled.map(\.id))
            let planned = mine.filter { $0.plannedFor == day && !onCalendar.contains($0.id) }
            // A week weighs its tasks without a time in it against its sessions, as the day does.
            func week(_ start: String) -> Capacity {
                let open = mine.filter { task in
                    BoardColumn.week(of: task, today: today) == start
                        && !(intentions[task.id] ?? []).contains { CalendarDay.weekStart(CalendarDay.today($0.startsAt)) == start }
                }
                .reduce(0) { $0 + $1.minutes }
                return .week(start, open: open, blocks: blocks, now: now, calendar: calendar)
            }
            return PlanLane(
                goal: goal,
                objective: objectives[goal.id],
                scheduled: scheduled,
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
