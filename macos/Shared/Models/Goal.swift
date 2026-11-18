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
    /// Saving; shown faded until the server has it.
    var isPending = false

    /// Its latest status: the last day's, which carries the most recent read.
    var latest: TrajectoryDay? { trajectory.last }
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
struct GoalInput: Hashable, Sendable {
    var title = ""
    var description = ""
    /// "YYYY-MM-DD", or nil.
    var targetDate: String?
    var icon = GoalPalette.defaultIcon
    var color = GoalPalette.defaultColor

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
}

extension CalendarDay {
    /// "Nov 16–22", or "Nov 30 – Dec 6" across months, for the week starting `weekStart`.
    static func formatWeek(_ weekStart: String) -> String {
        guard let start = date(weekStart) else { return weekStart }
        let end = start.addingTimeInterval(6 * 86_400)
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
        minutes >= 60 ? "\(minutes / 60) hr" : "\(minutes) min"
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
    var dueOn: String?
}

/// Something the latest read suggests doing next.
struct TaskSuggestion: Hashable, Sendable {
    let title: String
    let why: String
    let minutes: Int
}
