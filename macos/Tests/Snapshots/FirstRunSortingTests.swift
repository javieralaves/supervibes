import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Between the plate and What matters: the questions before sorting, then changing what was sorted.
@MainActor
final class FirstRunSortingTests: XCTestCase {
    private func clarify(current: Int, picked: [String: Int], more: [String: String] = [:]) -> some View {
        var state = Fixtures.firstRun(.clarify)
        state.clarify = PlateClarify(questions: Fixtures.plateQuestions, current: current, picked: picked, more: more)
        return FirstRunView(state: state, plateText: .constant("")).padding(.top, 20).background(Theme.background)
    }

    /// The first question, answered with a click: Spanish is kept up. The two to come peek out under it.
    func testClarifyFirst() {
        assertAppearances(clarify(current: 0, picked: ["keep up spanish": 0]), width: 1280, height: 820)
    }

    /// The last: two set aside with what they settled, the tap belonging to nothing bigger, and Sort it.
    func testClarifyLast() {
        let picked = ["keep up spanish": 0, "also call the bank about the mortgage": 0, "fix the leaking tap": 1]
        assertAppearances(clarify(current: 2, picked: picked, more: ["also call the bank about the mortgage": "it’s to refinance before we move"]),
                          width: 1280, height: 820)
    }

    private func sorted(_ plate: SortedPlate, center: OverlayCenter = OverlayCenter()) -> some View {
        let state = Fixtures.firstRun(.sorted, plate: plate)
        return FirstRunView(state: state, plateText: .constant("")).padding(.top, 20).background(Theme.background).overlayHost(center)
    }

    /// Sorted with the answers: Home's bucket, Around the house, said as one-offs that belong to nothing bigger.
    func testSortedWithBucket() {
        assertAppearances(sorted(Fixtures.sortedPlateAnswered), width: 1280, height: 820)
    }

    /// Spanish clicked: its card, with it as a practice 3 times a week, in Growth.
    func testSortedEditing() {
        let plate = Fixtures.sortedPlateAnswered
        let center = OverlayCenter()
        center.showMenu(anchor: CGRect(x: 396, y: 520, width: 300, height: 46), owner: "spanish", alignLeading: true) {
            SortedEditCard(plate: plate, edit: plate.edit(for: .item("spanish"))!, onDone: { _ in }, onRemove: {})
        }
        assertAppearances(sorted(plate, center: center), width: 1280, height: 820)
    }

    /// The bank call clicked: a task, under Move flats by January, which could go in Home's bucket instead.
    func testSortedEditingTask() {
        let plate = Fixtures.sortedPlateAnswered
        let center = OverlayCenter()
        center.showMenu(anchor: CGRect(x: 760, y: 300, width: 280, height: 26), owner: "move#0", alignLeading: true) {
            SortedEditCard(plate: plate, edit: plate.edit(for: .task(itemId: "move", index: 0))!, onDone: { _ in }, onRemove: {})
        }
        assertAppearances(sorted(plate, center: center), width: 1280, height: 820)
    }

    /// Five areas: the dashed Add an area takes the last place on the second row, naming a few usual areas not here.
    func testSortedAddAreaCard() {
        var plate = Fixtures.sortedPlateAnswered
        plate.areas.removeLast()
        assertAppearances(sorted(plate), width: 1280, height: 820)
    }

    /// Add an area, open from its card: the usual ones not here yet, and Name your own.
    func testSortedAddArea() {
        var plate = Fixtures.sortedPlateAnswered
        plate.areas.removeLast()
        let center = OverlayCenter()
        center.showMenu(anchor: CGRect(x: 809, y: 506, width: 309, height: 203), alignLeading: true) {
            AddAreaMenu(usual: Array(UsualArea.all.filter { !["Work", "Home", "Money", "Health", "Growth"].contains($0.name) }.prefix(4))) { _, _ in }
        }
        assertAppearances(sorted(plate, center: center), width: 1280, height: 820)
    }

    private func sorted(_ plate: SortedPlate, adding: AddDraft) -> some View {
        FirstRunSorted(plate: plate, adding: adding).padding(.top, 20).background(Theme.background).overlayHost(OverlayCenter())
    }

    /// Adding to Work, a project half named: its badge guesses the icon from the words, the kinds under it, Return to add.
    func testSortedAddingProject() {
        assertAppearances(sorted(Fixtures.sortedPlateAnswered, adding: AddDraft(areaId: "work", kind: .project, title: "Plan the team offsite")),
                          width: 1280, height: 820)
    }

    /// Adding to Home, a task, nothing typed yet: a task's box, where it'll go, Escape to close.
    func testSortedAddingTask() {
        assertAppearances(sorted(Fixtures.sortedPlateAnswered, adding: AddDraft(areaId: "home", kind: .task)), width: 1280, height: 820)
    }

    /// Spanish clicked, its look open: the colours and the icons under its name.
    func testSortedEditingLook() {
        let plate = Fixtures.sortedPlateAnswered
        let center = OverlayCenter()
        center.showMenu(anchor: CGRect(x: 396, y: 200, width: 300, height: 46), owner: "spanish", alignLeading: true) {
            SortedEditCard(plate: plate, edit: plate.edit(for: .item("spanish"))!, pickingLook: true, onDone: { _ in }, onRemove: {})
        }
        assertAppearances(sorted(plate, center: center), width: 1280, height: 820)
    }
}
