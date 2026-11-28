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

    private func plate(text: String, dictation: DictationState) -> some View {
        FirstRunView(state: Fixtures.firstRun(.plate, text: text), plateText: .constant(text), dictation: dictation)
            .padding(.top, 20).background(Theme.background)
    }

    /// Saying it: what's settled in the plate's text, what's still being said after it muted, the lit mic and the
    /// waveform, quiet as dots and speech as bars.
    func testPlateListening() {
        let levels: [Float] = [0, 0, 0.02, 0, 0.3, 0.55, 0.42, 0.1, 0.05, 0.6, 0.85, 0.7, 0.35, 0, 0.02, 0.4, 0.65, 0.9, 0.5, 0.2,
                               0, 0, 0.3, 0.45, 0.75, 0.6, 0.15, 0.05, 0.5, 0.8, 0.95, 0.7, 0.4, 0.1, 0, 0.25, 0.5, 0.3, 0.6, 0.45]
        let dictation = DictationState(phase: .listening, levels: levels, volatile: "and I keep meaning to call the bank about the mortgage")
        assertAppearances(plate(text: "pricing page launch, needs to ship before Q1 planning. Hiring a product designer,", dictation: dictation),
                          width: 1280, height: 820)
    }

    /// The first time: getting the speech model ready before it can listen.
    func testPlatePreparing() {
        assertAppearances(plate(text: "", dictation: DictationState(phase: .preparing)), width: 1280, height: 820)
    }

    /// The microphone not allowed: why, beside Say it instead.
    func testPlateDictationError() {
        let dictation = DictationState(error: "Supervibes needs the microphone to listen. Allow it in System Settings, under Privacy & Security, Microphone.")
        assertAppearances(plate(text: "", dictation: dictation), width: 1280, height: 820)
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

    /// Buttons while they load: the spinner takes the label's place and the button keeps its width.
    func testLoadingButtons() {
        assertAppearances(
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    FlowButton(title: "Sort it", primary: true, action: {})
                    FlowButton(title: "Sort it", primary: true, isBusy: true, action: {})
                    FlowButton(title: "Read again", action: {})
                    FlowButton(title: "Read again", isBusy: true, action: {})
                }
                HStack(spacing: 12) {
                    PrimaryButton(title: "Add area", action: {})
                    PrimaryButton(title: "Add area", isBusy: true, action: {})
                }
            }
            .padding(32).frame(maxWidth: .infinity, alignment: .leading).background(Theme.background),
            width: 640, height: 180
        )
    }
}
