import XCTest

/// The app's copy of src/lib/task-horizon.ts: where a task stands, and how placing it changes its day and week.
final class TaskHorizonTests: XCTestCase {
    /// A Thursday; this week starts Monday Nov 16, next week Nov 23.
    private let today = "2026-11-19"

    private func task(_ plannedFor: String?, _ plannedWeek: String?) -> TaskItem {
        TaskItem(id: "t", title: "T", minutes: 30, plannedFor: plannedFor, plannedWeek: plannedWeek)
    }

    func testWeekStart() {
        XCTAssertEqual(CalendarDay.weekStart("2026-11-16"), "2026-11-16")
        XCTAssertEqual(CalendarDay.weekStart("2026-11-19"), "2026-11-16")
        XCTAssertEqual(CalendarDay.weekStart("2026-11-22"), "2026-11-16")
        XCTAssertEqual(CalendarDay.weekStart("2026-11-23"), "2026-11-23")
        XCTAssertEqual(CalendarDay.weekStart("2027-01-01"), "2026-12-28")
    }

    func testHorizon() {
        XCTAssertEqual(task(nil, nil).horizon(today: today), TaskHorizon(group: .later))
        XCTAssertEqual(task("2026-11-19", "2026-11-16").horizon(today: today), TaskHorizon(group: .day))
        XCTAssertEqual(task("2026-12-20", "2026-12-14").horizon(today: today), TaskHorizon(group: .day))
        XCTAssertEqual(task("2026-11-18", "2026-11-16").horizon(today: today), TaskHorizon(group: .thisWeek, slipped: true))
        XCTAssertEqual(task(nil, "2026-11-16").horizon(today: today), TaskHorizon(group: .thisWeek))
        XCTAssertEqual(task(nil, "2026-11-02").horizon(today: today), TaskHorizon(group: .thisWeek, carriedWeeks: 2))
        XCTAssertEqual(task("2026-11-12", "2026-11-09").horizon(today: today), TaskHorizon(group: .thisWeek, slipped: true, carriedWeeks: 1))
        XCTAssertEqual(task(nil, "2026-11-23").horizon(today: today), TaskHorizon(group: .nextWeek))
        XCTAssertEqual(task(nil, "2026-11-30").horizon(today: today), TaskHorizon(group: .later))
    }

    func testPlacing() {
        func placed(_ t: TaskItem, day: String? = nil, week: String? = nil) -> [String?] {
            let p = t.placed(plannedFor: day, plannedWeek: week, today: today)
            return [p.plannedFor, p.plannedWeek]
        }
        // A day picks its week.
        XCTAssertEqual(placed(task(nil, nil), day: "2026-11-25"), ["2026-11-25", "2026-11-23"])
        // Clearing the day keeps the week, unless it's past next week.
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), day: ""), [nil, "2026-11-16"])
        XCTAssertEqual(placed(task("2026-12-20", "2026-12-14"), day: ""), [nil, nil])
        XCTAssertEqual(placed(task("2026-11-12", "2026-11-09"), day: ""), [nil, "2026-11-09"])
        // Another week drops a day outside it; the same week keeps it.
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), week: "2026-11-26"), [nil, "2026-11-23"])
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), week: "2026-11-19"), ["2026-11-20", "2026-11-16"])
        // Clearing the week, alone or with the day: Later.
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), week: ""), [nil, nil])
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), day: "", week: ""), [nil, nil])
        // Clear the day and move it to next week, as "Move to next week" does.
        XCTAssertEqual(placed(task("2026-11-20", "2026-11-16"), day: "", week: "2026-11-23"), [nil, "2026-11-23"])
        // Nothing asked: nothing changes.
        XCTAssertEqual(placed(task(nil, "2026-11-16")), [nil, "2026-11-16"])
    }
}

/// Which column of the planning board a task sits in, and what dropping it on one plans it for.
final class BoardColumnTests: XCTestCase {
    private let today = "2026-11-19" // Thursday

    private func column(_ plannedFor: String?, _ plannedWeek: String?) -> BoardColumn {
        BoardColumn.of(TaskItem(id: "t", title: "T", minutes: 30, plannedFor: plannedFor, plannedWeek: plannedWeek), today: today)
    }

    func testColumns() {
        XCTAssertEqual(column("2026-11-19", "2026-11-16"), .day("2026-11-19"))
        XCTAssertEqual(column("2026-11-21", "2026-11-16"), .day("2026-11-21"))
        XCTAssertEqual(column("2026-11-22", "2026-11-16"), .thisWeek) // Sunday, past the three days
        XCTAssertEqual(column("2026-11-25", "2026-11-23"), .nextWeek)
        XCTAssertEqual(column("2026-12-20", "2026-12-14"), .later)
        XCTAssertEqual(column("2026-11-17", "2026-11-16"), .thisWeek) // slipped
        XCTAssertEqual(column(nil, "2026-11-02"), .thisWeek) // carried
        XCTAssertEqual(column(nil, "2026-11-23"), .nextWeek)
        XCTAssertEqual(column(nil, nil), .later)
    }

    func testDropPatches() {
        XCTAssertEqual(BoardColumn.day("2026-11-20").patch(today: today), TaskPatch(plannedFor: "2026-11-20"))
        XCTAssertEqual(BoardColumn.thisWeek.patch(today: today), TaskPatch(plannedFor: "", plannedWeek: "2026-11-16"))
        XCTAssertEqual(BoardColumn.nextWeek.patch(today: today), TaskPatch(plannedFor: "", plannedWeek: "2026-11-23"))
        XCTAssertEqual(BoardColumn.later.patch(today: today), TaskPatch(plannedFor: "", plannedWeek: ""))
    }
}
