import Foundation

/// Route 1's week as Alex plans it: Mon Nov 30 to Sun Dec 6, 2026, with the calendar from the First run page in
/// supervibes-design (standups, reviews, a birthday; runs, Deep work holds and a dentist made by Alex).
extension Fixtures {
    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30)) ?? .now
        let date = calendar.date(byAdding: .day, value: day, to: monday) ?? monday
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    private static func event(_ key: String, _ title: String, _ day: Int, _ from: (Int, Int), _ to: (Int, Int), repeats: Bool = false) -> ExternalEvent {
        ExternalEvent(
            key: repeats ? "\(key)|\(day)" : key, calendarId: "work", calendarName: "Work", title: title,
            start: at(day, from.0, from.1), end: at(day, to.0, to.1), repeats: repeats
        )
    }

    static let weekEvents: [ExternalEvent] = (0..<5).map { event("standup", "Standup", $0, (9, 30), (10, 0), repeats: true) } + [
        event("review", "Product review", 0, (14, 0), (15, 30), repeats: true),
        event("one-on-ones", "1:1s", 1, (10, 0), (12, 0)),
        event("all-hands", "All hands", 2, (12, 0), (13, 0)),
        event("planning", "Quarterly planning", 3, (10, 0), (12, 30)),
        event("lunch", "Team lunch", 4, (12, 30), (14, 0)),
        event("birthday", "Marta’s birthday", 5, (13, 0), (16, 0)),
        event("call-home", "Call home", 6, (17, 30), (18, 30)),
        event("run", "Run", 1, (18, 0), (19, 0), repeats: true),
        event("run", "Run", 3, (18, 0), (19, 0), repeats: true),
        event("deep-work", "Deep work", 0, (10, 0), (12, 0), repeats: true),
        event("deep-work", "Deep work", 2, (10, 0), (12, 0), repeats: true),
        event("deep-work", "Deep work", 4, (10, 0), (12, 0), repeats: true),
        event("dentist", "Dentist", 4, (16, 0), (17, 0)),
    ]

    static let weekGoals: [CalendarGoal] = [
        CalendarGoal(id: "pricing", title: "Ship the new pricing page", icon: "Rocket01Icon", color: "violet"),
        CalendarGoal(id: "hire", title: "Hire a product designer", icon: "UserGroupIcon", color: "sky"),
        CalendarGoal(id: "move", title: "Move flats by January", icon: "Sofa01Icon", color: "amber"),
        CalendarGoal(id: "taxes", title: "Sort out this year’s taxes", icon: "Money03Icon", color: "slate"),
        CalendarGoal(id: "newsletter", title: "Start a newsletter", icon: "PenTool01Icon", color: "pink"),
        CalendarGoal(id: "lisbon", title: "Plan the Lisbon trip", icon: "Airplane01Icon", color: "teal"),
        CalendarGoal(id: "run", title: "Run", icon: "RunningShoesIcon", color: "green", kind: .practice, perWeek: 3),
        CalendarGoal(id: "spanish", title: "Spanish", icon: "LanguageSkillIcon", color: "indigo", kind: .practice, perWeek: 3),
    ]

    private static func block(_ id: String, _ goalId: String, _ day: Int, _ from: (Int, Int), _ to: (Int, Int), reserved: Bool = false, from event: ExternalEvent? = nil) -> CalendarBlock {
        var block = CalendarBlock(id: id, goalId: goalId, title: nil, startsAt: at(day, from.0, from.1), endsAt: at(day, to.0, to.1))
        block.reserved = reserved
        block.source = event.map { EventSource(key: $0.key, calendar: $0.calendarName, snapshot: $0.snapshot) }
        return block
    }

    /// The week with the calendar answered: the product review as reserved time for the pricing page, the runs as
    /// Run, Deep work as time to fill.
    static func weekAnswered(stage: WeekPlan.Stage = .projects, blocks extra: [CalendarBlock] = []) -> WeekPlan {
        let review = weekEvents.first { $0.title == "Product review" }!
        let runs = weekEvents.filter { $0.title == "Run" }
        var plan = WeekPlan(
            monday: at(0, 0),
            events: weekEvents.filter { $0.title != "Product review" && $0.title != "Run" },
            blocks: [block("review", "pricing", 0, (14, 0), (15, 30), reserved: true, from: review)]
                + runs.enumerated().map { index, run in block("run-\(index)", "run", index == 0 ? 1 : 3, (18, 0), (19, 0), from: run) }
                + extra,
            goals: weekGoals
        )
        plan.open = ["deep-work"]
        plan.stage = stage
        return plan
    }

    static let weekStart = WeekPlan(monday: at(0, 0), events: weekEvents, blocks: [], goals: weekGoals)

    static let weekPricingSession = block("pricing-1", "pricing", 0, (10, 0), (12, 0))
    static let weekSpanish = block("spanish-1", "spanish", 6, (10, 0), (11, 0))

    static let weekPlanned: WeekPlan = weekAnswered(stage: .done, blocks: [
        weekPricingSession,
        block("hire-1", "hire", 0, (16, 0), (17, 30)),
        block("pricing-2", "pricing", 1, (13, 0), (15, 30)),
        block("move-1", "move", 2, (14, 0), (16, 0)),
        block("spanish-0", "spanish", 2, (18, 30), (19, 30)),
        block("taxes-1", "taxes", 3, (14, 0), (15, 30)),
        block("move-2", "move", 5, (10, 15), (12, 30), reserved: true),
        weekSpanish,
    ])
}
