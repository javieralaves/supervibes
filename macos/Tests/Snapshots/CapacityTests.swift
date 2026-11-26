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

    func testTimePlannedWithNothingProtectedIsOver() {
        let thursday = Capacity.day("2026-11-19", open: 60, blocks: blocks, now: now, calendar: madrid)
        XCTAssertEqual(thursday.protected, 0)
        XCTAssertTrue(thursday.isOver)
        XCTAssertEqual(CapacityPopover.status(thursday), "No time protected")
        XCTAssertTrue(PlanTime.noTime(planned: 60).isOver)
        XCTAssertFalse(PlanTime.noTime(planned: 0).isOver)
    }

    func testColumnTotalsAddUpOveragesWithoutNettingSpareTime() {
        let over = Capacity(planned: 240, protected: 120)     // 2 h over
        let noTime = Capacity(planned: 60, protected: 0)      // 1 h, nothing protected
        let spare = Capacity(planned: 0, protected: 60)       // 1 h free
        let fits = Capacity(planned: 30, protected: 30)
        // Another goal's free hour doesn't make up for any of it: 3 h over.
        XCTAssertEqual(PlanTime.across([over, noTime, spare, fits], hasTasks: true), .weighed(planned: 390, protected: 210))
        // None over: what's free, added up.
        XCTAssertEqual(PlanTime.across([spare, fits], hasTasks: true), .weighed(planned: 30, protected: 90))
        // Nothing protected anywhere.
        XCTAssertEqual(PlanTime.across([noTime], hasTasks: true), .noTime(planned: 60))
        XCTAssertEqual(PlanTime.across([Capacity(planned: 0, protected: 0)], hasTasks: false), PlanTime.none)
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
