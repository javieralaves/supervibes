import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Route 3, step back first, as Alex goes through it: areas, where Health stands, the gaps as quests, what moves each,
/// the season, then the week with its quests.
@MainActor
final class FirstRunStepBackTests: XCTestCase {
    private func window(_ state: SeasonSetupState, isStarted: Bool = false) -> some View {
        FirstRunStepBack(state: state, isStarted: isStarted).padding(.top, 20).background(Theme.background)
    }

    /// Their six areas and every usual one they lack, worth a look: Play left out, Relationships picked.
    func testStepBackAreas() {
        assertAppearances(window(Fixtures.stepBackPick), width: 1280, height: 820)
    }

    /// Health, 4 of 6: where it is, where they want it, and the gap named, with Run setting off along its track.
    func testStepBackStand() {
        assertAppearances(window(Fixtures.stepBackStand), width: 1280, height: 820)
    }

    /// Relationships, nothing said yet: the gap still to come, Name the gap off.
    func testStepBackStandEmpty() {
        assertAppearances(window(Fixtures.stepBackStandEmpty), width: 1280, height: 820)
    }

    /// Six gaps as quests, three chosen.
    func testStepBackQuests() {
        assertAppearances(window(Fixtures.stepBackQuests), width: 1280, height: 820)
    }

    /// What moves each: Run and the move from the plate, Friends' evening suggested and marked New.
    func testStepBackMoves() {
        assertAppearances(window(Fixtures.stepBackMoves), width: 1280, height: 820)
    }

    /// The season: three gaps' quests fanned, each set off by what moves it, the rest of the plate keeping going.
    func testStepBackSeason() {
        assertAppearances(window(Fixtures.stepBackReview), width: 1280, height: 820)
    }

    /// The week: quests named for their gaps first on the plate, everything else still there.
    func testStepBackWeek() {
        var plan = Fixtures.weekAnswered(blocks: [Fixtures.weekPricingSession])
        plan.quests = [
            WeekQuest(number: 1, title: "A steady running rhythm", goalIds: ["run"]),
            WeekQuest(number: 2, title: "Settled in a new flat", goalIds: ["move"]),
        ]
        plan.steps = FirstRunChoice.stepBack.steps
        assertAppearances(FirstRunWeek(plan: plan).padding(.top, 28).background(Theme.background), width: 1280, height: 820)
    }
}
