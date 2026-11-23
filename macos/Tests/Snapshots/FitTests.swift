import XCTest

/// Making an over day fit on the planning board: which tasks move where, what free time there is,
/// and whose session has time to give.
final class FitTests: XCTestCase {
    private let now = Fixtures.referenceNow // Wednesday Nov 18, 10:18 in Madrid
    private let data = Fixtures.board

    private func goal(_ id: String) throws -> BoardGoal { try XCTUnwrap(data.goal(id)) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        return components.date!
    }

    func testMovesTheTaskToTheFirstDayWithRoomForAllOfIt() throws {
        // Build Supervibes today: 3 h open and this morning's hour gone by, in 2 h of sessions.
        let build = try goal("1")
        XCTAssertEqual(Fit.over(build, day: "2026-11-18", now: now), 120)
        let moves = Fit.moves(build, day: "2026-11-18", today: "2026-11-18", now: now)
        // The API sketch has its own time on the calendar, so it stays. Friday has 1 h 30 min
        // spare, not the 2 h the rebuild takes; Saturday has 5 h.
        XCTAssertEqual(moves.map(\.task.id), ["t1"])
        XCTAssertEqual(moves.first?.to, .day("2026-11-21"))
        XCTAssertEqual(moves.first?.roomAfter, 180)
        XCTAssertEqual(moves.first?.protected, 300)
    }

    func testMovesFromTheBottomOfTheDayAndSkipsWhatFitsNowhere() throws {
        // The playbook tomorrow: 3 h in a 1 h 30 min session. Friday takes the commute map (last
        // in its order); nothing has room for the interviews, and the week is over as a whole, so
        // they stay, and the day stays 30 min over.
        let playbook = try goal("3")
        let moves = Fit.moves(playbook, day: "2026-11-19", today: "2026-11-18", now: now)
        XCTAssertEqual(moves.map(\.task.id), ["p2"])
        XCTAssertEqual(moves.first?.to, .day("2026-11-20"))
        XCTAssertEqual(moves.first?.roomAfter, 60)
    }

    func testNothingToMoveWhenTheDayFits() throws {
        // Jacob's app tomorrow: 1 h in a 1 h session.
        XCTAssertTrue(Fit.moves(try goal("2"), day: "2026-11-19", today: "2026-11-18", now: now).isEmpty)
        XCTAssertTrue(Fit.freeSlots(for: try goal("2"), day: "2026-11-19", in: data, now: now).isEmpty)
    }

    func testFreeTimeNextToTheGoalsSessionComesFirst() throws {
        // From 10:30 (the next quarter hour) to 11:30 PM, around every goal's blocks: right after
        // Build's 4 PM session, then the evening, each no longer than the 2 h it's over.
        let slots = Fit.freeSlots(for: try goal("1"), day: "2026-11-18", in: data, now: now)
        XCTAssertEqual(slots, [
            Fit.Slot(start: at(18, 17), end: at(18, 18)),
            Fit.Slot(start: at(18, 19), end: at(18, 21)),
        ])
    }

    func testTimeToGiveComesFromGoalsWithTasksAndRoomThatDay() throws {
        // Superfocus has 1 h spare in its 1–4 PM session, Jacob's app 45 min in its 11–12; Movement
        // has time and no tasks, which is time for its own sake, so it gives none.
        let gives = Fit.gives(to: try goal("1"), day: "2026-11-18", in: data, now: now)
        XCTAssertEqual(gives.map(\.fromGoal), ["6", "2"])
        XCTAssertEqual(gives.first?.slot, Fit.Slot(start: at(18, 15), end: at(18, 16)))
        XCTAssertEqual(gives.last?.slot, Fit.Slot(start: at(18, 11, 15), end: at(18, 12)))
    }

    func testDestinationsPlanAsTheBoardDoes() {
        XCTAssertEqual(Fit.Destination.day("2026-11-21").patch(today: "2026-11-18"), TaskPatch(plannedFor: "2026-11-21"))
        XCTAssertEqual(Fit.Destination.nextWeek.patch(today: "2026-11-18"), TaskPatch(plannedFor: "", plannedWeek: "2026-11-23"))
        XCTAssertEqual(Fit.Destination.thisWeek.patch(today: "2026-11-18"), TaskPatch(plannedFor: "", plannedWeek: "2026-11-16"))
    }
}
