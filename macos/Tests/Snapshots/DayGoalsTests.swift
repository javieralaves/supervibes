import XCTest

/// The Day view's strip by goal: each goal's tasks against its sessions as the board counts them,
/// the order of the rows, and which tasks its session time doesn't reach.
final class DayGoalsTests: XCTestCase {
    private let now = Fixtures.referenceNow // Wednesday Nov 18, 10:18 in Madrid
    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    private var rows: [DayGoalRow] { Fixtures.dayByGoal.goalRows(day: 0, now: now, calendar: madrid) }
    private func row(_ id: String) -> DayGoalRow { rows.first { $0.id == id }! }

    func testRowsRunOverFirstThenNoSessionsThenTheRest() {
        XCTAssertEqual(rows.map(\.id), ["superfocus", "jacob", "playbook", "leisure", "build"])
    }

    func testGapsAgreeWithTheBoard() {
        let superfocus = row("superfocus")
        XCTAssertEqual(superfocus.capacity.planned, 240)
        XCTAssertEqual(superfocus.capacity.protected, 150) // reserved meetings don't count
        XCTAssertEqual(superfocus.gap, .over(90))
        XCTAssertEqual(superfocus.gapLabel, "Needs 1 h 30 min")
        XCTAssertTrue(superfocus.isOver)

        XCTAssertEqual(row("build").gap, .spare(45))
        XCTAssertEqual(row("build").gapLabel, "45 min spare")
        XCTAssertEqual(row("jacob").gap, .noSessions(90))
        XCTAssertEqual(row("jacob").gapLabel, "Needs 1 h 30 min")
        XCTAssertFalse(row("jacob").isOver)
        // Only due today: listed, not counted.
        XCTAssertEqual(row("leisure").items.map(\.task.id), ["l-tickets"])
        XCTAssertEqual(row("leisure").gap, .nothingPlanned)
        XCTAssertEqual(row("leisure").gapLabel, "No time")
    }

    func testTasksPastTheGoalsTimeAreEverythingFromTheFirstThatDoesntFit() {
        let superfocus = row("superfocus")
        XCTAssertEqual(superfocus.items.map(\.task.id), ["sf-spark", "sf-design", "sf-actions", "sf-community", "sf-reality", "sf-renewals", "sf-focus"])
        // 1 h + 30 min + 1 h fill the 2 h 30 min; the four after it don't make it.
        XCTAssertEqual(superfocus.pastTime, ["sf-community", "sf-reality", "sf-renewals", "sf-focus"])
        XCTAssertTrue(row("build").pastTime.isEmpty)
        // No sessions at all: the ring says so, and nothing dims.
        XCTAssertTrue(row("jacob").pastTime.isEmpty)
    }

    func testOnlySessionTimeStillAheadCountsTowardWhatFits() {
        // At 2:00 PM an hour of the first session has gone by: 1 h 30 min is left for the tasks.
        let two = madrid.date(bySettingHour: 14, minute: 0, second: 0, of: now)!
        let superfocus = Fixtures.dayByGoal.goalRows(day: 0, now: two, calendar: madrid).first { $0.id == "superfocus" }!
        XCTAssertEqual(superfocus.pastTime, ["sf-actions", "sf-community", "sf-reality", "sf-renewals", "sf-focus"])
    }

    func testADayGoneByDimsNothing() {
        let yesterday = madrid.date(byAdding: .day, value: 1, to: now)!
        let rows = Fixtures.dayByGoal.goalRows(day: -1, now: yesterday, calendar: madrid)
        XCTAssertTrue(rows.allSatisfy(\.pastTime.isEmpty))
    }
}
