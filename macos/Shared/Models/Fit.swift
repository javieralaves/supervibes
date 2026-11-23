import Foundation

/*
 * Making a day fit when a goal's ring for it is over, as the ring's panel on the planning board
 * offers it. Two ways, in the order Javi plans: keep the time and move tasks out, or keep the
 * tasks and protect more time. Designed in supervibes-design ("Planning, consolidated", 3).
 *
 * Moving out starts from the bottom of the day (the tasks ranked last) and sends each to the first
 * place with room for all of it: a later day this week, then an earlier one still ahead, then next
 * week, then this week without a day while the week as a whole has room. A task with its own time
 * on the calendar stays put. Protecting more time offers free time that day (between the person's
 * waking hours, around every goal's blocks), the slot next to the goal's own session first; and
 * time from another goal's session that day that it has to spare (a goal with tasks that day and
 * room left), taken from its end.
 */
enum Fit {
    /// Where a moved task goes.
    enum Destination: Hashable, Sendable {
        case day(String)
        /// This week, without a day.
        case thisWeek
        case nextWeek

        /// What planning a task there sends.
        func patch(today: String) -> TaskPatch {
            let thisWeek = CalendarDay.weekStart(today)
            return switch self {
            case .day(let day): TaskPatch(plannedFor: day)
            case .thisWeek: TaskPatch(plannedFor: "", plannedWeek: thisWeek)
            case .nextWeek: TaskPatch(plannedFor: "", plannedWeek: CalendarDay.addDays(thisWeek, 7))
            }
        }
    }

    struct Move: Hashable, Sendable {
        let task: TaskItem
        let to: Destination
        /// The room left there once it's moved; below zero never happens.
        let roomAfter: Int
        /// The session time there, for "fills its 2 h".
        let protected: Int
    }

    /// Free time, or time given by another goal, to protect for the goal.
    struct Slot: Hashable, Sendable {
        let start: Date
        let end: Date
        var minutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }
    }

    /// Time another goal's session has to spare that day, taken from its end.
    struct Give: Hashable, Sendable {
        let blockId: String
        let fromGoal: String
        let slot: Slot
    }

    /// How far a goal's day is over: planned (with session time gone by) less its session time.
    static func over(_ goal: BoardGoal, day: String, now: Date) -> Int {
        let capacity = dayCapacity(goal, day, now: now)
        return capacity.protected > 0 || capacity.planned > 0 ? max(0, capacity.planned - capacity.protected) : 0
    }

    // MARK: Moving tasks out

    static func moves(_ goal: BoardGoal, day: String, today: String, now: Date) -> [Move] {
        var over = over(goal, day: day, now: now)
        guard over > 0 else { return [] }
        let thisWeek = CalendarDay.weekStart(today)
        let nextWeek = CalendarDay.addDays(thisWeek, 7)

        // The days still ahead this week: later than the day first, then earlier ones.
        let weekDays = (0..<7).map { CalendarDay.addDays(thisWeek, $0) }.filter { $0 >= today && $0 != day }
        let ordered = weekDays.filter { $0 > day } + weekDays.filter { $0 < day }
        var places: [(destination: Destination, room: Int, protected: Int)] = ordered.compactMap { other in
            let capacity = dayCapacity(goal, other, now: now)
            let room = capacity.protected - capacity.planned
            return room > 0 ? (.day(other), room, capacity.protected) : nil
        }
        let next = Capacity.week(nextWeek, open: open(goal, week: nextWeek, today: today), blocks: goal.protectedBlocks, now: now)
        if next.remaining > 0 { places.append((.nextWeek, next.remaining, next.protected)) }
        // This week without a day only moves a task off the day, not out of the week: it only
        // helps while the week as a whole has room for it.
        let week = Capacity.week(thisWeek, open: open(goal, week: thisWeek, today: today), blocks: goal.protectedBlocks, now: now)
        if CalendarDay.weekStart(day) == thisWeek, week.remaining >= 0 { places.append((.thisWeek, week.remaining, week.protected)) }

        let candidates = goal.tasks.filter { $0.plannedFor == day && $0.scheduledAt == nil }.reversed()
        var moves: [Move] = []
        for task in candidates where over > 0 {
            guard let index = places.firstIndex(where: { place in
                place.destination == .thisWeek || place.room >= task.minutes
            }) else { continue }
            let place = places[index]
            // This week keeps the week's total; the others take the task's time.
            let roomAfter = place.destination == .thisWeek ? place.room : place.room - task.minutes
            moves.append(Move(task: task, to: place.destination, roomAfter: roomAfter, protected: place.protected))
            places[index].room = roomAfter
            over -= task.minutes
        }
        return moves
    }

    // MARK: Protecting more time

    /// Free time that day, at most two slots: next to the goal's own session first, then the
    /// longest; each no longer than the day is over.
    static func freeSlots(for goal: BoardGoal, day: String, in data: BoardData, now: Date, calendar: Calendar = .current) -> [Slot] {
        let need = over(goal, day: day, now: now)
        guard need > 0, let midnight = midnight(day, calendar: calendar) else { return [] }
        let wake = midnight.addingTimeInterval(Double(data.wakeTime) * 60)
        let sleep = data.sleepStart > data.wakeTime
            ? midnight.addingTimeInterval(Double(data.sleepStart) * 60)
            : calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        let from = max(wake, quarter(after: now))
        guard from < sleep else { return [] }

        let busy = data.blocks.filter { $0.end > from && $0.start < sleep }.sorted { $0.start < $1.start }
        var gaps: [Slot] = []
        var cursor = from
        for block in busy {
            if block.start > cursor { gaps.append(Slot(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < sleep { gaps.append(Slot(start: cursor, end: sleep)) }
        gaps = gaps.filter { $0.minutes >= 15 }

        let own = data.blocks.filter { $0.goalId == goal.id && $0.isSession }
        let need15 = Double(need) * 60
        func sized(_ gap: Slot) -> Slot {
            // Right after the goal's session, or right before one, sized to what's needed.
            if own.contains(where: { $0.start == gap.end }), !own.contains(where: { $0.end == gap.start }) {
                return Slot(start: max(gap.start, gap.end.addingTimeInterval(-need15)), end: gap.end)
            }
            return Slot(start: gap.start, end: min(gap.end, gap.start.addingTimeInterval(need15)))
        }
        let touching = gaps.filter { gap in own.contains { $0.end == gap.start || $0.start == gap.end } }
        let rest = gaps.filter { !touching.contains($0) }.sorted { $0.minutes > $1.minutes }
        return Array((touching + rest).prefix(2).map(sized))
    }

    /// Another goal's session that day with time to spare (its own day not full), the most first:
    /// as much of it as the day is over, taken from its end, never more than it can spare.
    static func gives(to goal: BoardGoal, day: String, in data: BoardData, now: Date) -> [Give] {
        let need = over(goal, day: day, now: now)
        guard need > 0 else { return [] }
        var gives: [Give] = []
        // Only a goal with tasks that day can have time to spare: one with time and no tasks keeps
        // its time for its own sake, like a workout.
        for other in data.goals where other.id != goal.id && other.tasks.contains(where: { $0.plannedFor == day }) {
            let capacity = dayCapacity(other, day, now: now)
            let spare = (capacity.protected - capacity.planned) / 15 * 15
            guard spare >= 15 else { continue }
            let sessions = data.blocks.filter { $0.goalId == other.id && $0.isSession && $0.start >= now && CalendarDay.today($0.start) == day }
            guard let block = sessions.max(by: { $0.minutes < $1.minutes }) else { continue }
            let minutes = min(spare, need, block.minutes)
            gives.append(Give(blockId: block.id, fromGoal: other.id, slot: Slot(start: block.end.addingTimeInterval(-Double(minutes) * 60), end: block.end)))
        }
        return gives.sorted { $0.slot.minutes > $1.slot.minutes }
    }

    // MARK: Helpers

    private static func dayCapacity(_ goal: BoardGoal, _ day: String, now: Date) -> Capacity {
        Capacity.day(day, open: goal.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }, blocks: goal.protectedBlocks, now: now)
    }

    private static func open(_ goal: BoardGoal, week: String, today: String) -> Int {
        goal.tasks.filter { BoardColumn.week(of: $0, today: today) == week }.reduce(0) { $0 + $1.minutes }
    }

    private static func midnight(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The next quarter hour from `date`.
    private static func quarter(after date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 900).rounded(.up) * 900)
    }
}
