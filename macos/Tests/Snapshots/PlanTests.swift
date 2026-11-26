import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The Plan board and Make it fit.
@MainActor
final class PlanTests: XCTestCase {
    private let now = Fixtures.referenceNow

    /// The planning board in the window's overlay layer, with Show completed as given.
    private func board(_ board: PlanningBoard, showsCompleted: Bool = false) -> some View {
        let defaults = UserDefaults(suiteName: "PlanTests.board")!
        defaults.set(showsCompleted, forKey: "planningBoard.showsCompleted")
        return board.background(Theme.background).overlayHost(OverlayCenter()).defaultAppStorage(defaults)
    }

    /// The housing playbook with an hour planned today and no session for it.
    private var boardWithNoTime: BoardData {
        var data = Fixtures.board
        let index = data.goals.firstIndex { $0.id == "3" }!
        data.goals[index].tasks.append(TaskItem(id: "no-time", title: "Call the agency about deposits", minutes: 60, plannedFor: "2026-11-18"))
        return data
    }

    /// The panel an over day's ring opens, built as the board builds it.
    private func fitPanel(_ goalId: String, day: String, dayName: String, label: String, mode: MakeItFitPanel.Mode = .move, applied: Set<String> = []) -> some View {
        let data = Fixtures.board
        return MakeItFitPanel(
            goal: data.goal(goalId)!, day: day, dayName: dayName, in: data, now: now, clock: .device,
            initialMode: mode, applied: applied, actions: BoardFitActions()
        )
        .padding(24)
        .background(Theme.background)
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

    func testPlanningBoardDropBetweenCards() {
        // Explore a lock screen widget dragged from Unplanned into today, between its two cards:
        // faded where it was, a line where it'd go.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now,
                                initialDrop: BoardDrop(task: "t9", column: .day("2026-11-18"), before: "t2"), onBack: {})),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardDropAtEnd() {
        // Today's first card dragged to the end of This week: the line under its last card.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now,
                                initialDrop: BoardDrop(task: "t1", column: .thisWeek, before: nil), onBack: {})),
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

    func testPlanningBoardAllGoalsNoTime() {
        // Time planned with none protected is over: the cell amber, "1 h, no time".
        assertAppearances(board(PlanningBoard(data: boardWithNoTime, now: now)), width: 1500, height: 760)
    }

    func testPlanningBoardAllGoalsNoTimeCapacity() {
        // Its lane open: the chip amber, its popover on "No time protected".
        assertAppearances(
            board(PlanningBoard(data: boardWithNoTime, now: now, initialCapacity: .day("2026-11-18"), initiallyExpanded: ["3"])),
            width: 1500, height: 1000
        )
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
        let defaults = UserDefaults(suiteName: "PlanTests.board")!
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

    /// Superfocus today from the Day view's strip, its first move already applied: "Moved", and the
    /// ring and totals counting it.
    func testDayMakeItFit() {
        let data = Fixtures.dayByGoal.board(now: now)
        assertAppearances(
            MakeItFitPanel(
                goal: data.goal("superfocus")!, day: "2026-11-18", dayName: "Today", in: data, now: now, clock: .twelveHour,
                applied: ["sf-focus"], actions: BoardFitActions()
            )
            .padding(24)
            .background(Theme.background),
            width: 420, height: 420
        )
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

    func testPlanningBoardTimeLeft() {
        // Friday has 1 h 30 min left: what would fit, the week's first, the pointer over one.
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initiallyHoveredFiller: "t5", onBack: {})),
            width: 1500, height: 760
        )
    }

    func testPlanningBoardWeekCapacity() {
        assertAppearances(
            board(PlanningBoard(data: Fixtures.board, scope: .goal("1"), now: now, initialCapacity: .thisWeek, onBack: {})),
            width: 1500, height: 760
        )
    }
}
