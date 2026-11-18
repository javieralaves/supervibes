import Foundation

/// Stand-in data for snapshot tests and the widget (until the widget can share the app's data).
enum Fixtures {
    /// A fixed moment, so snapshot tests render the same image every run.
    static let referenceNow: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        components.year = 2026
        components.month = 11
        components.day = 18
        components.hour = 10
        components.minute = 18
        return components.date!
    }()

    static let sky = Tint(light: "#0a8be0", dark: "#3cb8ff")
    static let pink = Tint(light: "#e6327f", dark: "#ff6fae")

    /// Today's blocks, laid out around `now`: one in progress and two still to come.
    static func blocks(around now: Date) -> [Block] {
        let minute: TimeInterval = 60
        let currentStart = now.addingTimeInterval(-48 * minute)
        let currentEnd = now.addingTimeInterval(42 * minute)
        return [
            Block(id: "current", title: "Scaffold the Mac app", goal: "Ship Supervibes for Mac",
                  start: currentStart, end: currentEnd, tint: sky),
            Block(id: "next", title: "Weekly review", goal: "Run a calm week",
                  start: currentEnd.addingTimeInterval(18 * minute),
                  end: currentEnd.addingTimeInterval(48 * minute), tint: pink),
            Block(id: "later", title: "Write the API sketch", goal: "Ship Supervibes for Mac",
                  start: currentEnd.addingTimeInterval(108 * minute),
                  end: currentEnd.addingTimeInterval(198 * minute), tint: sky),
        ]
    }

    static func current(at now: Date) -> Block? {
        blocks(around: now).first { $0.isHappening(at: now) }
    }

    static func upcoming(at now: Date) -> [Block] {
        blocks(around: now).filter { $0.start > now }
    }

    /// A month of calls to Claude, spread over the days before `referenceNow`.
    static var usageCalls: [UsageCall] {
        let features: [UsageCall.Feature] = [.progressRead, .progressRead, .recap, .agenda, .progressRead, .recap]
        let triggers = ["cron", "note", "auto", "manual", "recap", "draft"]
        let goals = ["Ship Supervibes for Mac", "Run a calm week", "Make time for movement"]
        return (0..<42).map { i in
            let feature = features[i % features.count]
            return UsageCall(
                id: "call-\(i)",
                feature: feature,
                trigger: triggers[i % triggers.count],
                goalTitle: goals[i % goals.count],
                model: "claude-sonnet-5-5",
                inputTokens: 18_000 + (i * 1_731) % 22_000,
                outputTokens: 900 + (i * 377) % 2_400,
                toolCalls: i % 4,
                durationMs: 6_000 + (i * 2_113) % 30_000,
                cost: feature == .agenda ? 0.021 + Double(i % 5) * 0.004 : 0.048 + Double(i % 7) * 0.011,
                createdAt: referenceNow.addingTimeInterval(-Double(i) * 16.5 * 3600)
            )
        }
    }

    static var connections: [ConnectionItem] {
        [
            ConnectionItem(provider: .linear, label: "Linear", description: "Issues, projects and cycles.",
                           configured: true, state: .connected(since: referenceNow.addingTimeInterval(-9 * 86_400))),
            ConnectionItem(provider: .github, label: "GitHub", description: "Commits, pull requests and issues.",
                           configured: true, state: .needsAttention(message: "The token expired.")),
            ConnectionItem(provider: .granola, label: "Granola", description: "Meeting notes and summaries.",
                           configured: true, state: .notConnected),
        ]
    }

    /// Six goals with statuses and trails, ending on Nov 18, 2026.
    static var goals: [Goal] {
        func trail(_ entries: [(Int, GoalStatus, StatusBasis)]) -> [TrajectoryDay] {
            // Days 0...27, oldest first; a status from its day onward, carried between reads.
            var current: (GoalStatus, StatusBasis)?
            return (0..<28).map { index in
                let day = CalendarDay.string(CalendarDay.date("2026-10-22")!.addingTimeInterval(Double(index) * 86_400))
                if let read = entries.first(where: { $0.0 == index }) {
                    current = (read.1, read.2)
                    return TrajectoryDay(day: day, status: read.1, basis: read.2, reason: nil, carried: false)
                }
                return TrajectoryDay(day: day, status: current?.0, basis: current?.1, reason: nil, carried: current != nil)
            }
        }
        return [
            Goal(id: "1", title: "Build Supervibes as a fresh take on productivity", targetDate: "2026-12-18",
                 icon: "Rocket01Icon", color: "sky", trajectory: trail([(14, .unclear, .target), (20, .onTrack, .target), (27, .onTrack, .target)])),
            Goal(id: "2", title: "Build an app that helps Jacob find an apartment in Madrid", targetDate: "2026-11-30",
                 icon: "Megaphone01Icon", color: "teal", trajectory: trail([(18, .onTrack, .target), (27, .atRisk, .target)])),
            Goal(id: "3", title: "Deliver research-backed housing playbook for Madrid", targetDate: "2026-11-12",
                 icon: "Target02Icon", color: "coral", trajectory: trail([(27, .offTrack, .target)])),
            Goal(id: "4", title: "Carve time out for life more broadly", icon: "Plant01Icon", color: "pink",
                 trajectory: trail([(27, .onTrack, .momentum)])),
            Goal(id: "5", title: "Make time for movement & exercise", icon: "RunningShoesIcon", color: "green",
                 trajectory: trail([])),
            Goal(id: "6", title: "Stay engaged with Superfocus and the community", icon: "Briefcase01Icon", color: "indigo",
                 trajectory: trail([(10, .atRisk, .momentum), (27, .onTrack, .momentum)])),
        ]
    }

    /// The first goal's page, with a read, a status and this week's objective.
    static var goalDetail: GoalDetail {
        var goal = goals[0]
        goal.description = "A calmer planner that reads where your work happens and tells you, honestly, whether you’re moving."
        return GoalDetail(
            goal: goal,
            today: "2026-11-18",
            read: .init(
                headline: "Steady progress: the native app is taking shape faster than planned",
                summary: "Three screens moved from web to native this week, and the API now backs each of them. Tasks are moving too; the risk is the calendar, which hasn’t started.",
                basedOn: ["linear", "github", "notes", "tasks"],
                createdAt: referenceNow.addingTimeInterval(-2 * 3600)
            ),
            status: .init(status: .onTrack, basis: .target, reason: "Shipping weekly toward Dec 18.", at: referenceNow),
            readsInTrajectory: 3,
            readPending: false,
            readError: nil,
            canRead: true,
            week: .init(start: "2026-11-16", objective: "Ship the goal page natively.", lastWeek: "Get sign-in working in the Mac app.")
        )
    }

    static let tasks: [TaskItem] = [
        TaskItem(id: "t1", title: "Rebuild the goal page’s tasks natively",
                 description: "Drag to reorder, day pills, suggestions.\nThen notes and sources.",
                 minutes: 120, plannedFor: "2026-11-18", dueOn: "2026-11-19"),
        TaskItem(id: "t2", title: "Write the API sketch for the calendar", minutes: 60,
                 scheduledAt: referenceNow.addingTimeInterval(4 * 3600)),
        TaskItem(id: "t3", title: "Review the onboarding copy with Pablo", minutes: 30,
                 plannedFor: "2026-11-15", dueOn: "2026-11-16"),
        TaskItem(id: "t4", title: "Try the Mac app for a full day", minutes: 15, dueOn: "2026-11-24"),
    ]

    static let suggestions: [TaskSuggestion] = [
        TaskSuggestion(title: "Sketch the native calendar’s week view",
                       why: "The calendar is the biggest screen left, and nothing’s been planned for it yet.", minutes: 60),
        TaskSuggestion(title: "Ask two people to try the Mac app", why: "", minutes: 30),
    ]
}
