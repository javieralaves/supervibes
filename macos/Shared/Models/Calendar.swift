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
    /// A plan for the session, once one has been prepared.
    var agenda: BlockAgenda?
    /// A draft recap, waiting to be posted or discarded.
    var recap: RecapDraft?
    /// The recap as posted to the goal's activity.
    var recapPost: PostedRecap?
    var isPending = false

    var isIntention: Bool { fromSuggestion != nil || taskId != nil }

    /// A recap waiting to be read and posted, or one drafting itself.
    var recapWaiting: Bool { !hasRecapPost && (hasRecapDraft || recapDrafting) }
}

/// What a drag on a block changes: the whole block, or its top or bottom edge.
enum BlockEdge: Sendable {
    case move, start, end
}

/// A block's prepared plan: a paragraph, the tasks it draws on (a snapshot), and when it was made.
/// An aim suggested for a session that doesn't say what it's for yet, and why it's the one.
/// Only a suggestion: it becomes the session's aim if the person takes it.
struct FocusSuggestion: Hashable, Sendable {
    let aim: String
    let why: String
}

/// How asking for a focus went: a suggestion, or a message to show.
enum FocusOutcome: Sendable {
    case suggested(FocusSuggestion)
    case failed(String)
}

struct BlockAgenda: Hashable, Sendable {
    struct Task: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let minutes: Int
    }

    let text: String
    let tasks: [Task]
    let preparedAt: Date
    /// The block's title and aim when it was prepared; older agendas didn't keep the title.
    let keptTitle: Bool
    let title: String?
    let description: String?

    /// Whether the title or aim has changed since it was prepared (agendaIsStale).
    func isStale(title current: String?, description currentDescription: String?) -> Bool {
        (keptTitle && title != current) || description != currentDescription
    }
}

/// A draft recap: what was meant to happen, what did, and the links it found.
struct RecapDraft: Hashable, Sendable {
    enum Found: String, Sendable { case clear, partial, none, noSources = "no-sources" }

    let planned: String?
    let happened: String
    let breadcrumbs: [NoteItem.Breadcrumb]
    let found: Found
    /// For an intention: whether its task looks finished.
    let taskLooksDone: Bool
    let preparedAt: Date
    /// Drafted on its own once the session ended.
    let auto: Bool
}

struct PostedRecap: Hashable, Sendable {
    let body: String
    let breadcrumbs: [NoteItem.Breadcrumb]
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

    /// The Monday of the week holding the day `offset` days from `base`'s, in days from `base`'s day.
    static func monday(of offset: Int, from base: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: midnight(offset, from: base, calendar: calendar))
        // Sunday is 1: Monday-first, it's the week's seventh day.
        return offset - (weekday + 5) % 7
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

extension CalendarData {
    /// Each goal's time in the week starting `monday` days from today: all of it, and how much has
    /// happened, in minutes (weekTotals).
    func weekTotals(monday: Int, now: Date) -> [String: (planned: Double, done: Double)] {
        var totals: [String: (planned: Double, done: Double)] = [:]
        for block in blocks {
            for segment in DaySegment.of(block, today: now) where segment.day >= monday && segment.day <= monday + 6 {
                let midnight = CalendarDayMath.midnight(segment.day, from: now)
                let from = midnight.addingTimeInterval(Double(segment.start) * 60)
                let to = midnight.addingTimeInterval(Double(segment.end) * 60)
                let elapsed = to > from ? min(max(now.timeIntervalSince(from) / to.timeIntervalSince(from), 0), 1) : 0
                let minutes = Double(segment.end - segment.start)
                var total = totals[block.goalId] ?? (0, 0)
                total.planned += minutes
                total.done += minutes * elapsed
                totals[block.goalId] = total
            }
        }
        return totals
    }

    /// Each goal's objective for the week starting on `weekStart`.
    func objectives(weekStart: String) -> [String: String] {
        Dictionary(objectives.filter { $0.weekStart == weekStart }.map { ($0.goalId, $0.objective) }, uniquingKeysWith: { a, _ in a })
    }
}

/// "45m", "2h", "2h 30m".
func durationLabel(_ minutes: Double) -> String {
    let h = Int(minutes / 60)
    let m = Int((minutes.truncatingRemainder(dividingBy: 60)).rounded())
    return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

/// An open task as the task panel lists it, with its next block that hasn't ended: dragging the
/// task moves that block rather than adding another.
struct PanelTask: Identifiable, Hashable, Sendable {
    let task: CalendarTask
    let block: CalendarBlock?
    var id: String { task.id }

    /// How long it lands when dropped on a day: its block's length, else its estimate.
    var minutes: Int {
        guard let block else { return task.minutes }
        return min(CalendarDayMath.dayMinutes, Int((block.endsAt.timeIntervalSince(block.startsAt) / 60).rounded()))
    }

    var isPending: Bool { block?.isPending ?? false }
}

/// A goal's open tasks in the panel.
struct PanelGroup: Identifiable, Hashable, Sendable {
    let goal: CalendarGoal
    let tasks: [PanelTask]
    var id: String { goal.id }
}

extension CalendarData {
    /// Each open task's next block that hasn't ended.
    func nextBlocks(now: Date) -> [String: CalendarBlock] {
        var next: [String: CalendarBlock] = [:]
        for block in blocks {
            guard let taskId = block.taskId, block.endsAt > now else { continue }
            if let seen = next[taskId], seen.startsAt <= block.startsAt { continue }
            next[taskId] = block
        }
        return next
    }

    func panelTask(_ taskId: String, now: Date) -> PanelTask? {
        tasks.first { $0.id == taskId }.map { PanelTask(task: $0, block: nextBlocks(now: now)[taskId]) }
    }

    /// The panel: each goal's open tasks in your order. Those planned for the shown day come first,
    /// ready to drag in; those already on the calendar last.
    func panelGroups(day: Int, now: Date) -> [PanelGroup] {
        let next = nextBlocks(now: now)
        let shown = CalendarDay.today(CalendarDayMath.midnight(day, from: now))
        func rank(_ t: PanelTask) -> Int { t.block != nil ? 2 : t.task.plannedFor == shown ? 0 : 1 }
        return goals.compactMap { goal in
            let mine = tasks.filter { $0.goalId == goal.id }.map { PanelTask(task: $0, block: next[$0.id]) }
            guard !mine.isEmpty else { return nil }
            let sorted = mine.enumerated().sorted { a, b in
                rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
            }.map(\.element)
            return PanelGroup(goal: goal, tasks: sorted)
        }
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
