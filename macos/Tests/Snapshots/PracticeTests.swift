import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Practices: Life with its Practices section, a practice's page (scheduled, with nothing planned, and paused), the
/// dialog that starts one, and an area that holds them. Wednesday, Nov 18, as every fixture.
@MainActor
final class PracticeTests: XCTestCase {
    private let now = Fixtures.referenceNow
    private let areaActions = AreaEditActions(create: { _ in true }, update: { _, _ in }, remove: { _ in })
    private let areaPageActions = AreaPageActions(save: { _ in true }, remove: {}, takeOut: { _ in }, moveIn: { _ in }, newGoal: { _ in })

    /// Projects, then practices (round badges, rhythm, this week's pips), then areas counting both.
    func testLifeWithPractices() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.lifeWithPractices, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     areas: Fixtures.practiceAreas, now: now, actions: GoalCardActions(setObjective: { _ in }),
                     areaActions: areaActions)
                .background(Theme.background),
            width: 1180, height: 1500
        )
    }

    /// Workouts on Wednesday: Monday's done, Tuesday's didn't happen, two planned; 8 of the last 12, at risk.
    func testPracticePage() {
        assertAppearances(
            PracticePage(detail: Fixtures.practiceDetail).background(Theme.background),
            width: 900, height: 1180
        )
    }

    /// No days set: Monday's logged, two to go any day, and what that means under the week.
    func testPracticePageUnplanned() {
        assertAppearances(
            PracticePage(detail: Fixtures.unplannedPracticeDetail).background(Theme.background),
            width: 900, height: 1180
        )
    }

    /// Paused until Nov 30: Resume now in place of Log one, the week dimmed, no status.
    func testPracticePagePaused() {
        assertAppearances(
            PracticePage(detail: Fixtures.pausedPracticeDetail).background(Theme.background),
            width: 900, height: 1180
        )
    }

    /// New, with Practice picked: how often, how long, its area and recaps; no target date.
    func testNewPracticeDialog() {
        assertAppearances(
            GoalDialog(
                input: GoalInput(kind: .practice, title: "Read before bed", icon: "Book02Icon", color: "slate",
                                 areaId: "rest", perWeek: 4, minMinutes: 20),
                today: "2026-11-18",
                areas: Fixtures.areas
            )
            .padding(24)
            .background(Theme.shell),
            width: 528, height: 688
        )
    }

    /// Health: no projects, said in one line, then its two practices.
    func testAreaPageWithPractices() {
        assertAppearances(
            AreaPage(detail: Fixtures.practiceAreaDetail, actions: areaPageActions, now: now).background(Theme.background),
            width: 900, height: 1120
        )
    }

    func testPipsFollowTheWeek() {
        let practice = Practice(perWeek: 3, week: .init(start: "2026-11-16", done: 1, planned: 1))
        XCTAssertEqual(practice.pips, [.done, .planned, .empty])
        XCTAssertEqual(practice.left, 2)
        // More than meant: every session shows, none is lost.
        let busy = Practice(perWeek: 2, week: .init(start: "2026-11-16", done: 3, planned: 0))
        XCTAssertEqual(busy.pips, [.done, .done, .done])
        XCTAssertEqual(busy.left, 0)
        XCTAssertEqual(Practice.rhythm(1), "Once a week")
        XCTAssertEqual(Practice.rhythm(4), "4 times a week")
    }

    func testAPracticeNeedsARhythm() {
        XCTAssertEqual(GoalInput(kind: .practice, title: "Walk", perWeek: 0).problem, "Pick between once and 14 times a week.")
        XCTAssertNil(GoalInput(kind: .practice, title: "Walk", perWeek: 5).problem)
        XCTAssertEqual(GoalInput(kind: .practice).problem, "Give your practice a name.")
    }
}
