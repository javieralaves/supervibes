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
        let top = DayGrid.y(6 * 60)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour)
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.y(15 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.y(15 * 60) - top
        )
    }

    func testDayTimelinePopover() {
        // Protecting 3–4 PM: the draft with the popover under it.
        let top = DayGrid.y(14 * 60)
        let editing = BlockEditing(mode: .create, day: 0, start: 15 * 60, end: 16 * 60, goalId: Fixtures.calendar.goals[0].id, title: nil)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour, editing: .constant(editing))
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.y(18 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.y(18 * 60) - top
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
}

/// Approximates the widget's frame for snapshots; WidgetKit itself only renders inside a widget host.
private struct CurrentBlockWidgetPreview: View {
    let block: Block?
    let now: Date

    var body: some View {
        Group {
            if let block { CurrentBlockView(block: block, now: now) } else { NoBlockView() }
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
