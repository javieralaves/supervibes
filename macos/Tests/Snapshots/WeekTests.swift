import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The multi-day views, the events panel and imported blocks.
@MainActor
final class WeekTests: XCTestCase {
    private let now = Fixtures.referenceNow
    /// The User research call (b4, today 12:00–12:30), imported from General, and its event changed
    /// in each of the ways a sync can find.
    private func importedCall(title: String? = "User research call", shift: TimeInterval = 0, recap: Bool = false) -> CalendarBlock {
        var block = Fixtures.calendar.blocks.first { $0.id == "b4" }!
        block.title = title
        block.hasRecapPost = recap
        block.source = EventSource(key: "call", calendar: "General", snapshot: .init(title: "User research call", startsAt: block.startsAt, endsAt: block.endsAt))
        block.startsAt += shift
        block.endsAt += shift
        return block
    }

    private func changes(for block: CalendarBlock, event: ExternalEvent?) -> ImportChange? {
        guard case .changed(let change) = ImportCheck.check(block.source!, title: block.title, start: block.startsAt, end: block.endsAt, event: event) else { return nil }
        return change
    }

    private func callEvent(title: String = "User research call", shift: TimeInterval = 0) -> ExternalEvent {
        let block = importedCall()
        return ExternalEvent(key: "call", calendarId: "general", calendarName: "General", title: title,
                             start: block.startsAt + shift, end: block.endsAt + shift)
    }

    func testWeekView() {
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, span: .week, onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testWeekFromThursday() {
        // Scrolled to start on a Thursday: the title runs Thursday to Wednesday.
        let thursday = CalendarDayMath.monday(of: 0, from: now) + 3
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: thursday, onScroll: { _ in },
                    span: .week, onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testEventsPanel() {
        // Hovering Design review offers the default goal and Import; once imported, its row says where
        // it went with Undo; the User research call was imported before. Then no events at all.
        let goals = Fixtures.calendar.goals
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                EventsPanel(days: Fixtures.eventDays, goals: goals, imported: ["research": "g3"], defaultGoalId: "g1",
                            lastRead: now, hovered: "review")
                EventsPanel(days: Fixtures.eventDays, goals: goals, imported: ["research": "g3", "review": "g1"], defaultGoalId: "g1",
                            lastRead: now, justImported: "review", hovered: "weekly")
                EventsPanel(days: [], goals: goals, imported: [:], defaultGoalId: "g1", lastRead: now)
            }
            .frame(height: 560)
            .frame(width: 1008)
            .padding(16)
            .background(Theme.background),
            width: 1040, height: 592
        )
    }

    func testWeekWithEventsPanel() {
        // Five days from today with the events panel open where a block's panel would be, and Design
        // review under the pointer: its time previewed on Wednesday in Ship Supervibes' colour.
        let review = Fixtures.externalEvents[0]
        let panel = EventsPanel(days: Fixtures.eventDays, goals: Fixtures.calendar.goals, imported: ["research": "g3"],
                                defaultGoalId: "g1", lastRead: now, hovered: review.key)
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(5), onSetSpan: { _ in },
                    eventsPanel: AnyView(panel), showsEvents: true, onToggleEvents: {},
                    eventPreview: EventPreview(event: review, color: "sky", now: now))
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testThreeDaysFromToday() {
        // Wednesday to Friday, today first: "Nov 18–20 · From today", and columns roomy enough for
        // the day's block cards.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(3), onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testFiveDaysFromToday() {
        // Wednesday to Sunday.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(5), dayCount: 5, onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testSevenDaysFromToday() {
        // Wednesday to Tuesday, across the end of the week.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 0, now: now, first: 0, onScroll: { _ in },
                    span: .days(7), dayCount: 7, onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 720
        )
    }

    func testThreeDaysScrolledOn() {
        // Scrolled two days on: Friday to Sunday, no "From today", and Today shows.
        assertAppearances(
            DayView(data: Fixtures.calendar, offset: 2, now: now, first: 2, onScroll: { _ in },
                    span: .days(3), onSetSpan: { _ in })
                .background(Theme.background),
            width: 1400, height: 120
        )
    }

    func testThreeDaysPopover() {
        // Time drawn on the last of three columns: no room to its right, so the popover opens left.
        let top = WeekGrid.standard.y(9 * 60)
        let editing = BlockEditing(mode: .create, day: 2, start: 10 * 60, end: 11 * 60, goalId: Fixtures.calendar.goals[0].id, title: nil)
        assertAppearances(
            WeekView(data: Fixtures.calendar, first: 0, count: 3, now: now, clock: .twelveHour, creating: .constant(editing), scrolls: false)
                .frame(width: 1100, height: 260 + WeekGrid.standard.height)
                .offset(y: -top)
                .frame(width: 1100, height: WeekGrid.standard.y(14 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.background),
            width: 1100, height: WeekGrid.standard.y(14 * 60) - top
        )
    }

    func testCalendarDaysMenu() {
        // The switch's chevron: Next 3, 5 or 7 days, the one showing ticked.
        assertAppearances(
            DaysMenu(selected: 5) { _ in }.padding(16).background(Theme.background),
            width: 232
        )
    }

    func testCalendarViewCard() {
        assertAppearances(
            CalendarViewCard(span: .days(5)).padding(16).background(Theme.background),
            width: 800
        )
    }

    func testWeekGridMorning() {
        // 7 AM to 6 PM: the week's blocks, today's under way, the now line.
        let top = WeekGrid.standard.y(7 * 60)
        assertAppearances(
            WeekView(data: Fixtures.calendar, first: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
                .frame(width: 1100, height: 260 + WeekGrid.standard.height)
                .offset(y: -top)
                .frame(width: 1100, height: WeekGrid.standard.y(18 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.background),
            width: 1100, height: WeekGrid.standard.y(18 * 60) - top
        )
    }

    func testWeekGridWithEventPreview() {
        // 10 AM to 4 PM, with Design review hovered in the events panel: its time previewed on
        // Wednesday, ringed in Ship Supervibes' colour; over a block it would take the right half.
        let top = WeekGrid.standard.y(10 * 60)
        let review = Fixtures.externalEvents[0]
        let planning = Fixtures.externalEvents[3]
        let now = now
        assertAppearances(
            HStack(spacing: 16) {
                ForEach([review, planning], id: \.key) { event in
                    WeekView(data: Fixtures.calendar, first: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
                        .environment(\.eventPreview, EventPreview(event: event, color: "sky", now: now))
                        .frame(width: 700, height: 260 + WeekGrid.standard.height)
                        .offset(y: -top)
                        .frame(width: 700, height: WeekGrid.standard.y(16 * 60) - top, alignment: .topLeading)
                        .clipped()
                }
            }
            .background(Theme.background),
            width: 1416, height: WeekGrid.standard.y(16 * 60) - top
        )
    }

    func testImportedBlocks() {
        // The User research call, Lunch and the Week view sketch came from Google: the events
        // button's icon in each one's corner, in the week's narrow cards too. The research call's
        // panel leads with where it came from.
        var data = Fixtures.calendar
        let source = { (title: String) in
            EventSource(key: title, calendar: "General", snapshot: .init(title: title, startsAt: Fixtures.referenceNow, endsAt: Fixtures.referenceNow))
        }
        for id in ["b4", "b6", "w3"] {
            if let index = data.blocks.firstIndex(where: { $0.id == id }) {
                data.blocks[index].source = source(data.blocks[index].title ?? "")
            }
        }
        let call = data.blocks.first { $0.id == "b4" }!
        let top = WeekGrid.standard.y(9 * 60)
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                WeekView(data: data, first: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
                    .frame(width: 760, height: 260 + WeekGrid.standard.height)
                    .offset(y: -top)
                    .frame(width: 760, height: WeekGrid.standard.y(15 * 60) - top, alignment: .topLeading)
                    .clipped()
                BlockPanel(
                    block: call, goal: data.goal(call.goalId), goals: data.goals, description: nil,
                    day: 0, start: 12 * 60, end: 12 * 60 + 30, when: "Wednesday, November 18 (today), 12:00–12:30 PM",
                    openTaskIds: [], ended: false, now: now, actions: nil
                )
                .frame(width: 320, height: 420)
            }
            .padding(16)
            .background(Theme.background),
            width: 1128, height: WeekGrid.standard.y(15 * 60) - top + 32
        )
    }

    func testImportChangeNotices() {
        // Moved, renamed, moved where you'd moved it too, removed, and removed after its recap was posted.
        let data = Fixtures.calendar
        let cases: [(CalendarBlock, ExternalEvent?)] = [
            (importedCall(), callEvent(shift: 1800)),
            (importedCall(), callEvent(title: "User research call: Lisbon cohort")),
            (importedCall(shift: 900), callEvent(shift: 1800)),
            (importedCall(), nil),
            (importedCall(recap: true), nil),
        ]
        let now = now
        assertAppearances(
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
                    let (block, event) = item
                    BlockPanel(
                        block: block, goal: data.goal(block.goalId), goals: data.goals, description: nil,
                        day: 0, start: CalendarDayMath.minutes(block.startsAt), end: CalendarDayMath.minutes(block.endsAt),
                        when: "", openTaskIds: [], ended: false, now: now, actions: nil,
                        importChange: self.changes(for: block, event: event)
                    )
                    .frame(width: 320, height: 560)
                }
            }
            .padding(16)
            .background(Theme.background),
            width: 1712, height: 592
        )
    }

    func testEventsPanelWithChanges() {
        // A sync found three imported events changed: they lead the panel, each with its two answers.
        let data = Fixtures.calendar
        let now = now
        let items: [(CalendarBlock, ExternalEvent?)] = [
            (importedCall(), callEvent(shift: 1800)),
            (importedCall(title: "Weekly sync"), nil),
        ]
        let pending = items.enumerated().compactMap { index, item -> PendingChange? in
            var block = item.0
            block = CalendarBlock(id: "c\(index)", goalId: block.goalId, title: block.title, startsAt: block.startsAt, endsAt: block.endsAt, source: block.source)
            guard let change = changes(for: block, event: item.1) else { return nil }
            return PendingChange(block: block, change: change,
                                 copy: ImportChangeCopy(change, block: block, source: block.source!, clock: .twelveHour, now: now),
                                 color: data.goal(block.goalId)?.color ?? "slate")
        }
        assertAppearances(
            EventsPanel(days: Fixtures.eventDays, goals: data.goals, imported: ["research": "g3"], defaultGoalId: "g1",
                        lastRead: now, changes: pending)
                .frame(width: 320, height: 720)
                .padding(16)
                .background(Theme.background),
            width: 352, height: 752
        )
    }

    func testChangedBlockOnTheGrid() {
        // The research call's event moved half an hour later: its card carries the sync arrows, and the
        // new time is previewed beside it, as while its panel is open.
        var data = Fixtures.calendar
        if let index = data.blocks.firstIndex(where: { $0.id == "b4" }) { data.blocks[index] = importedCall() }
        let preview = EventPreview(day: 0, start: 12 * 60 + 30, end: 13 * 60, title: "New time", color: "indigo")
        let top = WeekGrid.standard.y(11 * 60)
        let now = now
        assertAppearances(
            WeekView(data: data, first: -2, now: now, clock: .twelveHour, creating: .constant(nil), scrolls: false)
                .environment(\.changedBlocks, ["b4"])
                .environment(\.eventPreview, preview)
                .frame(width: 760, height: 260 + WeekGrid.standard.height)
                .offset(y: -top)
                .frame(width: 760, height: WeekGrid.standard.y(14 * 60) - top, alignment: .topLeading)
                .clipped()
                .background(Theme.background),
            width: 760, height: WeekGrid.standard.y(14 * 60) - top
        )
    }
}
