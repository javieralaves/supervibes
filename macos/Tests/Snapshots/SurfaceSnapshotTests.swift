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
                usage: UsageSummary(calls: Fixtures.usageCalls, today: now)
            )
            .background(Theme.background),
            width: 900, height: 2600
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
            GoalsHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18")
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
            width: 832, height: 820
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
                        block: block, goal: data.goal(block.goalId), timeLabel: "Today · 3:00–4:30 PM",
                        when: "Wednesday, November 18 (today), 3:00–4:30 PM", openTaskIds: ["t5"],
                        ended: block.endsAt <= now, now: now, actions: nil
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
                        block: block, goal: data.goal(block.goalId), timeLabel: "Today · 3:00–4:30 PM",
                        when: "Wednesday, November 18 (today), 3:00–4:30 PM", openTaskIds: [],
                        ended: block.endsAt <= now, now: now, actions: nil
                    )
                    .frame(width: 320, height: 260)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 292
        )
    }

    func testFocusSuggestion() {
        assertAppearances(
            FocusSuggestionCard(suggestion: Fixtures.focusSuggestion, onUse: {}, onAnother: {}, onDismiss: {})
                .padding(16)
                .background(Theme.card),
            width: 320, height: 180
        )
    }

    func testWeekView() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, isWeek: true, onSetWeek: { _ in },
                    showsOverview: true, onToggleOverview: {})
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testWeekGridMorning() {
        // 7 AM to 6 PM: the week's blocks, today's under way, the now line.
        let top = WeekGrid.standard.y(7 * 60)
        assertAppearances(
            WeekView(data: Fixtures.calendar, monday: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
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
            assertSnapshot(of: host, as: .image(size: size), named: name, file: file, testName: testName, line: line)
        }
    }
}
