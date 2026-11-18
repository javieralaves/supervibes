import Foundation

/*
 * The calendar's data (GET /api/v1/calendar) and the shape of a day on it, as in
 * src/app/(app)/calendar and src/lib/day.ts. Times on a day are minutes from local midnight.
 */

/// An intention (it schedules a task) or protected time (held for a goal).
struct CalendarBlock: Identifiable, Hashable, Sendable {
    let id: String
    var goalId: String
    /// nil for protected time without a name: it shows the goal's title.
    var title: String?
    /// For protected time: what the session is for.
    var description: String?
    var startsAt: Date
    var endsAt: Date
    var fromSuggestion: String?
    var taskId: String?
    var taskDone = false
    var hasAgenda = false
    var hasRecapDraft = false
    var recapDrafting = false
    var hasRecapPost = false
    var isPending = false

    var isIntention: Bool { fromSuggestion != nil || taskId != nil }

    /// A recap waiting to be read and posted, or one drafting itself.
    var recapWaiting: Bool { !hasRecapPost && (hasRecapDraft || recapDrafting) }
}

/// What a drag on a block changes: the whole block, or its top or bottom edge.
enum BlockEdge: Sendable {
    case move, start, end
}

struct CalendarGoal: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String
    let color: String
}

/// An open task, for the day strip and (later) the task panel.
struct CalendarTask: Identifiable, Hashable, Sendable {
    let id: String
    let goalId: String
    var title: String
    var minutes: Int
    var plannedFor: String?
    var dueOn: String?
}

struct CalendarData: Hashable, Sendable {
    var blocks: [CalendarBlock]
    var goals: [CalendarGoal]
    var tasks: [CalendarTask]
    var sleepStart: Int
    var wakeTime: Int
    var clock: Clock?
    var objectives: [WeekObjective]

    struct WeekObjective: Hashable, Sendable {
        let goalId: String
        let weekStart: String
        let objective: String
    }

    func goal(_ id: String) -> CalendarGoal? { goals.first { $0.id == id } }
}

// MARK: - A day

enum CalendarDayMath {
    static let dayMinutes = 24 * 60
    /// Blocks snap to quarter hours and are at least this long (BLOCK_STEP).
    static let step = 15

    static func snapDown(_ minutes: Int) -> Int { Int((Double(minutes) / Double(step)).rounded(.down)) * step }
    static func snapUp(_ minutes: Int) -> Int { Int((Double(minutes) / Double(step)).rounded(.up)) * step }

    /// The parts of any day spent asleep, e.g. 00:00–08:00 and 23:30–24:00.
    static func sleepSpans(sleepStart: Int, wakeTime: Int) -> [ClosedRange<Int>] {
        if sleepStart == wakeTime { return [] }
        if sleepStart < wakeTime { return [sleepStart...wakeTime] }
        return [0...wakeTime, sleepStart...dayMinutes].filter { $0.upperBound > $0.lowerBound }
    }

    /// Midnight starting the day `offset` days from `base`'s day, in this Mac's time zone.
    static func midnight(_ offset: Int, from base: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base)) ?? base
    }

    /// Minutes from local midnight.
    static func minutes(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Days from `base`'s day to `date`'s day.
    static func dayOffset(_ date: Date, from base: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: base), to: calendar.startOfDay(for: date)).day ?? 0
    }
}

/// A block, or the part of one, on a given day.
struct DaySegment: Identifiable, Hashable, Sendable {
    var id: String { "\(blockId):\(day)" }
    let blockId: String
    /// Days from today.
    let day: Int
    let start: Int
    let end: Int

    /// A block cut into its parts on each day it touches (blocks rarely cross midnight).
    static func of(_ block: CalendarBlock, today: Date) -> [DaySegment] {
        let d0 = CalendarDayMath.dayOffset(block.startsAt, from: today)
        let d1 = CalendarDayMath.dayOffset(block.endsAt, from: today)
        let start = CalendarDayMath.minutes(block.startsAt)
        let end = CalendarDayMath.minutes(block.endsAt)
        if d0 == d1 { return [DaySegment(blockId: block.id, day: d0, start: start, end: end)] }
        var parts = [DaySegment(blockId: block.id, day: d0, start: start, end: CalendarDayMath.dayMinutes)]
        if d1 - d0 > 1 {
            for day in (d0 + 1)..<d1 { parts.append(DaySegment(blockId: block.id, day: day, start: 0, end: CalendarDayMath.dayMinutes)) }
        }
        if end > 0 { parts.append(DaySegment(blockId: block.id, day: d1, start: 0, end: end)) }
        return parts
    }
}

/// A task on a day's strip: planned for that day without a time, or due that day.
struct StripItem: Identifiable, Hashable, Sendable {
    var id: String { task.id }
    let task: CalendarTask
    /// Planned for this day (or, on today, for an earlier day it wasn't done on).
    let planned: Bool
    /// On today: the earlier day it was planned for and missed.
    let carriedFrom: String?
    enum Due: Hashable, Sendable { case due, overdue }
    let due: Due?
}

extension CalendarData {
    /// A day's strip: tasks meant for that day without a time on it, and tasks due then. On today,
    /// plans missed on earlier days and overdue tasks carry over. As stripFor in day-calendar.tsx.
    func strip(day: Int, today: Date) -> [StripItem] {
        let dayISO = CalendarDay.today(CalendarDayMath.midnight(day, from: today))
        let todayISO = CalendarDay.today(today)
        let onToday = day == 0
        let timedHere = Set(blocks.filter { $0.taskId != nil && CalendarDayMath.dayOffset($0.startsAt, from: today) == day }.compactMap(\.taskId))
        var items: [StripItem] = []
        for task in tasks where !timedHere.contains(task.id) {
            let carriedFrom = onToday && (task.plannedFor.map { $0 < todayISO } ?? false) ? task.plannedFor : nil
            let planned = task.plannedFor == dayISO || carriedFrom != nil
            let due: StripItem.Due? = task.dueOn == dayISO ? .due : onToday && (task.dueOn.map { $0 < todayISO } ?? false) ? .overdue : nil
            if planned || due != nil { items.append(StripItem(task: task, planned: planned, carriedFrom: carriedFrom, due: due)) }
        }
        // What you meant to do first, then what's only due.
        return items.enumerated().sorted { a, b in
            a.element.planned != b.element.planned ? a.element.planned : a.offset < b.offset
        }.map(\.element)
    }
}

extension Clock {
    /// Hour-row label: "14:00" or "2 PM".
    func formatHour(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        if self == .twentyFourHour { return String(format: "%02d:00", h) }
        return "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")"
    }
}
