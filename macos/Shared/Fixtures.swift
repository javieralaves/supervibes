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

    /// What "Suggest a focus" might come back with for an untitled block.
    static let focusSuggestion = FocusSuggestion(
        aim: "Settle the week view's layout so part 4 can start.",
        why: "It's this week's objective, and the sketch task you planned for today is the last thing blocking it."
    )

    /// Protected time ahead with nothing prepared: one untitled (offers a focus), one titled (offers a plan).
    static var freshPanelBlocks: [CalendarBlock] {
        let day = Calendar.current.startOfDay(for: referenceNow)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3600 + minute * 60)) }
        return [
            CalendarBlock(id: "f1", goalId: "g1", title: nil, startsAt: at(15), endsAt: at(16, 30)),
            CalendarBlock(id: "f2", goalId: "g3", title: "Follow up with the community", startsAt: at(17, 30), endsAt: at(18)),
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
            CalendarBlock(id: "b6", goalId: "g2", title: "Lunch", startsAt: at(13, 0), endsAt: at(14, 0), hasRecapDraft: true),
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
}
