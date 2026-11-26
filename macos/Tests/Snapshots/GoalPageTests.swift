import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// A project's page and its sections, and the project dialogs.
@MainActor
final class GoalPageTests: XCTestCase {
    private let now = Fixtures.referenceNow

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

    /// A goal with no area: a dashed "Add to an area" after its target date.
    func testGoalPageNoArea() {
        assertAppearances(
            GoalPage(detail: Fixtures.goalDetail, now: now, areas: Fixtures.areas, onSetArea: { _ in }, onNewArea: {}) { EmptyView() }
                .background(Theme.background),
            width: 900, height: 880
        )
    }

    /// Edit goal with the person's areas: an Area field before the target date.
    func testGoalDialogWithArea() {
        assertAppearances(
            GoalDialog(
                input: GoalInput(title: "Deliver research-backed housing playbook for Madrid", targetDate: "2026-11-30",
                                 icon: "Target02Icon", color: "coral", areaId: "madrid"),
                mode: .edit,
                today: "2026-11-18",
                areas: Fixtures.areas
            )
            .padding(24)
            .background(Theme.shell),
            width: 528
        )
    }

    /// A goal in an area: the area leads the line under the title, before the target date.
    func testGoalPageInArea() {
        var detail = Fixtures.goalDetail
        detail.area = AreaRef(id: "work", name: "Work", icon: "LaptopIcon")
        assertAppearances(
            GoalPage(detail: detail, now: now).background(Theme.background),
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
}
