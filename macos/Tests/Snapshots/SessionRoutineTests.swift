import Foundation
import XCTest

/// When the session routine runs: once per stretch of sessions, as it starts and once it's over.
final class SessionRoutineTests: XCTestCase {
    private let now = Fixtures.referenceNow
    private let minute: TimeInterval = 60

    /// A block from `from` to `to`, in minutes from `now`.
    private func block(_ id: String, _ from: Double, _ to: Double) -> Block {
        Block(id: id, title: id, goal: "Goal", start: now.addingTimeInterval(from * minute), end: now.addingTimeInterval(to * minute))
    }

    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * minute) }

    func testCloseSessionsJoinIntoOneStretch() {
        let stretches = SessionStretches.all([
            block("c", 130, 160),
            block("a", 0, 60),
            block("b", 65, 120), // 5 minutes after "a": joins it
        ])
        XCTAssertEqual(stretches.map(\.blockIds), [["a", "b"], ["c"]])
        XCTAssertEqual(stretches[0].end, at(120))
    }

    func testOverlappingSessionsJoin() {
        let stretches = SessionStretches.all([block("a", 0, 90), block("b", 30, 60)])
        XCTAssertEqual(stretches.count, 1)
        XCTAssertEqual(stretches[0].end, at(90))
    }

    func testStartsOnceThenEndsOnce() {
        let blocks = [block("a", 0, 60), block("b", 60, 90)]
        var started: Set<String> = []
        var actions: [SessionStretches.Action?] = []
        for t in [-1.0, 0, 30, 60, 89, 90, 120] {
            let step = SessionStretches.step(blocks: blocks, now: at(t), started: started)
            actions.append(step.action)
            started = step.started
        }
        XCTAssertEqual(actions, [nil, .start, nil, nil, nil, .end, nil])
    }

    func testAStretchThatGrowsDoesntStartAgain() {
        // Started with "a"; then "b" was added right after it.
        let step = SessionStretches.step(blocks: [block("a", -30, 30), block("b", 30, 60)], now: at(0), started: ["a"])
        XCTAssertNil(step.action)
        XCTAssertEqual(step.started, ["a", "b"])
    }

    func testWakingInsideASessionStartsIt() {
        XCTAssertEqual(SessionStretches.step(blocks: [block("a", -40, 20)], now: now, started: []).action, .start)
    }

    func testWakingAfterAStartedSessionEndsIt() {
        XCTAssertEqual(SessionStretches.step(blocks: [block("a", -90, -30)], now: now, started: ["a"]).action, .end)
    }

    func testDeletingTheSessionInProgressEndsIt() {
        XCTAssertEqual(SessionStretches.step(blocks: [], now: now, started: ["a"]).action, .end)
    }

    func testSleepingThroughTheGapStartsTheNextWithoutEnding() {
        // "a" was started, the Mac slept through its end, and woke inside "b".
        let step = SessionStretches.step(blocks: [block("a", -120, -60), block("b", -10, 50)], now: now, started: ["a"])
        XCTAssertEqual(step.action, .start)
        XCTAssertEqual(step.started, ["b"])
    }

    func testStoredOnThisMac() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SessionRoutineTests"))
        defaults.removePersistentDomain(forName: "SessionRoutineTests")
        XCTAssertEqual(SessionRoutine.load(from: defaults), .defaults)
        let routine = SessionRoutine(doNotDisturb: true, quitApps: [.init(bundleId: "com.apple.mail", name: "Mail")], reopenApps: false, start: "Start focus")
        routine.save(to: defaults)
        XCTAssertEqual(SessionRoutine.load(from: defaults), routine)
    }

    func testAChoiceFromAnOlderBuildStillLoads() throws {
        let routine = try JSONDecoder().decode(SessionRoutine.self, from: Data(#"{"start":"Start focus"}"#.utf8))
        XCTAssertEqual(routine, SessionRoutine(start: "Start focus"))
        XCTAssertTrue(routine.reopenApps)
    }
}
