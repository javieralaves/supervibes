import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Settings, Connections, the rail and its menus, and right-click menus.
@MainActor
final class SettingsTests: XCTestCase {
    private let now = Fixtures.referenceNow

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

    func testCalendarEventsCard() {
        let calendars = [
            ExternalCalendar(id: "work", title: "Work"),
            ExternalCalendar(id: "personal", title: "Personal"),
            ExternalCalendar(id: "holidays", title: "Holidays in Spain"),
        ]
        let picked = EventImportSettings(calendarIds: ["work", "personal"], goalId: "g1")
        let goals = Fixtures.calendar.goals
        assertAppearances(
            VStack(spacing: 12) {
                CalendarEventsCard(settings: .defaults, access: .notAsked, calendars: [], goals: goals)
                CalendarEventsCard(settings: picked, access: .allowed, calendars: calendars, goals: goals)
                CalendarEventsCard(settings: .defaults, access: .allowed, calendars: [], goals: goals)
                CalendarEventsCard(settings: picked, access: .denied, calendars: [], goals: goals)
            }
            .padding(32)
            .background(Theme.background),
            width: 768, height: 1340
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
            width: 900, height: 720
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
}
