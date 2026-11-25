import Foundation

/// A goal as the home page shows it (src/lib/goals.ts plus its status trail).
struct Goal: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String?
    /// A calendar day, "YYYY-MM-DD".
    var targetDate: String?
    /// A Hugeicons name from GoalPalette, e.g. "Rocket01Icon".
    var icon: String
    /// A key from GoalPalette, e.g. "violet".
    var color: String
    /// The last 28 days, oldest first.
    var trajectory: [TrajectoryDay]
    /// The area it sits in, if any.
    var areaId: String? = nil
    /// When it last moved: its latest progress read or note, or when it was made. Nil until the server says.
    var updatedAt: Date? = nil
    /// Saving; shown faded until the server has it.
    var isPending = false

    /// Its latest status: the last day's, which carries the most recent read.
    var latest: TrajectoryDay? { trajectory.last }
}

/// A goal's week, as its card on Goals home shows it (GoalWeek in src/lib/api/routes/goals.ts):
/// this week's objective, and what's planned against the goal's session time, with the same
/// totals as the planning board's This week ring.
struct GoalWeek: Hashable, Sendable {
    var objective: String?
    /// Session time this week, gone by or not: room for tasks.
    var sessionMinutes: Int
    /// Reserved time this week, kept for its own sake: no room for tasks.
    var reservedMinutes: Int
    /// Open estimates meant for this week, plus the session time already gone by.
    var plannedMinutes: Int

    /// What's left of the session time once what's planned is taken out; below zero when over.
    var remaining: Int { sessionMinutes - plannedMinutes }
}

/// What a goal's status was on one day (src/lib/status-schema.ts).
struct TrajectoryDay: Hashable, Sendable {
    /// "YYYY-MM-DD", in the person's own calendar.
    let day: String
    let status: GoalStatus?
    let basis: StatusBasis?
    let reason: String?
    /// No read that day: the status shown is the one before it.
    let carried: Bool
}

enum GoalStatus: String, Hashable, Sendable {
    case onTrack = "on_track"
    case atRisk = "at_risk"
    case offTrack = "off_track"
    case unclear
}

enum StatusBasis: String, Hashable, Sendable {
    case target, week, momentum
}

/// "On track", or for a goal judged on momentum, "Moving".
func statusLabel(_ status: GoalStatus, _ basis: StatusBasis) -> String {
    switch (status, basis) {
    case (.unclear, _): "Too early to tell"
    case (.onTrack, .momentum): "Moving"
    case (.atRisk, .momentum): "Slowing"
    case (.offTrack, .momentum): "Stalled"
    case (.onTrack, _): "On track"
    case (.atRisk, _): "At risk"
    case (.offTrack, _): "Off track"
    }
}

/// What a new goal starts as, from the dialog (src/lib/goal-schema.ts).
extension GoalInput {
    /// A goal as it is, for its edit dialog.
    init(editing goal: Goal) {
        self.init(
            title: goal.title,
            description: goal.description ?? "",
            targetDate: goal.targetDate,
            icon: GoalPalette.iconName(goal.icon),
            color: GoalPalette.colorInfo(goal.color).key,
            areaId: goal.areaId
        )
    }
}

struct GoalInput: Hashable, Sendable {
    var title = ""
    var description = ""
    /// "YYYY-MM-DD", or nil.
    var targetDate: String?
    var icon = GoalPalette.defaultIcon
    var color = GoalPalette.defaultColor
    /// The area it sits in, if any. Set separately from the rest when editing (PUT /goals/{id}/area).
    var areaId: String?

    static let maxTitle = 120
    static let maxDescription = 1000

    /// The web dialog's checks, so the same messages show before anything is sent.
    var problem: String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Give your goal a name." }
        if title.count > Self.maxTitle { return "Keep it under \(Self.maxTitle) characters." }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxDescription {
            return "Keep the description under \(Self.maxDescription) characters."
        }
        return nil
    }
}

// MARK: - Calendar days

/// Calendar days ("YYYY-MM-DD") with no time zone, as in src/lib/target-date.ts.
enum CalendarDay {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func utcWeekday(_ date: Date) -> Int { utc.component(.weekday, from: date) }

    static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func string(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Today on this Mac, "YYYY-MM-DD".
    static func today(_ now: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whole days from `today` to `target`; negative once it has passed.
    static func daysUntil(_ target: String, today: String) -> Int {
        guard let a = date(today), let b = date(target) else { return 0 }
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    /// "Mar 31", or "Mar 31, 2027" when it isn't this year.
    static func format(_ target: String, today: String) -> String {
        guard let date = date(target) else { return target }
        var style = Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
            .month(.abbreviated).day()
        if target.prefix(4) != today.prefix(4) { style = style.year() }
        return date.formatted(style)
    }

    private static func span(_ days: Int) -> String {
        if days < 14 { return "\(days) day\(days == 1 ? "" : "s")" }
        if days < 60 { return "\(Int((Double(days) / 7).rounded())) weeks" }
        let months = Int((Double(days) / 30.44).rounded())
        return months < 24 ? "\(months) months" : "\(Int((Double(days) / 365.25).rounded())) years"
    }

    /// "today", "tomorrow", "in 3 weeks", "2 days past".
    static func relative(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "tomorrow"
        case -1: "yesterday"
        default: days > 0 ? "in \(span(days))" : "\(span(-days)) past"
        }
    }

    /// "today", "tomorrow", "5 d", "4 wk", "3 mo", or "2 d past".
    static func shortRelative(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        let n = abs(days)
        let span = n < 14 ? "\(n) d" : n < 60 ? "\(Int((Double(n) / 7).rounded())) wk" : "\(Int((Double(n) / 30.44).rounded())) mo"
        return days > 0 ? span : "\(span) past"
    }
}

// MARK: - A goal's page

/// What a goal's page shows above its tasks (GET /api/v1/goals/{id}).
struct GoalDetail: Hashable, Sendable {
    struct Read: Hashable, Sendable {
        let headline: String
        let summary: String
        /// Provider keys or labels, plus "notes" and "tasks".
        let basedOn: [String]
        let createdAt: Date
    }

    struct Status: Hashable, Sendable {
        let status: GoalStatus
        let basis: StatusBasis
        let reason: String
        let at: Date
    }

    struct Week: Hashable, Sendable {
        /// The Monday it starts on, "YYYY-MM-DD".
        let start: String
        var objective: String?
        let lastWeek: String?
        /// The goal's time on the calendar this week and next, clipped to those weeks, earliest first.
        var protectedBlocks: [ProtectedBlock] = []
        /// Tasks checked off this week, most recently first.
        var done: [TaskItem] = []
    }

    var goal: Goal
    let today: String
    let read: Read?
    let status: Status?
    let readsInTrajectory: Int
    var readPending: Bool
    let readError: String?
    /// There's a source, task or note to read.
    let canRead: Bool
    var week: Week
    /// Open tasks, in their order.
    var tasks: [TaskItem] = []
    /// The latest read's suggestions still to handle.
    var suggestions: [TaskSuggestion] = []
    /// The person's clock; nil follows this Mac.
    var clock: Clock? = nil
    /// The activity, newest first.
    var notes: [NoteItem] = []
    var author = NoteAuthor(name: "", imageURL: nil)
    var sources: [SourceItem] = []
    /// Connected apps a new source can read from.
    var connectionOptions: [ConnectionOption] = []
    /// The area it sits in, to show under its title and link to; nil when none.
    var area: AreaRef? = nil
}

extension CalendarDay {
    static func addDays(_ day: String, _ n: Int) -> String {
        guard let date = date(day) else { return day }
        return string(date.addingTimeInterval(Double(n) * 86_400))
    }

    /// The Monday that starts the week `day` falls in. Weeks run Monday to Sunday.
    static func weekStart(_ day: String) -> String {
        guard let date = date(day) else { return day }
        let weekday = utcWeekday(date) // 1 is Sunday
        return addDays(day, -((weekday + 5) % 7))
    }

    /// "Nov 16–22", or "Nov 30 – Dec 6" across months, for the week starting `weekStart`.
    static func formatWeek(_ weekStart: String) -> String {
        formatRange(weekStart, days: 7)
    }

    /// "Nov 18–20", or "Nov 30 – Dec 2" across months, for `days` days from `first`.
    static func formatRange(_ first: String, days: Int) -> String {
        guard let start = date(first) else { return first }
        let end = start.addingTimeInterval(Double(max(days, 1) - 1) * 86_400)
        let month = Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated)
        let day = { (d: Date) in Int(string(d).suffix(2)) ?? 0 }
        let (m1, m2) = (start.formatted(month), end.formatted(month))
        return m1 == m2 ? "\(m1) \(day(start))–\(day(end))" : "\(m1) \(day(start)) – \(m2) \(day(end))"
    }

    /// "Today", "Tomorrow", "Yesterday", "Fri" within a week either way, otherwise "Nov 28".
    static func relativeLabel(_ day: String, today: String) -> String {
        let days = daysUntil(day, today: today)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            if abs(days) < 7, let date = date(day) {
                return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated))
            }
            return format(day, today: today)
        }
    }
}

extension Date {
    /// "just now", "3 min ago", "2 hr ago", "4 days ago", like src/lib/time.ts.
    func shortAgo(now: Date = Date()) -> String {
        let minutes = max(0, Int((now.timeIntervalSince(self) / 60).rounded()))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return "\(hours) hr ago" }
        let days = Int((Double(hours) / 24).rounded())
        return "\(days) \(days == 1 ? "day" : "days") ago"
    }
}

// MARK: - Tasks

/// A goal's task (src/lib/tasks.ts), as the Tasks section shows it.
struct TaskItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String?
    /// The estimate: 15, 30, 60 or 120.
    var minutes: Int
    var done = false
    /// The day they mean to do it, "YYYY-MM-DD".
    var plannedFor: String?
    /// The Monday of the week they mean to do it; a planned day sets its week. Nil with no day: Later.
    var plannedWeek: String?
    /// The day it's due, "YYYY-MM-DD".
    var dueOn: String?
    /// When it's next on the calendar, if it is.
    var scheduledAt: Date?
    /// Saving; shown faded until the server has it.
    var isPending = false

    static let estimates = [15, 30, 60, 120]
    static let defaultMinutes = 30
    static let maxTitle = 200
    static let maxDescription = 2000

    /// "30 min", "1 hr", "2 hr".
    static func minutesLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        // As JavaScript prints minutes / 60: "1 hr", "1.5 hr", "1.25 hr".
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours)) hr" : "\(hours.formatted(.number.precision(.fractionLength(0...4)).locale(Locale(identifier: "en_US")))) hr"
    }

    /// The description's first line with something on it, for the closed row.
    var firstLine: String? {
        description?.split(separator: "\n").map(String.init).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// A change to a task. Only set fields are sent; an empty string clears a day or the description.
struct TaskPatch: Hashable, Sendable {
    var title: String?
    var description: String?
    var minutes: Int?
    var plannedFor: String?
    /// Any day of the week; empty moves it to Later.
    var plannedWeek: String?
    var dueOn: String?
}

/// Where an open task stands in the plan, as src/lib/task-horizon.ts works it out from its day and week.
struct TaskHorizon: Hashable, Sendable {
    enum Group: CaseIterable, Hashable, Sendable {
        case day, thisWeek, nextWeek, later
    }

    let group: Group
    /// Planned for a day that's gone by without it being done.
    var slipped = false
    /// Weeks it has carried over from the week it was planned for.
    var carriedWeeks = 0
}

extension TaskItem {
    /// Where it stands today: a missed day falls back to its week; a past week carries into this one.
    func horizon(today: String) -> TaskHorizon {
        if let day = plannedFor, day >= today { return TaskHorizon(group: .day) }
        let thisWeek = CalendarDay.weekStart(today)
        let week = plannedWeek ?? plannedFor.map(CalendarDay.weekStart)
        if let week, week <= thisWeek {
            return TaskHorizon(group: .thisWeek, slipped: plannedFor != nil, carriedWeeks: CalendarDay.daysUntil(thisWeek, today: week) / 7)
        }
        if week == CalendarDay.addDays(thisWeek, 7) { return TaskHorizon(group: .nextWeek) }
        return TaskHorizon(group: .later)
    }

    /// With a planned day or week changed as the server does it (resolvePlacement): a day sets its
    /// week; clearing the day keeps the week (Later if it's past next week); another week drops a
    /// day outside it; clearing the week moves it to Later. An empty string clears.
    func placed(plannedFor newDay: String?, plannedWeek newWeek: String?, today: String) -> TaskItem {
        var task = self
        if let day = newDay, !day.isEmpty {
            task.plannedFor = day
            task.plannedWeek = CalendarDay.weekStart(day)
            return task
        }
        // nil: leave the week; .some(nil): clear it; .some(day): that day's week.
        let week: String?? = newWeek.map { $0.isEmpty ? nil : CalendarDay.weekStart($0) }
        if newDay != nil {
            let kept: String? = if let week { week } else { plannedWeek ?? plannedFor.map(CalendarDay.weekStart) }
            task.plannedFor = nil
            task.plannedWeek = kept.flatMap { $0 <= CalendarDay.addDays(CalendarDay.weekStart(today), 7) ? $0 : nil }
            return task
        }
        guard let week else { return task }
        guard let week else {
            task.plannedFor = nil
            task.plannedWeek = nil
            return task
        }
        if let day = plannedFor, CalendarDay.weekStart(day) != week { task.plannedFor = nil }
        task.plannedWeek = week
        return task
    }
}

/// Something the latest read suggests doing next.
struct TaskSuggestion: Hashable, Sendable {
    let title: String
    let why: String
    let minutes: Int
}

// MARK: - Activity

/// An entry in a goal's activity (src/lib/posts.ts): a note, a recap, or a finished task or suggestion.
struct NoteItem: Identifiable, Hashable, Sendable {
    struct Session: Hashable, Sendable {
        let title: String
        let startsAt: Date
        let endsAt: Date
        /// What the person wanted out of the session, if they said.
        let aim: String?
    }

    struct Breadcrumb: Hashable, Sendable {
        let provider: ConnectionItem.Provider
        let title: String
        let url: URL
    }

    let id: String
    var body: String
    /// Posted by finishing a suggestion: its title.
    var completedSuggestion: String?
    /// Posted by checking a task off: its title.
    var completedTask: String?
    /// That task, while it still exists, so it can be reopened from here.
    var taskId: String?
    var taskDescription: String?
    /// The calendar session it recaps, on recaps.
    var session: Session?
    var breadcrumbs: [Breadcrumb] = []
    let createdAt: Date
    var updatedAt: Date
    /// Posting; shown faded until the server has it.
    var isPending = false

    static let maxBody = 2000

    /// Changed more than a second after it was posted.
    var isEdited: Bool { updatedAt.timeIntervalSince(createdAt) > 1 }
}

/// Who the activity is by.
struct NoteAuthor: Hashable, Sendable {
    let name: String
    let imageURL: URL?
}

extension Clock {
    /// "14:30–15:30", "2:30–3:30 PM" or "11:30 AM–12:30 PM", like the web's formatRange.
    func formatRange(_ start: Int, _ end: Int) -> String {
        guard self == .twelveHour else { return "\(format(minutes: start))–\(format(minutes: end))" }
        let samePeriod = (start % 1440 < 720) == (end % 1440 < 720)
        if samePeriod {
            let h = (start % 1440) / 60, m = start % 60
            return "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m))–\(format(minutes: end))"
        }
        return "\(format(minutes: start))–\(format(minutes: end))"
    }
}

// MARK: - Sources

/// A connected app a goal's reads look at, and how it relates in the person's words.
struct SourceItem: Identifiable, Hashable, Sendable {
    let id: String
    let connectionId: String
    let provider: ConnectionItem.Provider
    var relation: String
    var lastError: String?

    static let minRelation = 10
    static let maxRelation = 1500

    /// The web's checks, so the same message shows before anything is sent.
    static func problem(_ relation: String) -> String? {
        let trimmed = relation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minRelation { return "Say where to look and how it relates to this goal." }
        if trimmed.count > maxRelation { return "Keep it under 1,500 characters." }
        return nil
    }
}

/// A connected app a new source can read from.
struct ConnectionOption: Identifiable, Hashable, Sendable {
    let id: String
    let provider: ConnectionItem.Provider
    let label: String
    /// An example relation, for the dialog's placeholder.
    let relationHint: String
}
