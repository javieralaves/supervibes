import Foundation

/*
 * Route 1's guided week (the design's "Your week · Full screen, guided"): the week ahead, full window, with the plate
 * beside it. First what's already booked: any event from the person's Google calendars can be said to be time for a
 * project or practice (it's imported as that one's blocks, a session or reserved), time to fill (faded back, kept on
 * this Mac), or just an event. Then projects are dragged in, then practices, each explained where it first comes up.
 */

/// What first run's week shows, so it can be drawn from fixtures.
struct WeekPlan: Hashable, Sendable {
    /// Where the guide is: the calendar first, then projects, then practices.
    enum Stage: Int, Hashable, Sendable { case calendar, projects, practices, done }

    /// Whether the person's calendar can be shown.
    enum CalendarState: Hashable, Sendable {
        case ready
        /// Never asked for access to Calendar on this Mac.
        case notAsked
        /// Access refused; only System Settings can change it.
        case denied
        /// Access given, but reading events is turned off in Settings.
        case off
    }

    /// Midnight on the week's Monday.
    var monday: Date
    /// Events in the week not imported, from the person's Google calendars.
    var events: [ExternalEvent]
    /// Blocks in the week, imported events among them.
    var blocks: [CalendarBlock]
    var goals: [CalendarGoal]
    /// Series said to be time to fill.
    var open: Set<String> = []
    var stage: Stage = .calendar
    var calendar: CalendarState = .ready
    /// Route 2's quests, first on the plate; none in Route 1.
    var quests: [WeekQuest] = []
    /// What waits for next season, left off the plate.
    var waiting: Set<String> = []
    /// The route's row of steps; the week is its last.
    var steps: [String] = FirstRunChoice.week.steps

    /// The seven days, Monday first.
    var days: [Date] { (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: monday) ?? monday } }

    /// "Nov 30 – Dec 6".
    var label: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
        return "\(monday.formatted(.dateTime.month(.abbreviated).day().locale(Self.locale))) – \(end.formatted(.dateTime.month(.abbreviated).day().locale(Self.locale)))"
    }

    static let locale = Locale(identifier: "en_US")

    /// The day of the week (0 is Monday) a moment falls on, or nil outside the week.
    func dayIndex(_ date: Date) -> Int? {
        let day = Calendar.current.dateComponents([.day], from: monday, to: Calendar.current.startOfDay(for: date)).day ?? -1
        return (0..<7).contains(day) ? day : nil
    }

    /// An event's series: every occurrence shares its key up to the "|" (see EventKey).
    static func series(_ key: String) -> String {
        key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? key
    }

    func isOpen(_ event: ExternalEvent) -> Bool { open.contains(Self.series(event.key)) }

    func goal(_ id: String) -> CalendarGoal? { goals.first { $0.id == id } }

    /// What can be given time this week: everything but what waits for next season.
    var activeGoals: [CalendarGoal] { goals.filter { !waiting.contains($0.id) } }
    var projects: [CalendarGoal] { activeGoals.filter { !$0.isPractice } }
    var practices: [CalendarGoal] { activeGoals.filter(\.isPractice) }

    /// The quest a project or practice moves.
    func quest(for goalId: String) -> WeekQuest? { quests.first { $0.goalIds.contains(goalId) } }

    /// A quest's time this week: what moves it, as one project's hours or one practice's count, or all of it added
    /// up in hours.
    func meta(_ quest: WeekQuest) -> String {
        let moving = quest.goalIds.compactMap(goal)
        if moving.count == 1 { return meta(moving[0]) }
        return Self.hours(moving.reduce(0) { $0 + minutes(for: $1.id) })
    }

    /// A project's hours or a practice's count this week: "3h 30m", "2 of 3 this week".
    func meta(_ goal: CalendarGoal) -> String {
        goal.isPractice ? "\(count(for: goal.id)) of \(goal.perWeek ?? 1) this week" : Self.hours(minutes(for: goal.id))
    }

    /// A project's minutes this week, sessions and reserved alike.
    func minutes(for goalId: String) -> Int {
        blocks.filter { $0.goalId == goalId }.reduce(0) { $0 + Int($1.endsAt.timeIntervalSince($1.startsAt) / 60) }
    }

    /// A practice's blocks this week.
    func count(for goalId: String) -> Int { blocks.filter { $0.goalId == goalId && !$0.missed }.count }

    /// Which of the week's times a practice's block is: 1 for the first.
    func ordinal(of block: CalendarBlock) -> Int {
        (blocks.filter { $0.goalId == block.goalId && !$0.missed }.sorted { $0.startsAt < $1.startsAt }.firstIndex { $0.id == block.id } ?? 0) + 1
    }

    /// Everything else of the same series in the week, events and imported blocks alike, for "Every Tue and Thu".
    func when(_ title: String, start: Date, end: Date, key: String, repeats: Bool) -> String {
        let hours = "\(Self.clock(start))–\(Self.clock(end))"
        guard repeats else { return "\(start.formatted(.dateTime.weekday(.abbreviated).day().locale(Self.locale))), \(hours)" }
        let series = Self.series(key)
        let starts = events.filter { Self.series($0.key) == series }.map(\.start)
            + blocks.compactMap { $0.source.flatMap { Self.series($0.key) == series ? $0.snapshot.startsAt : nil } }
        let weekdays = Array(Set(starts.compactMap(dayIndex))).sorted()
        let names = weekdays.map { days[$0].formatted(.dateTime.weekday(weekdays.count == 1 ? .wide : .abbreviated).locale(Self.locale)) }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last! : names.first ?? ""
        return "Every \(list), \(hours)"
    }

    static func clock(_ date: Date) -> String {
        let minutes = CalendarDayMath.minutes(date)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "6h", "3h 30m", or "No time yet".
    static func hours(_ minutes: Int) -> String {
        guard minutes > 0 else { return "No time yet" }
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// The Monday of the week to plan: this one early in the week, the next one from Wednesday on.
    static func weekToPlan(from now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // Sunday is 1
        let sinceMonday = (weekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -sinceMonday, to: today) ?? today
        return sinceMonday <= 1 ? thisMonday : calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday
    }
}

/// What's open on the week: an event's question, a block's, or a block just dropped (found by its goal and start,
/// since its id changes once it's saved).
enum WeekSelection: Hashable, Sendable {
    case event(String)
    case block(String)
    case placed(goalId: String, startsAt: Date)
}
