import XCTest

/// The Plan page's sums: each goal's tasks for the day against its session time, where the cut
/// line falls, what a session has to spare, and a trade previewed.
final class PlanTests: XCTestCase {
    private let now = Fixtures.referenceNow // Wednesday Nov 18, 10:18 in Madrid
    private let data = Fixtures.plan

    private func lanes(_ data: CalendarData) -> [String: PlanLane] {
        Dictionary(uniqueKeysWithValues: data.planLanes(day: "2026-11-19", now: now).map { ($0.id, $0) })
    }

    func testCutLineFallsWhereSessionTimeRunsOut() throws {
        let build = try XCTUnwrap(lanes(data)["pg1"])
        // 4 h of tasks in a 2 h session: the first four (2 h) fit, the last three don't.
        XCTAssertEqual(build.open, 240)
        XCTAssertEqual(build.room, 120)
        XCTAssertEqual(build.fitting, 4)
        XCTAssertEqual(build.overflow.map(\.id), ["pt5", "pt6", "pt7"])
        XCTAssertEqual(build.overflowMinutes, 120)
        XCTAssertEqual(build.spare, -120)
    }

    func testReservedTimeIsNoRoomForTasks() throws {
        let health = try XCTUnwrap(lanes(data)["pg4"])
        XCTAssertEqual(health.room, 0)
        XCTAssertFalse(health.isActive)
        let budget = data.budget(day: 1, now: now)
        XCTAssertEqual(budget.awake, 16 * 60)
        XCTAssertEqual(budget.sessionMinutes, 300)
        XCTAssertEqual(budget.reserved, 120)
        XCTAssertEqual(budget.free, 16 * 60 - 420)
    }

    func testSpareAndGivingIt() throws {
        let superfocus = try XCTUnwrap(lanes(data)["pg2"])
        let block = try XCTUnwrap(data.blocks.first { $0.id == "p4" })
        XCTAssertEqual(data.spare(in: block, lane: superfocus, now: now), 30)

        // Giving those 30 min to Build Supervibes: its cut line drops one task, Superfocus just fits.
        let given = lanes(data.giving(GiveTime(blockId: "p4", goalId: "pg1", minutes: 30)))
        XCTAssertEqual(given["pg1"]?.room, 150)
        XCTAssertEqual(given["pg1"]?.fitting, 5)
        XCTAssertEqual(given["pg2"]?.spare, 0)

        // Reserved time and intentions have nothing to give.
        let gym = try XCTUnwrap(data.blocks.first { $0.id == "p1" })
        XCTAssertEqual(data.spare(in: gym, lane: lanes(data)["pg4"], now: now), 0)
    }

    func testGivingAWholeBlock() {
        let given = lanes(data.giving(GiveTime(blockId: "p5", goalId: "pg1", minutes: 0, whole: true)))
        XCTAssertEqual(given["pg1"]?.room, 180)
        XCTAssertEqual(given["pg3"]?.room, 0)
    }

    func testWeeks() throws {
        let build = try XCTUnwrap(lanes(data)["pg1"])
        // Next week: 1 h open against 9 h protected.
        XCTAssertEqual(build.nextWeek.planned, 60)
        XCTAssertEqual(build.nextWeek.protected, 540)
    }

    func testDayNames() {
        XCTAssertEqual(PlanDay.title(offset: 1, day: "2026-11-19"), "Tomorrow")
        XCTAssertEqual(PlanDay.title(offset: 3, day: "2026-11-21"), "Saturday")
        XCTAssertEqual(PlanDay.subtitle("2026-11-19"), "Thursday, Nov 19")
    }
}
