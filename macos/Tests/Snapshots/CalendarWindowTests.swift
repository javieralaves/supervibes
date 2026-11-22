import Foundation
import XCTest

/// Which days the Calendar shows: Day, Next N days and Week, through the arrows, scrolling, Today
/// and midnight. Fixtures.referenceNow is Wednesday 18 November 2026, so this Monday is 2 days back.
final class CalendarWindowTests: XCTestCase {
    private let now = Fixtures.referenceNow
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: now)! }

    // MARK: Spans

    func testRawValuesRoundTrip() {
        for span in CalendarSpan.all {
            XCTAssertEqual(CalendarSpan(rawValue: span.rawValue), span)
        }
        // What the Calendar's switch saved before.
        XCTAssertEqual(CalendarSpan(rawValue: "day"), .day)
        XCTAssertEqual(CalendarSpan(rawValue: "week"), .week)
        XCTAssertNil(CalendarSpan(rawValue: "days-4"))
        XCTAssertNil(CalendarSpan(rawValue: "month"))
    }

    func testCountsAndLabels() {
        XCTAssertEqual(CalendarSpan.all.map(\.count), [1, 3, 5, 7, 7])
        XCTAssertEqual(CalendarSpan.all.map(\.label), ["Day", "3 days", "5 days", "7 days", "Week"])
        XCTAssertEqual(CalendarSpan.days(5).title, "Next 5 days")
    }

    func testOpensOnTheSettingsChoiceElseTheLastView() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CalendarWindowTests"))
        defaults.removePersistentDomain(forName: "CalendarWindowTests")
        defer { defaults.removePersistentDomain(forName: "CalendarWindowTests") }

        XCTAssertEqual(CalendarSpan.opening(defaults), .day)
        // Left on the week before Settings had a choice: it still opens there.
        defaults.set("week", forKey: CalendarSpan.legacyKey)
        XCTAssertEqual(CalendarSpan.opening(defaults), .week)
        CalendarSpan.setOpening(.days(5), defaults)
        XCTAssertEqual(CalendarSpan.opening(defaults), .days(5))
        XCTAssertEqual(CalendarSpan.lastDayCount(defaults), 5)
    }

    func testRangeTitles() {
        XCTAssertEqual(CalendarDay.formatRange("2026-11-18", days: 3), "Nov 18–20")
        XCTAssertEqual(CalendarDay.formatRange("2026-11-29", days: 5), "Nov 29 – Dec 3")
        XCTAssertEqual(CalendarDay.formatWeek("2026-11-16"), "Nov 16–22")
    }

    // MARK: Next N days

    func testNextDaysStartToday() {
        let window = CalendarWindow(span: .days(3), now: now)
        XCTAssertEqual(window.first, 0)
        XCTAssertEqual(window.shown, 0...2)
        XCTAssertTrue(window.isHome(now: now))
        // Three days, all within what's loaded (-36...42).
        XCTAssertEqual(window.firstRange, -36...40)
    }

    func testNextDaysPageAndToday() {
        var window = CalendarWindow(span: .days(5), now: now)
        window.scroll(5)
        XCTAssertEqual(window.shown, 5...9)
        XCTAssertEqual(window.offset, 5)
        XCTAssertFalse(window.isHome(now: now))
        window.scroll(-1)
        XCTAssertEqual(window.first, 4)
        window.today(now: now)
        XCTAssertEqual(window.first, 0)
        XCTAssertEqual(window.offset, 0)
    }

    func testScrollingStopsAtWhatsLoaded() {
        var window = CalendarWindow(span: .days(7), now: now, loaded: -5...10)
        window.scroll(100)
        XCTAssertEqual(window.shown, 4...10)
        window.scroll(-100)
        XCTAssertEqual(window.first, -5)
    }

    func testSteppingADayPastTheShownDaysMovesThem() {
        var window = CalendarWindow(span: .days(3), now: now)
        window.step(2, now: now)
        XCTAssertEqual(window.offset, 2)
        XCTAssertEqual(window.first, 0)
        window.step(1, now: now)
        XCTAssertEqual(window.shown, 3...5)
    }

    func testShowingADay() {
        var window = CalendarWindow(span: .days(3), now: now)
        window.show(day: 1, now: now)
        XCTAssertEqual(window.first, 0)
        window.show(day: 12, now: now)
        XCTAssertEqual(window.shown, 12...14)
        XCTAssertEqual(window.offset, 12)
    }

    // MARK: Week

    func testWeekStartsOnMonday() {
        var window = CalendarWindow(span: .week, now: now)
        XCTAssertEqual(window.shown, -2...4)
        window.scroll(7)
        XCTAssertEqual(window.first, 5)
        window.scroll(1)
        XCTAssertEqual(window.first, 6)
        window.today(now: now)
        XCTAssertEqual(window.first, -2)
        // A day outside the week: its own Monday-to-Sunday week (Sat 28 Nov is in Nov 23–29).
        window.show(day: 10, now: now)
        XCTAssertEqual(window.shown, 5...11)
    }

    // MARK: Switching views

    func testSwitchingKeepsTheDayInView() {
        var window = CalendarWindow(span: .day, now: now)
        window.step(1, now: now)
        // Tomorrow is among the next 3 days: they open from today.
        window.setSpan(.days(3), now: now)
        XCTAssertEqual(window.shown, 0...2)
        XCTAssertEqual(window.offset, 1)

        window.setSpan(.day, now: now)
        window.step(9, now: now)
        // Day 10 isn't: it goes first.
        window.setSpan(.days(5), now: now)
        XCTAssertEqual(window.shown, 10...14)
        // And in the week, its Monday-to-Sunday week.
        window.setSpan(.week, now: now)
        XCTAssertEqual(window.shown, 5...11)
        XCTAssertEqual(window.offset, 10)
    }

    // MARK: Midnight

    func testAtHomeTheDaysMoveOnWithTheDay() {
        var window = CalendarWindow(span: .days(3), now: now)
        window.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(window.first, 0)
        XCTAssertEqual(window.offset, 0)
        XCTAssertEqual(window.loaded, -37...41)
    }

    func testScrolledTheDaysStayOnTheirDates() {
        var window = CalendarWindow(span: .days(3), now: now)
        window.scroll(4)
        window.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(window.shown, 3...5)
        XCTAssertEqual(window.offset, 3)
    }

    func testTheWeekKeepsItsMondayOverMidnight() {
        // At home: still this week's Monday, now three days back.
        var home = CalendarWindow(span: .week, now: now)
        home.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(home.first, -3)

        // Scrolled to start on Thursday: it stays on Thursday rather than sliding a day.
        var scrolled = CalendarWindow(span: .week, now: now)
        scrolled.scroll(3)
        scrolled.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(scrolled.first, 0)
    }

    func testTheWeekAtHomeMovesToTheNewWeekOnMonday() {
        let sunday = Calendar.current.date(byAdding: .day, value: 4, to: now)!
        let monday = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        var window = CalendarWindow(span: .week, now: sunday)
        XCTAssertEqual(window.first, -6)
        window.dayChanged(by: 1, before: sunday, now: monday)
        XCTAssertEqual(window.first, 0)
    }

    func testDayFollowsTodayOrKeepsItsDate() {
        var today = CalendarWindow(span: .day, now: now)
        today.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(today.offset, 0)

        var saturday = CalendarWindow(span: .day, now: now)
        saturday.step(3, now: now)
        saturday.dayChanged(by: 1, before: now, now: tomorrow)
        XCTAssertEqual(saturday.offset, 2)
    }
}
