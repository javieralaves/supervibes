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

    /// The current block with an aim and a prepared agenda, one of its tasks already done.
    static func planned(at now: Date) -> Block? {
        guard var block = current(at: now) else { return nil }
        block.aim = "A native menu bar that reads today's blocks from the API."
        block.agenda = SessionAgenda(
            text: "Get the menu bar reading real blocks before you touch the widget: that's what makes the Mac app useful today. "
                + "Start by wiring the today endpoint into the app model, then swap the fixtures out of the popover. "
                + "Leave the widget on sample data for now, and stop to sign in once the token is in place so you know it holds across launches.",
            tasks: [
                .init(id: "t1", title: "Wire /api/v1/today into the app model", minutes: 60, done: true),
                .init(id: "t2", title: "Show real blocks in the menu bar popover", minutes: 30, done: false),
            ]
        )
        return block
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
            ConnectionItem(provider: .slack, label: "Slack", description: "Messages, threads and canvases.",
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

    /// The six goals' weeks: one with its objective and time to spare, one with time and no
    /// objective or tasks yet, one over, one with only reserved time, one with time and no tasks,
    /// and one well scoped.
    static var goalWeeks: [String: GoalWeek] {
        [
            "1": GoalWeek(objective: "Inspire new ideas for the Superfocus sprint", sessionMinutes: 510, reservedMinutes: 0, plannedMinutes: 135),
            "2": GoalWeek(objective: nil, sessionMinutes: 180, reservedMinutes: 0, plannedMinutes: 0),
            "3": GoalWeek(objective: "Draft the utilities chapter", sessionMinutes: 300, reservedMinutes: 0, plannedMinutes: 330),
            "4": GoalWeek(objective: nil, sessionMinutes: 0, reservedMinutes: 180, plannedMinutes: 0),
            "5": GoalWeek(objective: "Three workouts", sessionMinutes: 270, reservedMinutes: 0, plannedMinutes: 0),
            "6": GoalWeek(objective: "Ship the onboarding consolidation", sessionMinutes: 840, reservedMinutes: 0, plannedMinutes: 480),
        ]
    }

    /// The six goals as Life shows them: each in an area, and when each last moved, before `referenceNow`.
    static var lifeGoals: [Goal] {
        let placed: [String: (area: String, minutesAgo: Double)] = [
            "1": ("work", 120), "2": ("madrid", 20 * 60), "3": ("madrid", 7 * 60),
            "4": ("people", 3 * 24 * 60), "5": ("health", 9 * 24 * 60), "6": ("work", 45),
        ]
        return goals.map { goal in
            var goal = goal
            goal.areaId = placed[goal.id]?.area
            goal.updatedAt = placed[goal.id].map { referenceNow.addingTimeInterval(-$0.minutesAgo * 60) }
            return goal
        }
    }

    /// Six areas, rolled up from `lifeGoals`: Work on track, Madrid off track (its playbook is), People on track,
    /// Health with a goal and no status yet, and two with no goals. People has no words yet.
    static var areas: [Area] {
        [
            Area(id: "work", name: "Work", icon: "LaptopIcon",
                 now: "Superfocus sprints are landing. Supervibes ships fast but isn’t ready to show Pablo and Denis.",
                 want: "Supervibes inspires a new direction for Superfocus, and for productivity more broadly.",
                 status: .onTrack, goalIds: ["1", "6"]),
            Area(id: "madrid", name: "Madrid", icon: "Building03Icon",
                 now: "The housing playbook is live. The rent app works for Jacob; nobody has landed a home yet.",
                 want: "A playbook institutions act on, and friends finding a home in Madrid with ease.",
                 status: .offTrack, goalIds: ["2", "3"]),
            Area(id: "people", name: "People", icon: "UserGroupIcon", status: .onTrack, goalIds: ["4"]),
            Area(id: "health", name: "Health", icon: "HeartCheckIcon",
                 want: "Daily walks and three home workouts a week, without having to think about it.",
                 status: nil, goalIds: ["5"]),
            Area(id: "rest", name: "Rest & play", icon: "Coffee01Icon", status: nil, goalIds: []),
            Area(id: "home", name: "Home & money", icon: "Sofa01Icon", status: nil, goalIds: []),
        ]
    }

    /// Madrid's page: its two goals, its last weeks as the worse of theirs each day, and its read from this morning.
    static var areaDetail: AreaDetail {
        var detail = unreadAreaDetail
        detail.read = AreaRead(
            headline: "The playbook is live, but nobody has a home yet",
            summary: "The playbook went up on the 18th, and only refinement is left before it’s due Monday. The rent app is the gap: Jacob finds it useful, but there are no visits yet and Idealista access is unresolved. Madrid got 4 h of your last 7 days, for an area you’re growing.",
            goalIds: detail.area.goalIds,
            usedCalendar: true,
            createdAt: referenceNow.addingTimeInterval(-7 * 3600)
        )
        return detail
    }

    /// Madrid before its first read.
    static var unreadAreaDetail: AreaDetail {
        let area = areas[1]
        let goals = lifeGoals.filter { area.goalIds.contains($0.id) }
        let rank: [GoalStatus: Int] = [.unclear: 0, .onTrack: 1, .atRisk: 2, .offTrack: 3]
        let trajectory = (0..<28).map { index -> AreaTrajectoryDay in
            let days = goals.map { $0.trajectory[index] }.filter { $0.status != nil }
            let worst = days.compactMap(\.status).max { rank[$0, default: 0] < rank[$1, default: 0] }
            return AreaTrajectoryDay(day: goals[0].trajectory[index].day, status: worst,
                                     carried: !days.isEmpty && days.allSatisfy(\.carried))
        }
        return AreaDetail(area: area, today: "2026-11-18", trajectory: trajectory, goals: goals,
                          weeks: goalWeeks.filter { area.goalIds.contains($0.key) })
    }

    /// An area just made: a name and an icon, nothing else yet.
    static var newAreaDetail: AreaDetail {
        let area = Area(id: "learning", name: "Learning", icon: "BookOpen01Icon", status: nil, goalIds: [])
        return AreaDetail(area: area, today: "2026-11-18",
                          trajectory: (0..<28).map { AreaTrajectoryDay(day: CalendarDay.addDays("2026-10-22", $0), status: nil, carried: false) },
                          goals: [], weeks: [:])
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

    /// The first goal's page for planning: its tasks, its protected time this week and next, two
    /// tasks already done.
    static var planningDetail: GoalDetail {
        var detail = goalDetail
        detail.tasks = tasks
        detail.week.protectedBlocks = protectedBlocks
        detail.week.done = [
            TaskItem(id: "d1", title: "Sign in with a one-time code", minutes: 60, done: true, plannedFor: "2026-11-18", plannedWeek: "2026-11-16"),
            TaskItem(id: "d2", title: "Draft the menu bar’s copy", minutes: 30, done: true, plannedWeek: "2026-11-16"),
        ]
        return detail
    }

    /// The planning board across the six goals on Wednesday Nov 18: Build Supervibes as on its own
    /// board, then Jacob's app with time to spare, the housing playbook over tomorrow and with no
    /// objective, a goal with nothing at all, Movement with time and no tasks, and Superfocus.
    static var board: BoardData {
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(identifier: "Europe/Madrid")
            return components.date!
        }
        func blocks(_ spans: [(Int, Int, Int, Int, Int)]) -> [ProtectedBlock] {
            spans.map { ProtectedBlock(start: at($0.0, $0.1, $0.2), end: at($0.0, $0.3, $0.4)) }
        }
        let detail = planningDetail
        let goals = Self.goals
        func goal(_ index: Int, objective: String?, tasks: [TaskItem], done: [TaskItem] = [], blocks: [ProtectedBlock]) -> BoardGoal {
            BoardGoal(id: goals[index].id, title: goals[index].title, icon: goals[index].icon, color: goals[index].color,
                      objective: objective, tasks: tasks, done: done, protectedBlocks: blocks)
        }
        var data = BoardData(today: "2026-11-18", clock: nil, goals: [
            goal(0, objective: detail.week.objective, tasks: detail.tasks, done: detail.week.done, blocks: detail.week.protectedBlocks),
            goal(1, objective: "Get the agent answering with real listings", tasks: [
                TaskItem(id: "j1", title: "Follow up with Idealista re: API access", minutes: 15, plannedFor: "2026-11-18", plannedWeek: "2026-11-16"),
                TaskItem(id: "j2", title: "Log failed Idealista MCP queries and rewrite them", minutes: 60, plannedFor: "2026-11-19", plannedWeek: "2026-11-16"),
                TaskItem(id: "j3", title: "Compare Fotocasa’s API with Idealista’s", minutes: 30),
            ], blocks: blocks([(18, 11, 0, 12, 0), (19, 9, 0, 10, 0), (20, 9, 0, 10, 0)])),
            goal(2, objective: nil, tasks: [
                TaskItem(id: "p1", title: "Interview two expats about renting", minutes: 120, plannedFor: "2026-11-19", plannedWeek: "2026-11-16"),
                TaskItem(id: "p2", title: "Map neighbourhoods by commute", minutes: 60, plannedFor: "2026-11-19", plannedWeek: "2026-11-16"),
                TaskItem(id: "p3", title: "Draft the utilities chapter", minutes: 120, plannedWeek: "2026-11-16"),
            ], blocks: blocks([(19, 10, 0, 11, 30), (20, 10, 0, 12, 0)])),
            goal(3, objective: nil, tasks: [], blocks: []),
            goal(4, objective: "Three workouts", tasks: [], blocks: blocks([(18, 18, 0, 19, 0), (20, 18, 0, 19, 0), (21, 10, 0, 11, 30)])),
            goal(5, objective: "Ship the onboarding consolidation", tasks: [
                TaskItem(id: "s1", title: "Prototype a single quick capture experience", minutes: 120, plannedFor: "2026-11-18", plannedWeek: "2026-11-16"),
                TaskItem(id: "s2", title: "Clean up Lens product experience & data", minutes: 60, plannedWeek: "2026-11-16"),
                TaskItem(id: "s3", title: "Review what the sprint shipped", minutes: 30, plannedWeek: "2026-11-23"),
            ], done: [
                TaskItem(id: "s0", title: "Follow up with the community", minutes: 30, done: true, plannedFor: "2026-11-17", plannedWeek: "2026-11-16"),
            ], blocks: blocks([(18, 13, 0, 16, 0), (19, 13, 0, 15, 0), (23, 13, 0, 16, 0)])),
        ])
        // Every goal's sessions as blocks, and lunch kept for its own sake; awake 8 AM to 11:30 PM.
        data.blocks = data.goals.flatMap { goal in
            goal.protectedBlocks.enumerated().map { BoardBlock(id: "\(goal.id)-b\($0.offset)", goalId: goal.id, start: $0.element.start, end: $0.element.end) }
        } + [BoardBlock(id: "lunch", goalId: goals[3].id, start: at(18, 14), end: at(18, 15), reserved: true)]
        data.wakeTime = 8 * 60
        data.sleepStart = 23 * 60 + 30
        return data
    }

    /// The goal's protected time around `referenceNow` (Wednesday 10:18): Monday's and Tuesday's
    /// gone by; today one block over and one ahead, with more planned than both (over capacity);
    /// none tomorrow; Friday with time to spare; Saturday's long block making the week fit, 1 h to
    /// spare; and two blocks next week.
    static var protectedBlocks: [ProtectedBlock] {
        func at(_ day: Int, _ hour: Int) -> Date {
            var components = DateComponents(year: 2026, month: 11, day: day, hour: hour)
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(identifier: "Europe/Madrid")
            return components.date!
        }
        return [
            (16, 9, 12), (17, 14, 16), (18, 9, 10), (18, 16, 17), (20, 9, 11), (21, 10, 15), (23, 9, 11), (25, 9, 11),
        ].map { ProtectedBlock(start: at($0.0, $0.1), end: at($0.0, $0.2)) }
    }

    /// Open tasks as of Wednesday 2026-11-18 (the week of Nov 16): planned for days, for this week
    /// (one slipped and carried over, one carried twice), for next week, and in Later.
    static let tasks: [TaskItem] = [
        TaskItem(id: "t1", title: "Rebuild the goal page’s tasks natively",
                 description: "Drag to reorder, day pills, suggestions.\nThen notes and sources.",
                 minutes: 120, plannedFor: "2026-11-18", plannedWeek: "2026-11-16", dueOn: "2026-11-19"),
        TaskItem(id: "t2", title: "Write the API sketch for the calendar", minutes: 60,
                 plannedFor: "2026-11-18", plannedWeek: "2026-11-16", scheduledAt: referenceNow.addingTimeInterval(4 * 3600)),
        TaskItem(id: "t5", title: "Sketch the week view", minutes: 60, plannedWeek: "2026-11-16"),
        TaskItem(id: "t3", title: "Review the onboarding copy with Pablo", minutes: 30,
                 plannedFor: "2026-11-15", plannedWeek: "2026-11-09", dueOn: "2026-11-16"),
        TaskItem(id: "t6", title: "Tidy the empty states", minutes: 120, plannedWeek: "2026-11-02"),
        TaskItem(id: "t7", title: "Write the release notes", minutes: 30, plannedFor: "2026-11-20", plannedWeek: "2026-11-16"),
        TaskItem(id: "t8", title: "Ask two people to try a beta", minutes: 15, plannedWeek: "2026-11-23"),
        TaskItem(id: "t4", title: "Try the Mac app for a full day", minutes: 15, dueOn: "2026-11-24"),
        TaskItem(id: "t9", title: "Explore a lock screen widget", minutes: 120),
    ]

    static let suggestions: [TaskSuggestion] = [
        TaskSuggestion(title: "Sketch the native calendar’s week view",
                       why: "The calendar is the biggest screen left, and nothing’s been planned for it yet.", minutes: 60),
        TaskSuggestion(title: "Ask two people to try the Mac app", why: "", minutes: 30),
    ]

    static let author = NoteAuthor(name: "Javier Alaves", imageURL: nil)

    /// One of each kind of activity entry, newest first.
    static var notes: [NoteItem] {
        let hour: TimeInterval = 3600
        let start = referenceNow.addingTimeInterval(-26 * hour)
        return [
            NoteItem(id: "n1", body: "Decided to keep the web app running until the calendar is native, then retire it.",
                     createdAt: referenceNow.addingTimeInterval(-2 * hour), updatedAt: referenceNow.addingTimeInterval(-1 * hour)),
            NoteItem(id: "n2", body: "", completedTask: "Rebuild the goal page’s tasks natively", taskId: "t1",
                     taskDescription: "Drag to reorder, day pills, suggestions.",
                     createdAt: referenceNow.addingTimeInterval(-5 * hour), updatedAt: referenceNow.addingTimeInterval(-5 * hour)),
            NoteItem(id: "n3", body: "Got the progress card and this week’s objective working; the hover card needed a second pass.",
                     session: .init(title: "Native goal page", startsAt: start, endsAt: start.addingTimeInterval(80 * 60),
                                    aim: "Ship part 1 of the goal page."),
                     breadcrumbs: [
                        .init(provider: .github, title: "Build part 1 of the native goal page", url: URL(string: "https://github.com/x/y/commit/1")!),
                        .init(provider: .linear, title: "SUP-42 Native goal page", url: URL(string: "https://linear.app/x/issue/SUP-42")!),
                     ],
                     createdAt: referenceNow.addingTimeInterval(-24 * hour), updatedAt: referenceNow.addingTimeInterval(-24 * hour)),
            NoteItem(id: "n4", body: "Wrote it up in the README.", completedSuggestion: "Write down what the Mac app should do first",
                     createdAt: referenceNow.addingTimeInterval(-3 * 24 * hour), updatedAt: referenceNow.addingTimeInterval(-3 * 24 * hour)),
        ]
    }

    static let connectionOptions: [ConnectionOption] = [
        ConnectionOption(id: "c1", provider: .linear, label: "Linear",
                         relationHint: "e.g. The Supervibes project. Shipped issues are direct progress; feedback from user calls shapes where it’s going."),
        ConnectionOption(id: "c2", provider: .github, label: "GitHub",
                         relationHint: "e.g. The javieralaves/supervibes repo. Merged PRs are progress; open PRs show what I’m in the middle of."),
    ]

    static let sources: [SourceItem] = [
        SourceItem(id: "s1", connectionId: "c1", provider: .linear,
                   relation: "The Supervibes project. Shipped issues are direct progress; ignore routine bug triage."),
        SourceItem(id: "s2", connectionId: "c2", provider: .github,
                   relation: "The supervibes repo. Merged PRs are progress.", lastError: "The token expired."),
    ]

    /// The block panel's three states: ahead with an aim and agenda, ended with a draft recap, recapped.
    static var panelBlocks: [CalendarBlock] {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        let github = NoteItem.Breadcrumb(provider: .github, title: "Native calendar: day view (#212)", url: URL(string: "https://github.com/example/supervibes/pull/212")!)
        let granola = NoteItem.Breadcrumb(provider: .granola, title: "Calendar sync with design", url: URL(string: "https://notes.granola.ai/d/example")!)
        return [
            CalendarBlock(
                id: "p1", goalId: "g1", title: "Week view sketch", description: "Get the week view's layout settled so part 4 can start.",
                startsAt: at(15), endsAt: at(16, 30), hasAgenda: true,
                agenda: BlockAgenda(
                    text: "Aim to leave with the week view's layout decided: seven columns, how blocks shrink, and where the overview panel sits. Start from the web version and note what has to change natively, then sketch the two trickiest bits.",
                    tasks: [.init(id: "t5", title: "Sketch the week view", minutes: 45), .init(id: "t7", title: "List what the week view needs from the API", minutes: 30)],
                    preparedAt: referenceNow.addingTimeInterval(-25 * 60), keptTitle: true, title: "Week view sketch", description: "Get the week view's layout settled."
                )
            ),
            CalendarBlock(
                id: "p2", goalId: "g1", title: "Rebuild the calendar natively", startsAt: at(8), endsAt: at(9, 30), taskId: "t9", hasRecapDraft: true,
                recap: RecapDraft(
                    planned: "Build the day view's reading parts.",
                    happened: "Finished the day view: hour grid, sleep shading, blocks filling in as time passes, and the now line. Snapshot tests cover light and dark.",
                    breadcrumbs: [github], found: .clear, taskLooksDone: true, preparedAt: referenceNow.addingTimeInterval(-40 * 60), auto: true
                )
            ),
            CalendarBlock(
                id: "p3", goalId: "g3", title: nil, description: "Hear how people plan their week.", startsAt: at(7), endsAt: at(8), hasRecapPost: true,
                recapPost: PostedRecap(
                    body: "Talked to three people about weekly planning. Two plan on Sunday evening, one on Monday morning. All three want to see last week before planning the next, which argues for the week overview showing what got done, not only what's planned. One wants objectives to carry over when unfinished.",
                    breadcrumbs: [granola]
                )
            ),
        ]
    }

    /// The calendar's goals with a practice among them: Workouts, three times a week, at least 30 min, one done and
    /// two planned this week.
    static var practiceCalendarGoals: [CalendarGoal] {
        calendar.goals + [
            CalendarGoal(id: "w", title: "Workouts", icon: "Dumbbell01Icon", color: "green", kind: .practice, perWeek: 3, minMinutes: 30,
                         week: .init(start: "2026-11-16", done: 1, planned: 2)),
            CalendarGoal(id: "t", title: "Tagalog", icon: "LanguageSkillIcon", color: "amber", kind: .practice, perWeek: 4),
        ]
    }

    /// The calendar with practices kept without blocks: Workouts with one done and one planned for Friday (no time),
    /// so one left to plan; Walk with one logged today, three left; Tagalog with all four left.
    static var calendarWithPractices: CalendarData {
        var data = calendar
        data.goals += [
            CalendarGoal(id: "w", title: "Workouts", icon: "Dumbbell01Icon", color: "green", kind: .practice, perWeek: 3, minMinutes: 30,
                         week: .init(start: "2026-11-16", done: 1, planned: 1)),
            CalendarGoal(id: "k", title: "Walk", icon: "RunningShoesIcon", color: "violet", kind: .practice, perWeek: 5,
                         week: .init(start: "2026-11-16", done: 2, planned: 0)),
            CalendarGoal(id: "t", title: "Tagalog", icon: "LanguageSkillIcon", color: "amber", kind: .practice, perWeek: 4,
                         week: .init(start: "2026-11-16", done: 0, planned: 0)),
        ]
        data.practiceSessions = [
            CalendarPracticeSession(id: "ps1", goalId: "w", day: "2026-11-20", done: false),
            CalendarPracticeSession(id: "ps2", goalId: "k", day: "2026-11-18", done: true),
            CalendarPracticeSession(id: "ps3", goalId: "w", day: "2026-11-18", done: false),
        ]
        return data
    }

    /// Workouts' blocks: one this evening, still to come; this morning's, counted; and yesterday's, which didn't happen.
    static var practicePanelBlocks: [CalendarBlock] {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
            day.addingTimeInterval(Double(days * 86_400 + hour * 3600 + minute * 60))
        }
        return [
            CalendarBlock(id: "w1", goalId: "w", title: nil, startsAt: at(18), endsAt: at(18, 45)),
            CalendarBlock(id: "w2", goalId: "w", title: "Home workout", startsAt: at(7, 30), endsAt: at(8, 15)),
            CalendarBlock(id: "w3", goalId: "w", title: nil, startsAt: at(9, days: -1), endsAt: at(9, 30, days: -1), missed: true),
        ]
    }

    /// What "Suggest a focus" might come back with for an untitled block.
    static let focusSuggestion = FocusSuggestion(
        aim: "Settle the week view's layout so part 4 can start.",
        why: "It's this week's objective, and the sketch task you planned for today is the last thing blocking it."
    )

    /// Sessions ahead with nothing prepared: protected time untitled (offers a focus) and titled (offers a plan), and a task's (offers a plan).
    static var freshPanelBlocks: [CalendarBlock] {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        return [
            CalendarBlock(id: "f1", goalId: "g1", title: nil, startsAt: at(15), endsAt: at(16, 30)),
            CalendarBlock(id: "f2", goalId: "g3", title: "Follow up with the community", startsAt: at(17, 30), endsAt: at(18)),
            CalendarBlock(id: "f3", goalId: "g1", title: "Sketch the week view", startsAt: at(11), endsAt: at(12), taskId: "t5"),
        ]
    }

    /// Protected time ahead, as a session and as reserved time, for the panel's switch.
    static var kindPanelBlocks: [CalendarBlock] {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        return [
            CalendarBlock(id: "k1", goalId: "g1", title: nil, startsAt: at(15), endsAt: at(16, 30)),
            CalendarBlock(id: "k2", goalId: "g2", title: "Lunch with family", startsAt: at(13), endsAt: at(14, 30), reserved: true),
        ]
    }

    /// A calendar day around `referenceNow` (10:18): sessions behind, one under way, more ahead.
    static var calendar: CalendarData {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        let goals = [
            CalendarGoal(id: "g1", title: "Ship Supervibes for Mac", icon: "Rocket01Icon", color: "sky"),
            CalendarGoal(id: "g2", title: "Run a calm week", icon: "Plant01Icon", color: "pink"),
            CalendarGoal(id: "g3", title: "Stay engaged with the community", icon: "Briefcase01Icon", color: "indigo"),
        ]
        let blocks = [
            CalendarBlock(id: "b1", goalId: "g1", title: nil, startsAt: at(8, 15), endsAt: at(9, 45), hasRecapPost: true),
            CalendarBlock(id: "b2", goalId: "g2", title: "Groceries with Julia", startsAt: at(9, 45), endsAt: at(10, 0)),
            CalendarBlock(id: "b3", goalId: "g1", title: "Rebuild the calendar natively", startsAt: at(10, 0), endsAt: at(11, 30),
                          taskId: "t9"),
            CalendarBlock(id: "b4", goalId: "g3", title: "User research call", startsAt: at(12, 0), endsAt: at(12, 30)),
            CalendarBlock(id: "b5", goalId: "g1", title: "Review the onboarding copy", startsAt: at(7, 0), endsAt: at(7, 45),
                          taskId: "t3", taskDone: true),
            CalendarBlock(id: "b6", goalId: "g2", title: "Lunch", startsAt: at(13, 0), endsAt: at(14, 0), reserved: true),
        ]
        let tasks = [
            CalendarTask(id: "t1", goalId: "g1", title: "Write the API sketch", minutes: 60, plannedFor: "2026-11-18"),
            CalendarTask(id: "t2", goalId: "g2", title: "Book the restaurant", minutes: 15, plannedFor: "2026-11-16"),
            CalendarTask(id: "t4", goalId: "g3", title: "Reply to Jorge", minutes: 30, dueOn: "2026-11-17"),
            CalendarTask(id: "t9", goalId: "g1", title: "Rebuild the calendar natively", minutes: 90),
            CalendarTask(id: "t5", goalId: "g1", title: "Sketch the week view", minutes: 45, plannedFor: "2026-11-19", dueOn: "2026-11-20"),
            CalendarTask(id: "t6", goalId: "g2", title: "Plan the weekend", minutes: 30),
        ]
        // Earlier and later in the week, for the week view.
        let week = [
            CalendarBlock(id: "w1", goalId: "g1", title: "API sketch", startsAt: at(9).addingTimeInterval(-2 * 86_400), endsAt: at(11).addingTimeInterval(-2 * 86_400), hasRecapPost: true),
            CalendarBlock(id: "w2", goalId: "g3", title: "Community call", startsAt: at(16).addingTimeInterval(-86_400), endsAt: at(17).addingTimeInterval(-86_400)),
            CalendarBlock(id: "w3", goalId: "g1", title: "Week view sketch", startsAt: at(9).addingTimeInterval(86_400), endsAt: at(12).addingTimeInterval(86_400)),
            CalendarBlock(id: "w4", goalId: "g2", title: "Long walk", startsAt: at(10).addingTimeInterval(3 * 86_400), endsAt: at(11, 30).addingTimeInterval(3 * 86_400)),
        ]
        return CalendarData(blocks: blocks + week, goals: goals, tasks: tasks, sleepStart: 23 * 60 + 30, wakeTime: 7 * 60 + 30,
                            clock: .twelveHour, objectives: [
                                .init(goalId: "g1", weekStart: "2026-11-16", objective: "Finish the native calendar, week view included."),
                            ])
    }


    /// A day just planned across goals, for the strip by goal ("The day, by goal" in supervibes-design):
    /// Superfocus 1 h 30 min over its sessions, Build with 45 min spare, two goals with tasks and no
    /// sessions, and one with only a task due today.
    static var dayByGoal: CalendarData {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        let today = "2026-11-18"
        let goals = [
            CalendarGoal(id: "build", title: "Build Supervibes as a fresh take on productivity", icon: "Rocket01Icon", color: "sky"),
            CalendarGoal(id: "jacob", title: "Build an app that helps Jacob find an apartment in Madrid", icon: "Home01Icon", color: "teal"),
            CalendarGoal(id: "playbook", title: "Deliver research-backed housing playbook for Madrid", icon: "Target02Icon", color: "coral"),
            CalendarGoal(id: "leisure", title: "Carve time out for leisure", icon: "Plant01Icon", color: "pink"),
            CalendarGoal(id: "superfocus", title: "Stay engaged with Superfocus and the community", icon: "Briefcase01Icon", color: "indigo"),
        ]
        let blocks = [
            CalendarBlock(id: "sf1", goalId: "superfocus", title: nil, startsAt: at(13), endsAt: at(14, 30)),
            CalendarBlock(id: "hamish", goalId: "superfocus", title: "Chat about Superfocus – Hamish", startsAt: at(14, 30), endsAt: at(15), reserved: true),
            CalendarBlock(id: "sf2", goalId: "superfocus", title: nil, startsAt: at(15), endsAt: at(16)),
            CalendarBlock(id: "vinay", goalId: "superfocus", title: "Chat about Superfocus – Vinay", startsAt: at(16), endsAt: at(16, 30), reserved: true),
            CalendarBlock(id: "richie", goalId: "superfocus", title: "Chat about Superfocus – Richie", startsAt: at(16, 30), endsAt: at(17), reserved: true),
            CalendarBlock(id: "build1", goalId: "build", title: nil, startsAt: at(17), endsAt: at(20, 30)),
            // Friday: Superfocus has 3 h and 30 min of it planned, so room for what doesn't fit today.
            CalendarBlock(id: "sf-friday", goalId: "superfocus", title: nil, startsAt: at(13).addingTimeInterval(2 * 86_400), endsAt: at(16).addingTimeInterval(2 * 86_400)),
        ]
        func task(_ id: String, _ goal: String, _ title: String, _ minutes: Int, planned: Bool = true, due: Bool = false) -> CalendarTask {
            CalendarTask(id: id, goalId: goal, title: title, minutes: minutes, plannedFor: planned ? today : nil, dueOn: due ? today : nil)
        }
        let tasks = [
            task("sf-spark", "superfocus", "Brainstorm experience for Spark Summit", 60, due: true),
            task("b-polish", "build", "Polish here and there", 60),
            task("p-election", "playbook", "Assess election likeliness & impact on the housing market", 30),
            task("b-catch", "build", "“Catch up” to new activity", 30),
            task("j-listings", "jacob", "Daily time aside to update listings", 30),
            task("b-login", "build", "Launch at login", 15),
            task("sf-design", "superfocus", "Test the design system workflow", 30),
            task("j-skor", "jacob", "Research Skor product strategy", 30),
            task("sf-actions", "superfocus", "Actions in other apps", 60),
            task("j-idealista", "jacob", "Brainstorm “modern Idealista”", 30),
            task("sf-community", "superfocus", "Put time aside daily for community", 15),
            task("sf-reality", "superfocus", "Look into extending reality tracking", 15),
            task("b-delete", "build", "A signed-in user can delete or export their data", 15),
            task("sf-renewals", "superfocus", "January renewals for the first founding members", 30),
            task("b-imported", "build", "Imported calendar events land on the right goal", 30),
            task("b-blocks", "build", "Deleting several selected blocks at once", 15),
            task("sf-focus", "superfocus", "Make focus time editing more forgiving", 30),
            task("l-tickets", "leisure", "Buy tickets for Doomsday", 30, planned: false, due: true),
            CalendarTask(id: "sf-friday-task", goalId: "superfocus", title: "Draft the community newsletter", minutes: 30, plannedFor: "2026-11-20"),
        ]
        return CalendarData(blocks: blocks, goals: goals, tasks: tasks, sleepStart: 23 * 60 + 30, wakeTime: 7 * 60 + 30,
                            clock: .twelveHour, objectives: [])
    }

    // MARK: - Practices

    /// Four practices on Wednesday, Nov 18 (their week started Monday the 16th): Workouts at risk with one done and
    /// two planned, Walk on track, Tagalog off track, and Superfocus on track.
    static var practices: [Goal] {
        func practice(_ id: String, _ title: String, _ icon: String, _ color: String, area: String, perWeek: Int, min: Int? = nil,
                      done: Int, planned: Int, status: GoalStatus, counted: Int, weeks: Int = 4) -> Goal {
            Goal(id: id, title: title, icon: icon, color: color, trajectory: [], areaId: area, kind: .practice,
                 practice: Practice(perWeek: perWeek, minMinutes: min,
                                    week: .init(start: "2026-11-16", done: done, planned: planned),
                                    status: .init(status: status, done: counted, expected: perWeek * weeks, weeks: weeks,
                                                  reason: "\(counted) of the last \(perWeek * weeks)")))
        }
        return [
            practice("p1", "Workouts", "Dumbbell01Icon", "green", area: "health", perWeek: 3, min: 30, done: 1, planned: 2, status: .atRisk, counted: 8),
            practice("p2", "Walk", "RunningShoesIcon", "violet", area: "health", perWeek: 5, done: 2, planned: 0, status: .onTrack, counted: 18),
            practice("p3", "Tagalog", "LanguageSkillIcon", "amber", area: "people", perWeek: 4, min: 20, done: 0, planned: 1, status: .offTrack, counted: 1),
            practice("p4", "Superfocus and the community", "Briefcase01Icon", "indigo", area: "work", perWeek: 4, done: 2, planned: 1, status: .onTrack, counted: 15),
        ]
    }

    /// Life with practices: the three goals with an end as projects, then the practices.
    static var lifeWithPractices: [Goal] {
        lifeGoals.filter { ["1", "2", "3"].contains($0.id) } + practices
    }

    /// The areas, holding projects and practices: Health and People now have a status from their practices.
    static var practiceAreas: [Area] {
        var list = areas
        list[0].goalIds = ["1", "p4"]
        list[2].goalIds = ["p3"]
        list[2].status = .offTrack
        list[3].goalIds = ["p1", "p2"]
        list[3].status = .atRisk
        return list
    }

    /// Workouts' last 8 full weeks: 3, 3, 2, 3, then 3, 1, 2, 2 (the four its status counts: 8 of 12).
    private static var workoutWeeks: [Practice.Week] {
        zip(["2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26", "2026-11-02", "2026-11-09"],
            [3, 3, 2, 3, 3, 1, 2, 2]).map { Practice.Week(start: $0, done: $1, planned: 0) }
    }

    private static func block(_ id: String, _ day: Int, _ hour: Int, _ minutes: Int, _ state: PracticeSession.State, title: String? = nil) -> PracticeSession {
        let start = madrid(day, hour)
        return PracticeSession(id: id, source: .block, day: String(format: "2026-11-%02d", day), state: state, title: title,
                               startsAt: start, endsAt: start.addingTimeInterval(Double(minutes) * 60))
    }

    /// Last week's sessions: two blocks and a run logged on Saturday, and a short one that didn't count.
    private static var lastWeekSessions: [PracticeSession] {
        [
            block("s1", 11, 8, 45, .done, title: "Home workout"),
            block("s2", 12, 18, 20, .short),
            PracticeSession(id: "s3", source: .day, day: "2026-11-14", state: .done),
        ]
    }

    /// Workouts' page on Wednesday: Monday's done, Tuesday's didn't happen, today's 6 PM and Friday's 7:30 AM planned.
    static var practiceDetail: GoalDetail {
        var goal = practices[0]
        goal.description = "Three home workouts a week, without having to think about it."
        return GoalDetail(
            goal: goal,
            today: "2026-11-18",
            read: nil,
            status: nil,
            readsInTrajectory: 0,
            readPending: false,
            readError: nil,
            canRead: false,
            week: .init(start: "2026-11-16", objective: nil, lastWeek: nil),
            area: AreaRef(id: "health", name: "Health", icon: "HeartCheckIcon"),
            practice: PracticeDetail(
                weeks: workoutWeeks,
                sessions: lastWeekSessions + [
                    block("s4", 16, 9, 30, .done, title: "Home workout"),
                    block("s5", 17, 9, 30, .missed),
                    block("s6", 18, 18, 45, .planned),
                    block("s7", 20, 7, 30, .planned),
                ]
            )
        )
    }

    /// Workouts with no days set: Monday's logged, and two to go any day.
    static var unplannedPracticeDetail: GoalDetail {
        var detail = practiceDetail
        detail.goal.practice?.week = .init(start: "2026-11-16", done: 1, planned: 0)
        detail.practice?.sessions = lastWeekSessions + [PracticeSession(id: "s8", source: .day, day: "2026-11-16", state: .done)]
        return detail
    }

    /// Workouts paused this morning, until Monday, Nov 30.
    static var pausedPracticeDetail: GoalDetail {
        var detail = practiceDetail
        detail.goal.practice?.status = nil
        detail.goal.practice?.paused = .init(startsOn: "2026-11-18", resumesOn: "2026-11-30")
        detail.goal.practice?.week = .init(start: "2026-11-16", done: 1, planned: 0, paused: true)
        detail.practice?.sessions = lastWeekSessions + [block("s4", 16, 9, 30, .done, title: "Home workout")]
        return detail
    }

    /// Health's page: no projects, and its two practices.
    static var practiceAreaDetail: AreaDetail {
        let area = practiceAreas[3]
        return AreaDetail(area: area, today: "2026-11-18",
                          trajectory: (0..<28).map { AreaTrajectoryDay(day: CalendarDay.addDays("2026-10-22", $0), status: $0 < 7 ? .onTrack : .atRisk, carried: false) },
                          goals: practices.filter { area.goalIds.contains($0.id) }, weeks: [:])
    }

    // MARK: - Calendar import

    /// A time on a day of the reference week (Wednesday Nov 18 is today), in Madrid.
    private static func madrid(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        return components.date!
    }

    /// Events in the person's Google calendars around `referenceNow`; "research" is imported (to g3).
    static var externalEvents: [ExternalEvent] {
        [
            ExternalEvent(key: "review", calendarId: "work", calendarName: "Work", title: "Design review: block editing",
                          start: madrid(18, 12), end: madrid(18, 12, 30)),
            ExternalEvent(key: "research", calendarId: "work", calendarName: "Work", title: "User research call",
                          start: madrid(18, 15), end: madrid(18, 15, 30)),
            ExternalEvent(key: "physio", calendarId: "personal", calendarName: "Personal", title: "Physio",
                          start: madrid(19, 8), end: madrid(19, 8, 45)),
            ExternalEvent(key: "planning", calendarId: "work", calendarName: "Work", title: "Planning with Pablo",
                          start: madrid(19, 14), end: madrid(19, 15)),
            ExternalEvent(key: "weekly", calendarId: "work", calendarName: "Work", title: "Superfocus weekly",
                          start: madrid(20, 12, 15), end: madrid(20, 12, 45), repeats: true),
        ]
    }

    /// The events panel's days for `externalEvents`.
    static var eventDays: [EventDay] {
        let labels = [0: "Today", 1: "Tomorrow", 2: "Friday, Nov 20"]
        let byDay = Dictionary(grouping: externalEvents) { CalendarDayMath.dayOffset($0.start, from: referenceNow) }
        return byDay.keys.sorted().map { EventDay(day: $0, label: labels[$0] ?? "", events: byDay[$0] ?? []) }
    }
}
