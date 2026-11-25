import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Practices on the calendar: a practice's block panel before, after and when it didn't happen; and the menu that
/// lists projects and practices apart. Wednesday, Nov 18, as every fixture.
@MainActor
final class PracticeCalendarTests: XCTestCase {
    private let now = Fixtures.referenceNow

    /// This evening's workout (still to come), this morning's (counted, with Didn't happen), and yesterday's (didn't
    /// happen, with It happened after all). No agenda or focus help, and no task type.
    func testPracticeBlockPanels() {
        let goals = Fixtures.practiceCalendarGoals
        let actions = BlockPanelActions(
            setDescription: { _, _ in nil }, prepareAgenda: { _, _ in nil },
            suggestFocus: { _, _, _ in .failed("") }, prepareRecap: { _ in nil },
            postRecap: { _, _, _, _ in nil }, discardRecap: { _ in nil }, setTaskDone: { _, _ in nil },
            toggleDone: { _ in }, openGoal: { _ in }
        )
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.practicePanelBlocks) { block in
                    let midnight = Calendar.current.startOfDay(for: block.startsAt)
                    let day = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: midnight).day ?? 0
                    BlockPanel(
                        block: block, goal: goals.first { $0.id == block.goalId }, goals: goals, description: nil,
                        day: day, start: Int(block.startsAt.timeIntervalSince(midnight) / 60), end: Int(block.endsAt.timeIntervalSince(midnight) / 60),
                        when: "Wednesday, November 18 (today)",
                        openTaskIds: [], ended: block.endsAt <= now, now: now, actions: actions, calendar: .preview
                    )
                    .frame(width: 320, height: 520)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 552
        )
    }

    /// What a block can be for: projects, then practices with how often.
    func testGoalMenuWithPractices() {
        assertAppearances(
            GoalMenu(goals: Fixtures.practiceCalendarGoals, selected: "w") { _ in }.padding(24).background(Theme.shell),
            width: 336
        )
    }

    func testGoalSections() {
        let sections = GoalSections(Fixtures.practiceCalendarGoals).sections
        XCTAssertEqual(sections.map(\.title), ["Projects", "Practices"])
        XCTAssertEqual(sections[1].goals.map(\.id), ["w", "t"])
        XCTAssertEqual(GoalSections(Fixtures.calendar.goals).sections.map(\.title), ["Projects"])
    }
}
