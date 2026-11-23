import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Renders the native surfaces to PNGs in __Snapshots__/, in light and dark.
/// Reference images are checked in; a changed view fails until it's re-recorded (scripts/snapshot.sh --record).
@MainActor
final class SurfaceSnapshotTests: XCTestCase {
    private let now = Fixtures.referenceNow

    func testMenuBarDuringBlock() {
        assertAppearances(
            MenuBarContent(current: Fixtures.current(at: now), upcoming: Fixtures.upcoming(at: now), now: now),
            width: 300
        )
    }

    func testMenuBarDuringPlannedBlock() {
        assertAppearances(
            MenuBarContent(current: Fixtures.planned(at: now), upcoming: Fixtures.upcoming(at: now), now: now),
            width: 300
        )
    }

    func testMenuBarStartingSoon() {
        // Eight minutes before the next block, with nothing under way.
        let soon = now.addingTimeInterval(52 * 60)
        let upcoming = Fixtures.blocks(around: now).filter { $0.start > soon }
        assertAppearances(MenuBarContent(current: nil, upcoming: upcoming, now: soon), width: 300)
    }

    func testMenuBarSuggestedFocus() {
        let block = Fixtures.current(at: now)!
        let untitled = Block(id: block.id, title: block.goal, goal: "Protected time", start: block.start, end: block.end, tint: block.tint, untitled: true)
        assertAppearances(
            SessionPlanView(block: untitled, suggestion: Fixtures.focusSuggestion).padding(16),
            width: 300
        )
    }

    func testMenuBarWithNothingScheduled() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now), width: 300)
    }

    func testMenuBarSignedOut() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now, isSignedIn: false), width: 300)
    }

    func testSettingsPage() {
        let settings = SleepSettings(sleepStart: 23 * 60 + 30, wakeTime: 8 * 60, clock: .twelveHour)
        assertAppearances(
            SettingsPage(
                settings: .constant(settings),
                status: (.sleep, .saved),
                usage: UsageSummary(calls: Fixtures.usageCalls, today: now),
                calendar: CalendarViewCard(span: .days(3))
            )
            .background(Theme.background),
            width: 900, height: 2800
        )
    }

    func testNoticesCard() {
        assertAppearances(
            VStack(spacing: 12) {
                NoticesCard(settings: .defaults, permission: .notAsked)
                NoticesCard(settings: NoticeSettings(isOn: true, leads: [.five, .atStart]), permission: .allowed)
                NoticesCard(settings: NoticeSettings(isOn: true, leads: [.fifteen]), permission: .denied)
            }
            .padding(32)
            .background(Theme.background),
            width: 768, height: 640
        )
    }

    func testSessionRoutineCard() {
        let slack = SessionRoutine.App(bundleId: "com.tinyspeck.slackmacgap", name: "Slack")
        let mail = SessionRoutine.App(bundleId: "com.apple.mail", name: "Mail")
        assertAppearances(
            VStack(spacing: 12) {
                SessionRoutineCard(routine: .defaults, shortcuts: [])
                SessionRoutineCard(routine: SessionRoutine(doNotDisturb: true), shortcuts: [SessionRoutine.focusOn])
                SessionRoutineCard(
                    routine: SessionRoutine(doNotDisturb: true, quitApps: [slack, mail], start: "Start playlist", end: "Old routine"),
                    shortcuts: [SessionRoutine.focusOn, SessionRoutine.focusOff, "Start playlist"]
                )
            }
            .padding(32)
            .background(Theme.background),
            width: 768, height: 1600
        )
    }

    func testSettingsPageWithProblem() {
        let settings = SleepSettings(sleepStart: 8 * 60, wakeTime: 8 * 60, clock: nil)
        assertAppearances(
            SettingsPage(settings: .constant(settings), status: (.sleep, .failed(settings.problem!)), usage: nil)
                .background(Theme.background),
            width: 900, height: 900
        )
    }

    func testShellWithSettings() {
        let account = RailAccount(name: "Javi", email: "you@example.com", imageURL: nil)
        let settings = SleepSettings(sleepStart: 23 * 60 + 30, wakeTime: 8 * 60, clock: .twelveHour)
        assertAppearances(
            HStack(spacing: 0) {
                Rail(active: nil, account: account, topInset: 28)
                AppWindowFrame {
                    ZStack {
                        Backdrop()
                        SettingsPage(settings: .constant(settings), usage: UsageSummary(calls: Fixtures.usageCalls, today: now))
                    }
                }
            }
            .background(Theme.shell),
            width: 1280, height: 820
        )
    }

    func testRailAndAccountMenu() {
        let account = RailAccount(name: "Javi", email: "you@example.com", imageURL: nil)
        assertAppearances(
            HStack(alignment: .bottom, spacing: 12) {
                Rail(active: .calendar, account: account, isMenuOpen: true)
                AccountMenu(account: account).padding(.bottom, 12)
            }
            .frame(height: 360, alignment: .leading)
            .background(Theme.shell),
            width: 360, height: 360
        )
    }

    /// Right-click menus: a task's, a block's (with Give time) and a goal card's.
    func testRightClickMenus() {
        let task = Fixtures.tasks[0]
        let blocks = Fixtures.panelBlocks
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                TaskMenu(
                    task: task, horizon: task.horizon(today: "2026-11-18"), today: "2026-11-18",
                    thisWeek: "2026-11-16", nextWeek: "2026-11-23", actions: TaskActions(), onOpen: {}, onOpenGoal: {}
                )
                BlockMenu(block: blocks[0], day: 0, actions: .preview, onEdit: {}, onGive: {})
                GoalCardMenu(goal: Fixtures.goals[0], actions: GoalCardActions(plan: { _ in }, updateStatus: { _ in }, edit: { _ in }, delete: { _ in }), onOpen: {})
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background),
            width: 720, height: 480
        )
    }

    /// A right-click near the window's bottom right corner opens the menu up and to the left of the pointer.
    func testRightClickMenuStaysInTheWindow() {
        let center = OverlayCenter()
        let task = Fixtures.tasks[2]
        center.showMenu(at: CGPoint(x: 380, y: 300), owner: task.id) {
            TaskMenu(
                task: task, horizon: task.horizon(today: "2026-11-18"), today: "2026-11-18",
                thisWeek: "2026-11-16", nextWeek: "2026-11-23", actions: TaskActions()
            )
        }
        assertAppearances(
            Theme.background.overlayHost(center),
            width: 400, height: 320
        )
    }

    /// "Plan for a day" open beside a task's menu, its first row level with the row it came from.
    func testRightClickSubmenu() {
        let center = OverlayCenter()
        let task = Fixtures.tasks[2]
        center.showMenu(at: CGPoint(x: 20, y: 20), owner: task.id) {
            TaskMenu(
                task: task, horizon: task.horizon(today: "2026-11-18"), today: "2026-11-18",
                thisWeek: "2026-11-16", nextWeek: "2026-11-23", actions: TaskActions()
            )
        }
        // Below the panel's padding, Mark done, a separator, and two moves.
        let row = CGRect(x: 28, y: 22 + 6 + 36 + 9 + 36 + 36, width: 204, height: 36)
        center.showSubmenu(id: "Plan for a day", row: row, content: AnyView(
            DayMenu(kind: .plan, value: nil, today: "2026-11-18", week: task.plannedWeek, onWeek: { _ in }) { _ in }
        ))
        assertAppearances(Theme.background.overlayHost(center), width: 520, height: 520)
    }

    func testConnectionsPage() {
        assertAppearances(
            ConnectionsPage(items: Fixtures.connections, notice: .connected("Linear"))
                .background(Theme.background),
            width: 900, height: 620
        )
    }

    func testConnectionMenuAndDialog() {
        assertAppearances(
            HStack(alignment: .top, spacing: 24) {
                MenuPanel {
                    MenuItem(icon: .refresh, title: "Reconnect") {}
                    MenuItem(icon: .unlink, title: "Disconnect", isDestructive: true) {}
                }
                ConfirmDialog(
                    title: "Disconnect Linear?",
                    message: "Supervibes will stop reading from Linear. Goal sources that use it will be removed, so progress reads won’t look there anymore. You can connect it again anytime.",
                    confirmTitle: "Disconnect"
                )
            }
            .padding(32)
            .background(Theme.shell),
            width: 700, height: 320
        )
    }

    func testGoalsHome() {
        assertAppearances(
            GoalsHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                      actions: GoalCardActions(setObjective: { _ in }))
                .background(Theme.background),
            width: 1180, height: 900
        )
    }

    func testGoalsHomeEmpty() {
        assertAppearances(
            GoalsHome(firstName: "Javier", goals: [], today: "2026-11-18").background(Theme.background),
            width: 900, height: 760
        )
    }

    func testGoalDialog() {
        assertAppearances(
            GoalDialog(
                input: GoalInput(title: "Run a half marathon", description: "Finish under two hours.",
                                 targetDate: "2027-04-12", icon: "Rocket01Icon", color: "sky"),
                today: "2026-11-18"
            )
            .padding(24)
            .background(Theme.shell),
            width: 528, height: 688
        )
    }

    func testGoalPage() {
        assertAppearances(
            GoalPage(detail: Fixtures.goalDetail, now: now).background(Theme.background),
            width: 900, height: 880
        )
    }

    func testTasksSection() {
        assertAppearances(
            TasksSection(
                tasks: Fixtures.tasks, suggestions: Fixtures.suggestions, hasRead: true, reading: false,
                clock: .twelveHour, today: "2026-11-18", now: now
            )
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background),
            width: 832, height: 1320
        )
    }

    /// The planning board in the window's overlay layer, with Show completed as given.
    private func board(_ board: PlanningBoard, showsCompleted: Bool = false) -> some View {
        let defaults = UserDefaults(suiteName: "SurfaceSnapshotTests.board")!
        defaults.set(showsCompleted, forKey: "planningBoard.showsCompleted")
        return board.background(Theme.background).overlayHost(OverlayCenter()).defaultAppStorage(defaults)
    }

    func testPlanningBoard() {
        // The pointer over Unplanned, showing its add button.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initiallyHovered: .unplanned, onBack: {})),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardWithOpenCard() {
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initiallyOpen: "t5", onBack: {})),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardShowingCompleted() {
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, onBack: {}), showsCompleted: true),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardDayCapacity() {
        // Today: over capacity, one block gone by and one ahead.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initialCapacity: .day("2026-11-18"), onBack: {})),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardAllGoals() {
        // Every goal a row, Build Supervibes open to its cards; the rest folded to their rings.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, now: now, initiallyExpanded: ["1"])),
            width: 1500, height: 1000
        )
    }

    func testPlanningBoardAllGoalsFolded() {
        // Every row folded: the week across goals at a glance, with each column's total.
        assertAppearances(board(PlanningBoard(data: Fixtures.board, now: now)), width: 1500, height: 760)
    }

    func testPlanningBoardAllGoalsDayCapacity() {
        // The housing playbook open, its tomorrow over: 3 h planned in a 1 h 30 min session.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, now: now, initialCapacity: .day("2026-11-19"), initiallyExpanded: ["3"])),
            width: 1500, height: 1000
        )
    }

    func testPlanWindow() {
        // The whole window, with Plan on the rail: the board on All goals.
        let defaults = UserDefaults(suiteName: "SurfaceSnapshotTests.board")!
        defaults.set(false, forKey: "planningBoard.showsCompleted")
        return assertAppearances(
            HStack(spacing: 0) {
                Rail(active: .plan, account: nil, topInset: 28)
                AppWindowFrame { PlanningBoard(data: Fixtures.board, now: now) }
            }
            .background(Theme.shell)
            .overlayHost(OverlayCenter())
            .defaultAppStorage(defaults),
            width: 1620, height: 1016
        )
    }

    /// The panel an over day's ring opens, built as the board builds it.
    private func fitPanel(_ goalId: String, day: String, dayName: String, label: String, mode: MakeItFitPanel.Mode = .move) -> some View {
        let data = Fixtures.board
        let goal = data.goal(goalId)!
        let capacity = Capacity.day(day, open: goal.tasks.filter { $0.plannedFor == day }.reduce(0) { $0 + $1.minutes }, blocks: goal.protectedBlocks, now: now)
        let free = Fit.freeSlots(for: goal, day: day, in: data, now: now).map { FitSource(give: nil, goalTitle: nil, goalColor: nil, slot: $0) }
        let given = Fit.gives(to: goal, day: day, in: data, now: now).map { give in
            FitSource(give: give, goalTitle: data.goal(give.fromGoal)!.title, goalColor: data.goal(give.fromGoal)!.color, slot: give.slot)
        }
        return MakeItFitPanel(
            label: label, dayName: dayName, capacity: capacity, color: goal.color,
            moves: Fit.moves(goal, day: day, today: data.today, now: now), sources: free + given,
            today: data.today, clock: .device, initialMode: mode, onMove: { _ in }, onProtect: { _ in }
        )
        .padding(24)
        .background(Theme.background)
    }

    func testMakeItFitMovingTasksOut() {
        // Build Supervibes today, 2 h over: the rebuild goes to Saturday, which has 5 h.
        assertAppearances(fitPanel("1", day: "2026-11-18", dayName: "Today", label: "Today · Wed, Nov 18"), width: 420, height: 400)
    }

    func testMakeItFitProtectingTime() {
        // The same day, keeping the tasks: free time right after its 4 PM session, the evening,
        // then time Superfocus and Jacob's app have to spare.
        assertAppearances(fitPanel("1", day: "2026-11-18", dayName: "Today", label: "Today · Wed, Nov 18", mode: .protect), width: 420, height: 460)
    }

    func testMakeItFitWhenOnlySomeCanMove() {
        // The playbook tomorrow on All goals: the commute map goes to Friday, the interviews fit
        // nowhere, so tomorrow stays 30 min over.
        assertAppearances(
            fitPanel("3", day: "2026-11-19", dayName: "Tomorrow", label: "Tomorrow · Thu, Nov 19 · Deliver research-backed housing playbook for Madrid"),
            width: 420, height: 400
        )
    }

    func testPlanningBoardWeekCapacity() {
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initialCapacity: .thisWeek, onBack: {})),
            width: 1500, height: 760
        )
    }

    func testTasksSectionWithPlanButton() {
        var actions = TaskActions()
        actions.plan = {}
        assertAppearances(
            TasksSection(tasks: [], suggestions: [], hasRead: false, reading: false, clock: .twelveHour, today: "2026-11-18", now: now, actions: actions)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background),
            width: 832, height: 360
        )
    }

    func testTasksSectionWithUnplanned() {
        assertAppearances(
            TasksSection(
                tasks: Fixtures.tasks, suggestions: [], hasRead: false, reading: false,
                clock: .twelveHour, today: "2026-11-18", initiallyShowsUnplanned: true, now: now
            )
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background),
            width: 832, height: 1120
        )
    }

    func testTasksSectionEmpty() {
        assertAppearances(
            TasksSection(tasks: [], suggestions: [], hasRead: false, reading: false, clock: .twelveHour, today: "2026-11-18", now: now)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background),
            width: 832, height: 360
        )
    }

    func testTasksSectionWithOpenTask() {
        assertAppearances(
            TasksSection(
                tasks: Fixtures.tasks, suggestions: [], hasRead: true, reading: false,
                clock: .twentyFourHour, today: "2026-11-18", initiallyOpen: "t1", now: now
            )
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background),
            width: 832, height: 640
        )
    }

    func testNotesSection() {
        assertAppearances(
            NotesSection(notes: Fixtures.notes, author: Fixtures.author, clock: .twelveHour, now: now)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background),
            width: 832, height: 1040
        )
    }

    func testSourcesSection() {
        assertAppearances(
            VStack(spacing: 0) {
                SourcesSection(sources: Fixtures.sources, options: Fixtures.connectionOptions, goal: Fixtures.goals[0])
                SourcesSection(sources: [], options: Fixtures.connectionOptions, goal: Fixtures.goals[0])
                SourcesSection(sources: [], options: [], goal: Fixtures.goals[0])
            }
            .padding(.horizontal, 32)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background),
            width: 832, height: 760
        )
    }

    func testSourceDialog() {
        assertAppearances(
            SourceDialog(goal: Fixtures.goals[0], connection: Fixtures.connectionOptions[0], relation: "", isEditing: false)
                .padding(24)
                .background(Theme.shell),
            width: 528, height: 600
        )
    }

    func testDayTimeline() {
        // 6 AM to 3 PM of the timeline, the way it opens on a morning.
        let top = DayGrid.standard.y(6 * 60)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour)
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.standard.y(15 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.standard.y(15 * 60) - top
        )
    }

    func testDayTimelinePopover() {
        // Protecting 3–4 PM: the draft with the popover under it.
        let top = DayGrid.standard.y(14 * 60)
        let editing = BlockEditing(mode: .create, day: 0, start: 15 * 60, end: 16 * 60, goalId: Fixtures.calendar.goals[0].id, title: nil)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour, editing: .constant(editing))
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.standard.y(18 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.standard.y(18 * 60) - top
        )
    }

    /// Time just drawn, as a task: typing suggests open tasks, those starting with it and in the
    /// chosen goal first.
    func testNewBlockTaskSuggestions() {
        let data = Fixtures.calendar
        assertAppearances(
            NewBlockPopover(
                goals: data.goals, tasks: data.tasks, goalId: data.goals[0].id, kind: .task, title: "re",
                timeLabel: "Today · 12:00–1:00 PM · 1h", onAdd: { _, _, _ in }, onCancel: {}
            )
            .frame(width: 320)
            .padding(24)
            .background(Theme.background),
            width: 368
        )
    }

    func testDayViewWithTasks() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, showsTasks: true, onToggleTasks: {}).background(Theme.background),
            width: 1180, height: 560
        )
    }

    func testBlockPanels() {
        let data = Fixtures.calendar
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.panelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                        openTaskIds: ["t5"], ended: block.endsAt <= now, now: now, actions: nil
                    )
                    .frame(width: 320, height: 640)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 672
        )
    }

    func testFreshBlockPanels() {
        let data = Fixtures.calendar
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.freshPanelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                        openTaskIds: [], ended: block.endsAt <= now, now: now, actions: nil
                    )
                    .frame(width: 320, height: 360)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 392
        )
    }

    func testSessionAndReservedPanels() {
        // With actions, so the rows can be changed and the description offers Tab.
        let data = Fixtures.calendar
        let now = now
        let actions = BlockPanelActions(
            setDescription: { _, _ in nil }, prepareAgenda: { _, _ in nil },
            suggestFocus: { _, _, _ in .failed("") }, prepareRecap: { _ in nil },
            postRecap: { _, _, _, _ in nil }, discardRecap: { _ in nil }, setTaskDone: { _, _ in nil },
            toggleDone: { _ in }, openGoal: { _ in }
        )
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.kindPanelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 13 * 60, end: 14 * 60 + 30, when: "Wednesday, November 18 (today), 1:00–2:30 PM",
                        openTaskIds: [], ended: false, now: now, actions: actions, calendar: .preview
                    )
                    .frame(width: 320, height: 360)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 688, height: 392
        )
    }

    func testMenuBarDuringReservedTime() {
        // Reserved time shows what it is and when it ends, with no aim to set or plan to follow.
        let lunch = Block(id: "lunch", title: "Lunch with family", goal: "Run a calm week",
                          start: now.addingTimeInterval(-20 * 60), end: now.addingTimeInterval(40 * 60), tint: Fixtures.pink, reserved: true)
        assertAppearances(
            MenuBarContent(current: lunch, upcoming: Fixtures.upcoming(at: now), now: now, sessionActions: nil),
            width: 300
        )
    }

    /// A suggested focus, standing in the empty description until it's taken or set aside.
    func testFocusSuggestion() {
        let data = Fixtures.calendar
        let block = Fixtures.freshPanelBlocks.first { $0.title == nil && $0.description == nil && !$0.isIntention && !$0.reserved }!
        let actions = BlockPanelActions(
            setDescription: { _, _ in nil }, prepareAgenda: { _, _ in nil },
            suggestFocus: { _, _, _ in .failed("") }, prepareRecap: { _ in nil },
            postRecap: { _, _, _, _ in nil }, discardRecap: { _ in nil }, setTaskDone: { _, _ in nil },
            toggleDone: { _ in }, openGoal: { _ in }
        )
        assertAppearances(
            BlockPanel(
                block: block, goal: data.goal(block.goalId), goals: data.goals, description: nil,
                day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                openTaskIds: [], ended: false, now: now, actions: actions, calendar: .preview, suggestion: Fixtures.focusSuggestion
            )
            .frame(width: 320, height: 400)
            .padding(16)
            .background(Theme.background),
            width: 352, height: 432
        )
    }

    func testWeekView() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, span: .week, onSetSpan: { _ in },
                    showsOverview: true, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testWeekFromThursday() {
        // Scrolled to start on a Thursday: the title runs Thursday to Wednesday, and the overview
        // keeps to the Monday-to-Sunday week holding most of those days.
        let thursday = CalendarDayMath.monday(of: 0, from: now) + 3
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: thursday, onScroll: { _ in },
                    span: .week, onSetSpan: { _ in }, showsOverview: true, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testThreeDaysFromToday() {
        // Wednesday to Friday, today first: "Nov 18–20 · From today", and columns roomy enough for
        // the day's block cards.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(3), onSetSpan: { _ in }, showsOverview: false, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testFiveDaysFromToday() {
        // Wednesday to Sunday, with the week's overview beside them.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(5), dayCount: 5, onSetSpan: { _ in }, showsOverview: true, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testSevenDaysFromToday() {
        // Wednesday to Tuesday, across the end of the week; the overview keeps to the Monday-to-Sunday
        // week holding the middle day (Saturday's, Nov 16–22).
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(7), dayCount: 7, onSetSpan: { _ in }, showsOverview: true, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testThreeDaysScrolledOn() {
        // Scrolled two days on: Friday to Sunday, no "From today", and Today shows.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 2, now: now, first: 2, onScroll: { _ in },
                    span: .days(3), onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 120
        )
    }

    func testThreeDaysPopover() {
        // Time drawn on the last of three columns: no room to its right, so the popover opens left.
        let top = WeekGrid.standard.y(9 * 60)
        let editing = BlockEditing(mode: .create, day: 2, start: 10 * 60, end: 11 * 60, goalId: Fixtures.calendar.goals[0].id, title: nil)
        assertAppearances(
            WeekView(data: Fixtures.calendar, first: 0, count: 3, now: now, clock: .twelveHour, creating: .constant(editing), scrolls: false)
                .frame(width: 1100, height: 260 + WeekGrid.standard.height)
                .offset(y: -top)
                .frame(width: 1100, height: WeekGrid.standard.y(14 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.background),
            width: 1100, height: WeekGrid.standard.y(14 * 60) - top
        )
    }

    func testCalendarDaysMenu() {
        // The switch's chevron: Next 3, 5 or 7 days, the one showing ticked.
        assertAppearances(
            DaysMenu(selected: 5) { _ in }.padding(16).background(Theme.background),
            width: 232
        )
    }

    func testCalendarViewCard() {
        assertAppearances(
            CalendarViewCard(span: .days(5)).padding(16).background(Theme.background),
            width: 800
        )
    }

    func testWeekGridMorning() {
        // 7 AM to 6 PM: the week's blocks, today's under way, the now line.
        let top = WeekGrid.standard.y(7 * 60)
        assertAppearances(
            WeekView(data: Fixtures.calendar, first: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
                .frame(width: 1100, height: 260 + WeekGrid.standard.height)
                .offset(y: -top)
                .frame(width: 1100, height: WeekGrid.standard.y(18 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.background),
            width: 1100, height: WeekGrid.standard.y(18 * 60) - top
        )
    }

    func testDayViewTop() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now).background(Theme.background),
            width: 900, height: 360
        )
    }

    func testTrajectoryHoverCard() {
        let days = Fixtures.goals[1].trajectory
        assertAppearances(
            VStack(spacing: 0) {
                TrajectoryDays(days: days, today: "2026-11-18", hovered: 20)
                TrajectoryDays(days: days, today: "2026-11-18", hovered: 1).padding(.top, 110)
                TrajectoryDays(days: days, today: "2026-11-18", hovered: 27).padding(.top, 110)
            }
            .padding(.horizontal, 24)
            .padding(.top, 100)
            .padding(.bottom, 16)
            .background(Theme.card),
            width: 640, height: 400
        )
    }

    func testNewGoalDialogEmpty() {
        assertAppearances(
            GoalDialog(input: GoalInput(), today: "2026-11-18").padding(24).background(Theme.shell),
            width: 528, height: 688
        )
    }

    func testGoalPageFirstRead() {
        var detail = Fixtures.goalDetail
        detail = GoalDetail(
            goal: detail.goal, today: detail.today, read: nil, status: nil, readsInTrajectory: 0,
            readPending: true, readError: nil, canRead: true,
            week: .init(start: "2026-11-16", objective: nil, lastWeek: "Get sign-in working in the Mac app.")
        )
        assertAppearances(GoalPage(detail: detail, now: now).background(Theme.background), width: 900, height: 760)
    }

    func testSignIn() {
        assertAppearances(SignInView(), width: 640, height: 360)
    }

    func testSignInWithMessage() {
        assertAppearances(
            SignInView(message: "This Google account isn't on the access list."),
            width: 640, height: 360
        )
    }

    func testWidgetSmall() {
        assertAppearances(
            CurrentBlockWidgetPreview(block: Fixtures.current(at: now), now: now),
            width: 170, height: 170
        )
    }

    /// Between blocks, and before the app has shared anything.
    func testWidgetFreeAndSignedOut() {
        let between = now.addingTimeInterval(50 * 60)
        assertAppearances(
            HStack(spacing: 12) {
                CurrentBlockWidgetPreview(block: nil, now: between, next: Fixtures.upcoming(at: now).first)
                    .frame(width: 170, height: 170)
                CurrentBlockWidgetPreview(block: nil, now: now, signedIn: false)
                    .frame(width: 170, height: 170)
            },
            width: 352, height: 170
        )
    }

    /// The widget's timeline: a block shows the moment it starts, and between blocks it says what's next.
    func testWidgetTimeline() {
        let blocks = Fixtures.blocks(around: now)
        let moments = WidgetTimeline.moments(blocks: blocks, from: now)
        XCTAssertEqual(moments.first?.date, now)
        XCTAssertEqual(moments.first?.current?.id, "current")
        // Every minute for the next hour, plus each later start and end within the day.
        XCTAssertTrue(moments.contains { $0.date == blocks[2].start && $0.current?.id == "later" })
        let afterCurrent = moments.first { $0.date == blocks[0].end }
        XCTAssertNil(afterCurrent?.current)
        XCTAssertEqual(afterCurrent?.next?.id, "next")
        XCTAssertEqual(moments.map(\.date), moments.map(\.date).sorted())
        XCTAssertEqual(moments.last?.date, blocks[2].end)
        XCTAssertNil(moments.last?.current)
        XCTAssertNil(moments.last?.next)
    }

    /// What the app writes, the widget reads back the same.
    func testSharedTodayRoundTrip() throws {
        let today = SharedToday(signedIn: true, fetchedAt: now, blocks: Fixtures.blocks(around: now))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(SharedToday.self, from: encoder.encode(today))
        XCTAssertEqual(back.blocks.map(\.id), today.blocks.map(\.id))
        XCTAssertEqual(back.blocks.first?.tint, today.blocks.first?.tint)
    }
}

/// Approximates the widget's frame for snapshots; WidgetKit itself only renders inside a widget host.
private struct CurrentBlockWidgetPreview: View {
    let block: Block?
    let now: Date
    var next: Block?
    var signedIn = true

    var body: some View {
        Group {
            if let block { CurrentBlockView(block: block, now: now) } else { NoBlockView(next: next, signedIn: signedIn) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension XCTestCase {
    /// Snapshots `view` once per appearance, named `<test>.light.png` and `<test>.dark.png`.
    /// Height defaults to whatever the view needs at `width`.
    @MainActor
    func assertAppearances<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        Self.prepareFonts()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingController(
                rootView: view
                    .environment(\.staticRendering, true)
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            host.view.appearance = NSAppearance(named: appearance)
            let fitting = host.sizeThatFits(in: CGSize(width: width, height: height ?? 2000))
            let size = CGSize(width: width, height: height ?? ceil(fitting.height))
            host.view.frame = CGRect(origin: .zero, size: size)
            settleLayout(host.view)
            assertSnapshot(of: host, as: .image(size: size), named: name, file: file, testName: testName, line: line)
        }
    }

    @MainActor private static var fontsReady = false

    /// AppKit-backed controls, like an empty multi-line TextField, take their height from the font
    /// as AppKit sees it. The bundled font registers on first use, and AppKit only picks it up on a
    /// later turn of the run loop, so a field measured before that got the system font's line
    /// height, and everything below it moved from run to run. So the font is registered before
    /// any view is measured, with a moment for AppKit to catch up.
    @MainActor private static func prepareFonts() {
        guard !fontsReady else { return }
        fontsReady = true
        Fonts.registerOnce()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    /// Lets a view finish laying out before it's drawn; AppKit-backed controls settle their size on a later pass.
    @MainActor private func settleLayout(_ view: NSView) {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        view.layoutSubtreeIfNeeded()
    }
}
