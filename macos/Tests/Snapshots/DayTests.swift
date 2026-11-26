import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The Day view: its strip, timeline, popovers and block panels.
@MainActor
final class DayTests: XCTestCase {
    private let now = Fixtures.referenceNow

    func testDayTimeline() {
        // 6 AM to 3 PM of the timeline, the way it opens on a morning.
        let top = DayGrid.standard.y(6 * 60)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour)
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.standard.y(15 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.standard.y(15 * 60) - top
        )
    }

    func testDayTimelinePopover() {
        // Protecting 3–4 PM: the draft with the popover under it.
        let top = DayGrid.standard.y(14 * 60)
        let editing = BlockEditing(mode: .create, day: 0, start: 15 * 60, end: 16 * 60, goalId: Fixtures.calendar.goals[0].id, title: nil)
        assertAppearances(
            DayTimeline(data: Fixtures.calendar, offset: 0, now: now, clock: .twelveHour, editing: .constant(editing))
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: DayGrid.standard.y(18 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: DayGrid.standard.y(18 * 60) - top
        )
    }

    /// Time just drawn, as a task: typing suggests open tasks, those starting with it and in the
    /// chosen goal first.
    func testNewBlockTaskSuggestions() {
        let data = Fixtures.calendar
        assertAppearances(
            NewBlockPopover(
                goals: data.goals, tasks: data.tasks, goalId: data.goals[0].id, kind: .task, title: "re",
                timeLabel: "Today · 12:00–1:00 PM · 1h", onAdd: { _, _, _ in }, onCancel: {}
            )
            .frame(width: 320)
            .padding(24)
            .background(Theme.background),
            width: 368
        )
    }

    /// The Anytime strip by goal: a row each, over first, every one closed.
    func testDayStripByGoal() {
        assertAppearances(
            DayView(data: Fixtures.dayByGoal, offset: 0, now: now).background(Theme.background),
            width: 1000, height: 820
        )
    }

    /// Superfocus open: its tasks listed, the four its sessions don't reach dimmed, its sessions ringed.
    func testDayStripGoalOpen() {
        assertAppearances(
            DayView(data: Fixtures.dayByGoal, offset: 0, now: now, openGoals: ["superfocus"]).background(Theme.background),
            width: 1000, height: 820
        )
    }

    /// Right-clicking a task within its goal's time, and one past it (dimmed): the second leads with
    /// where it could go instead.
    func testDayTaskMenus() {
        let data = Fixtures.dayByGoal
        let row = data.goalRows(day: 0, now: now).first { $0.id == "superfocus" }!
        func menu(_ id: String) -> some View {
            DayTaskMenu(
                task: data.tasks.first { $0.id == id }!, goal: row.goal, suggestions: data.suggestions(for: id, day: 0, now: now)!,
                sessionMinutes: row.capacity.protected, day: 0, dayISO: row.day, today: "2026-11-18", clock: .twelveHour,
                actions: CalendarActions.preview
            )
        }
        assertAppearances(
            HStack(alignment: .top, spacing: 24) {
                menu("sf-design")
                menu("sf-renewals")
            }
            .padding(24)
            .background(Theme.background),
            width: 648
        )
    }

    /// January renewals held second in Superfocus's list: lifted into its new place, and the dimming
    /// moved so Actions in other apps no longer fits.
    func testDayStripReordering() {
        let holding = Placing(taskId: "sf-renewals", goalId: "superfocus", title: "January renewals for the first founding members",
                              minutes: 30, moved: true, listIndex: 1)
        assertAppearances(
            GoalStrip(rows: Fixtures.dayByGoal.goalRows(day: 0, now: now), today: "2026-11-18", dayName: "Today",
                      open: .constant(["superfocus"]), holding: holding)
                .frame(width: 768)
                .background(Theme.card),
            width: 768
        )
    }

    /// Superfocus open on the strip: its two sessions ringed lightly, its reserved meetings and Build's session not.
    func testDayTimelineGoalSessionsRinged() {
        let top = DayGrid.standard.y(12 * 60 + 30)
        let bottom = DayGrid.standard.y(17 * 60 + 30)
        assertAppearances(
            DayTimeline(data: Fixtures.dayByGoal, offset: 0, now: now, clock: .twelveHour, ringedGoals: ["superfocus"])
                .frame(width: 736)
                .offset(y: -top)
                .frame(width: 736, height: bottom - top, alignment: .topLeading)
                .clipped()
                .background(Theme.card),
            width: 736, height: bottom - top
        )
    }

    func testBlockPanels() {
        let data = Fixtures.calendar
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.panelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                        openTaskIds: ["t5"], ended: block.endsAt <= now, now: now, actions: nil
                    )
                    .frame(width: 320, height: 640)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 672
        )
    }

    func testFreshBlockPanels() {
        let data = Fixtures.calendar
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.freshPanelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                        openTaskIds: [], ended: block.endsAt <= now, now: now, actions: nil
                    )
                    .frame(width: 320, height: 360)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1024, height: 392
        )
    }

    func testSessionAndReservedPanels() {
        // With actions, so the rows can be changed and the description offers Tab.
        let data = Fixtures.calendar
        let now = now
        let actions = BlockPanelActions(
            setDescription: { _, _ in nil }, prepareAgenda: { _, _ in nil },
            suggestFocus: { _, _, _ in .failed("") }, prepareRecap: { _ in nil },
            postRecap: { _, _, _, _ in nil }, discardRecap: { _ in nil }, setTaskDone: { _, _ in nil },
            toggleDone: { _ in }, openGoal: { _ in }
        )
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Fixtures.kindPanelBlocks) { block in
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                        day: 0, start: 13 * 60, end: 14 * 60 + 30, when: "Wednesday, November 18 (today), 1:00–2:30 PM",
                        openTaskIds: [], ended: false, now: now, actions: actions, calendar: .preview
                    )
                    .frame(width: 320, height: 360)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 688, height: 392
        )
    }

    func testDayViewTop() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now).background(Theme.background),
            width: 900, height: 360
        )
    }
}
