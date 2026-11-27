import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// First run's shared start as Alex goes through it on Thursday, Nov 26: welcome, the plate, sorted, what matters.
@MainActor
final class FirstRunTests: XCTestCase {
    private func window(_ state: FirstRunState) -> some View {
        FirstRunView(state: state, plateText: .constant(state.plateText)).padding(.top, 20).background(Theme.background)
    }

    /// The welcome: the mark, a greeting, a line, the four steps as tiles on a track, Let's go.
    func testWelcome() {
        assertAppearances(window(Fixtures.firstRun(.welcome)), width: 1280, height: 820)
    }

    /// The plate, empty: an example where the first line goes, the prompts beside it, Sort it off.
    func testPlateEmpty() {
        assertAppearances(window(Fixtures.firstRun(.plate, text: "")), width: 1280, height: 820)
    }

    /// The plate, written: nine messy lines, ready to sort.
    func testPlate() {
        assertAppearances(window(Fixtures.firstRun(.plate)), width: 1280, height: 820)
    }

    /// Sorted: six areas, Spanish asking how often, Looks right off until it's said.
    func testSorted() {
        assertAppearances(window(Fixtures.firstRun(.sorted)), width: 1280, height: 820)
    }

    /// What matters with a lot on the plate: what can wait, The next few months suggested.
    func testWhatMattersHeavy() {
        assertAppearances(window(Fixtures.firstRun(.whatMatters)), width: 1280, height: 820)
    }

    /// The way into Your week: why it matters, the next screen in miniature, the three things it asks, Plan my week.
    func testWeekIntro() {
        assertAppearances(
            FirstRunWeekIntro(weekLabel: "Nov 30 – Dec 6", onStart: {}).padding(.top, 28).background(Theme.background),
            width: 1280, height: 820
        )
    }

    /// What matters with three things: what to do with the room, Step back first suggested.
    func testWhatMattersLight() {
        assertAppearances(window(Fixtures.firstRun(.whatMatters, plate: Fixtures.lightPlate)), width: 1280, height: 820)
    }
}
