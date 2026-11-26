import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Life, areas and their pages, and the area dialogs and pickers.
@MainActor
final class LifeTests: XCTestCase {
    private let now = Fixtures.referenceNow
    private let areaActions = AreaEditActions(create: { _ in true }, update: { _, _ in }, remove: { _ in })
    private let areaPageActions = AreaPageActions(save: { _ in true }, remove: {}, takeOut: { _ in }, moveIn: { _ in }, newGoal: { _ in },
                                                  nameGap: {}, writeGap: { _ in true })

    /// Life with six goals in four of six areas: Work on track, Madrid off track, People on track, Health with no
    /// status yet, and two areas with no goals.
    func testLifeHome() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.lifeGoals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     areas: Fixtures.areas, now: now, actions: GoalCardActions(setObjective: { _ in }),
                     areaActions: areaActions)
                .background(Theme.background),
            width: 1180, height: 1300
        )
    }

    /// Editing the areas, from the pencil: each card's icon a button, its name a field, a remove button in its
    /// corner, a new area being named at the end, and the goals stepping back above.
    func testLifeHomeEditingAreas() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.lifeGoals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     areas: Fixtures.areas, now: now, actions: GoalCardActions(setObjective: { _ in }),
                     areaActions: areaActions, startsEditingAreas: true, startsWithNewArea: true)
                .background(Theme.background),
            width: 1180, height: 1460
        )
    }

    /// No areas yet: an Areas heading and one quiet way to start.
    func testLifeHomeFirstArea() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     now: now, actions: GoalCardActions(setObjective: { _ in }), areaActions: areaActions)
                .background(Theme.background),
            width: 1180, height: 1100
        )
    }

    /// Before any areas: the goals alone, with no Areas section and no area on the cards.
    func testLifeHomeNoAreas() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.goals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     now: now, actions: GoalCardActions(setObjective: { _ in }))
                .background(Theme.background),
            width: 1180, height: 900
        )
    }

    func testLifeHomeEmpty() {
        assertAppearances(
            LifeHome(firstName: "Javier", goals: [], today: "2026-11-18", now: now).background(Theme.background),
            width: 900, height: 760
        )
    }

    /// Madrid's page: its status in the header, where it is and where it's going with the gap Supervibes named, its
    /// read, and its two goals in one list.
    func testAreaPage() {
        assertAppearances(
            AreaPage(detail: Fixtures.areaDetail, actions: areaPageActions, onRead: {}, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 1320
        )
    }

    /// Madrid before its gap is named: what it'll be, Name the gap and Write it yourself; and before its first read.
    func testAreaPageGapUnnamed() {
        assertAppearances(
            AreaPage(detail: Fixtures.unreadAreaDetail, actions: areaPageActions, onRead: {}, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 1180
        )
    }

    /// Madrid's gap while Supervibes names it again: the gap dimmed and its button turning.
    func testAreaPageNamingGap() {
        assertAppearances(
            AreaPage(detail: Fixtures.areaDetail, actions: areaPageActions, onRead: {}, namingGap: true, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 640
        )
    }

    /// A gap the person wrote, said so under it; and a goal whose name runs long, cut short before its status.
    func testAreaPageGapWritten() {
        var detail = Fixtures.areaDetail
        detail.area.gap = AreaGap(title: "From tools that work to people who use them.", body: "",
                                  by: .you, at: Fixtures.referenceNow.addingTimeInterval(-2 * 86400))
        detail.goals[0].title = "Publish the housing playbook for Madrid’s institutions and the groups that work with them"
        assertAppearances(
            AreaPage(detail: detail, actions: areaPageActions, onRead: {}, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 1240
        )
    }

    /// The gap being written: two fields in its place, Save and Cancel, and why it didn't save.
    func testAreaPageWritingGap() {
        assertAppearances(
            AreaPage(detail: Fixtures.unreadAreaDetail, actions: areaPageActions, onRead: {},
                     gapError: "Name the gap in a few words.", startsWritingGap: true, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 700
        )
    }

    /// Madrid's read card while it's being written again: the read dimmed, the button turning.
    func testAreaReadCardReading() {
        assertAppearances(
            AreaReadCard(detail: Fixtures.areaDetail, reading: true, now: Fixtures.referenceNow, onRead: {})
                .padding(32).frame(maxHeight: .infinity, alignment: .top).background(Theme.background),
            width: 704, height: 400
        )
    }

    /// Madrid before its first read: its status, a button for the read, and a read that didn't come back.
    func testAreaReadCardFirstRead() {
        assertAppearances(
            AreaReadCard(detail: Fixtures.unreadAreaDetail, error: "The read didn’t come back. Try again.",
                         now: Fixtures.referenceNow, onRead: {})
                .padding(32).frame(maxHeight: .infinity, alignment: .top).background(Theme.background),
            width: 704, height: 340
        )
    }

    /// Madrid being edited: its icon a button, name and words as fields, its goals each with an ×, a way to move
    /// another goal in, and removing it at the end.
    func testAreaPageEditing() {
        assertAppearances(
            AreaPage(detail: Fixtures.areaDetail, otherGoals: Fixtures.lifeGoals.filter { $0.areaId != "madrid" },
                     actions: areaPageActions, startsEditing: true, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 1080
        )
    }

    /// An area just made: prompts for its words, a gap that waits for them, its read in its empty form, and a list
    /// with nothing in it yet but ways to give it goals.
    func testAreaPageNew() {
        assertAppearances(
            AreaPage(detail: Fixtures.newAreaDetail, actions: areaPageActions, onRead: {}, now: Fixtures.referenceNow)
                .background(Theme.background),
            width: 900, height: 1120
        )
    }

    /// The areas a goal can go in, from "Add to an area" or a goal in one: the one in force ticked.
    func testAreaMenu() {
        assertAppearances(
            AreaMenu(areas: Fixtures.areas, selected: "madrid", onPick: { _ in }, onNewArea: {}).padding(24).background(Theme.shell),
            width: 280
        )
    }

    func testAreaIconPicker() {
        assertAppearances(
            AreaIconPicker(selected: "Building03Icon") { _ in }.padding(24).background(Theme.shell),
            width: 328
        )
    }

    func testNewAreaDialog() {
        assertAppearances(
            NewAreaDialog(input: AreaInput(name: "Learning", icon: "BookOpen01Icon")).padding(24).background(Theme.shell),
            width: 432
        )
    }
}
