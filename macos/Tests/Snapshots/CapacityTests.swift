import XCTest

/// The planning board's capacity: totals planned (open estimates plus protected time gone by)
/// against all the time protected, for a day or a week.
final class CapacityTests: XCTestCase {
    private let now = Fixtures.referenceNow // Wednesday Nov 18, 10:18 in Madrid
    private let blocks = Fixtures.protectedBlocks
    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    func testOverCapacityDay() {
        // 3 h open, plus this morning's hour gone by, against 2 h protected.
        let today = Capacity.day("2026-11-18", open: 180, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(today.planned, 240)
        XCTAssertEqual(today.protected, 120)
        XCTAssertEqual(today.remaining, -120)
        XCTAssertTrue(today.isOver)
        XCTAssertEqual(today.blocks.map(\.isPast), [true, false])
        XCTAssertEqual(today.ahead.count, 1)
        XCTAssertEqual(CapacityPopover.status(today), "2 h over")
    }

    func testDayWithTimeLeftAndDayWithNone() {
        let friday = Capacity.day("2026-11-20", open: 30, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(CapacityPopover.status(friday), "1 h 30 min remaining")
        let thursday = Capacity.day("2026-11-19", open: 0, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(thursday.protected, 0)
        XCTAssertFalse(thursday.isOver)
        XCTAssertEqual(CapacityPopover.status(thursday), "No time protected")
    }

    func testWeeks() {
        // 7 h open this week, plus Monday's, Tuesday's and this morning's 6 h gone by, against 14 h.
        let thisWeek = Capacity.week("2026-11-16", open: 420, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(thisWeek.planned, 780)
        XCTAssertEqual(thisWeek.protected, 840)
        XCTAssertTrue(thisWeek.blocks.isEmpty)
        XCTAssertFalse(thisWeek.isDay)
        let nextWeek = Capacity.week("2026-11-23", open: 15, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(CapacityPopover.status(nextWeek), "3 h 45 min remaining")
    }

    func testABlockUnderWayCountsAsSpentUpToNow() {
        let start = now.addingTimeInterval(-30 * 60)
        let block = ProtectedBlock(start: start, end: start.addingTimeInterval(90 * 60))
        let today = Capacity.day("2026-11-18", open: 0, blocks: [block], now: now, calendar: madrid)
        XCTAssertEqual(today.planned, 30)
        XCTAssertEqual(today.protected, 90)
        XCTAssertEqual(today.ahead.count, 1)
    }

    func testDurationsAndRanges() {
        XCTAssertEqual(BoardDuration.text(225), "3 h 45 min")
        XCTAssertEqual(BoardDuration.text(120), "2 h")
        XCTAssertEqual(BoardDuration.text(45), "45 min")
        let at = { (hour: Int) in self.madrid.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour))! }
        XCTAssertEqual(Clock.twelveHour.range(at(16), at(18), calendar: madrid), "4:00 – 6:00 PM")
        XCTAssertEqual(Clock.twelveHour.range(at(9), at(12), calendar: madrid), "9:00 AM – 12:00 PM")
        XCTAssertEqual(Clock.twentyFourHour.range(at(9), at(11), calendar: madrid), "09:00 – 11:00")
    }
}
