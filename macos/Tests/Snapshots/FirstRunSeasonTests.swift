import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Route 2, the next few months, as Alex goes through it: the Focus board, the season it makes, then the week with
/// quests.
@MainActor
final class FirstRunSeasonTests: XCTestCase {
    private func window(_ step: FirstRunStep, board: FocusBoard, error: String? = nil) -> some View {
        var state = Fixtures.firstRun(step)
        state.route = .season
        state.board = board
        state.error = error
        return FirstRunView(state: state, plateText: .constant("")).padding(.top, 20).background(Theme.background)
    }

    /// Nothing chosen yet: three empty slots, the whole plate below, Continue off.
    func testFocusEmpty() {
        assertAppearances(window(.focus, board: Fixtures.focusBoard()), width: 1280, height: 820)
    }

    /// One chosen, the pricing page: two slots left, the rest keeping going.
    func testFocusOneChosen() {
        assertAppearances(window(.focus, board: Fixtures.focusBoard(focus: ["pricing"])), width: 1280, height: 820)
    }

    /// Three chosen, three waiting for next season.
    func testFocusThreeChosen() {
        let board = Fixtures.focusBoard(focus: ["pricing", "move", "run"], waiting: ["spanish", "newsletter", "lisbon"])
        assertAppearances(window(.focus, board: board), width: 1280, height: 820)
    }

    /// The season: three quest cards fanned, Start your season, and what else still gets time or waits.
    func testSeason() {
        let board = Fixtures.focusBoard(focus: ["pricing", "move", "run"], waiting: ["spanish", "newsletter", "lisbon"])
        assertAppearances(window(.season, board: board), width: 1280, height: 820)
    }

    /// A season of one, renamed, nothing waiting, and why it couldn't start.
    func testSeasonOfOne() {
        var board = Fixtures.focusBoard(focus: ["move"])
        board.names["move"] = "A home by January"
        assertAppearances(window(.season, board: board, error: "You’re already setting up a season. Pick up where you left off."),
                          width: 1280, height: 820)
    }

    /// The week with a season: the quests first on the plate, each project and practice marked with its quest, what
    /// waits counted at the end, the pricing page's session marked as quest 1.
    func testWeekWithQuests() {
        var plan = Fixtures.weekAnswered(blocks: [Fixtures.weekPricingSession])
        plan.quests = Fixtures.weekQuests
        plan.waiting = ["spanish", "newsletter", "lisbon"]
        plan.steps = FirstRunChoice.season.steps
        assertAppearances(FirstRunWeek(plan: plan).padding(.top, 28).background(Theme.background), width: 1280, height: 820)
    }
}
