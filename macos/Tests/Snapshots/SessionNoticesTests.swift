import Foundation
import XCTest

/// Which notices before sessions go out, and which come out of Notification Center.
final class SessionNoticesTests: XCTestCase {
    private let now = Fixtures.referenceNow
    private let minute: TimeInterval = 60

    private func block(_ id: String, startsIn minutes: Double, length: Double = 60, aim: String? = nil) -> Block {
        let start = now.addingTimeInterval(minutes * minute)
        return Block(id: id, title: "Write the API sketch", goal: "Ship Supervibes for Mac",
                     start: start, end: start.addingTimeInterval(length * minute), aim: aim)
    }

    func testEachChosenLeadGetsANotice() {
        let notices = SessionNotices.upcoming(for: [block("a", startsIn: 30)], leads: [.fifteen, .five, .atStart], now: now)
        XCTAssertEqual(notices.map(\.lead), [.fifteen, .five, .atStart])
        XCTAssertEqual(notices.map(\.fireDate), [15, 25, 30].map { now.addingTimeInterval($0 * minute) })
        XCTAssertEqual(notices.map(\.id), ["session-a-15", "session-a-5", "session-a-0"])
    }

    func testNoticesThatArePastAreSkippedNotSentLate() {
        let notices = SessionNotices.upcoming(for: [block("a", startsIn: 8)], leads: [.fifteen, .five, .atStart], now: now)
        XCTAssertEqual(notices.map(\.lead), [.five, .atStart])
        XCTAssertTrue(SessionNotices.upcoming(for: [block("a", startsIn: -1)], leads: [.atStart], now: now).isEmpty)
    }

    func testOffSendsNothing() {
        var settings = NoticeSettings.defaults
        XCTAssertTrue(SessionNotices.upcoming(for: [block("a", startsIn: 30)], leads: settings.active, now: now).isEmpty)
        settings.setOn(true)
        XCTAssertEqual(settings.active, [.five])
    }

    func testContentLeadsWithWhenAndCarriesTheAim() {
        let notice = SessionNotices.all(for: [block("a", startsIn: 30, aim: "A first cut of the routes")], leads: [.five])[0]
        XCTAssertEqual(notice.title, "In 5 min · Write the API sketch")
        XCTAssertTrue(notice.subtitle.hasSuffix("· Ship Supervibes for Mac"))
        XCTAssertEqual(notice.body, "A first cut of the routes")
        XCTAssertEqual(SessionNotices.all(for: [block("a", startsIn: 30)], leads: [.atStart])[0].title, "Starting now · Write the API sketch")
    }

    func testANewerNoticeReplacesTheEarlierOne() {
        let blocks = [block("a", startsIn: -1), block("b", startsIn: 3)]
        let outdated = SessionNotices.outdated(for: blocks, leads: [.fifteen, .five, .atStart], now: now)
        // "a" has started: its 15 and 5 minute notices give way to "Starting now".
        // "b" is 3 minutes off: its 15 minute notice gives way to the 5 minute one.
        XCTAssertEqual(outdated, ["session-a-15", "session-a-5", "session-b-15"])
    }

    func testEveryNoticeGoesOnceTheSessionIsOver() {
        let outdated = SessionNotices.outdated(for: [block("a", startsIn: -90)], leads: [.five], now: now)
        XCTAssertEqual(outdated, ["session-a-0", "session-a-15", "session-a-5"])
    }

    func testUntickingTheLastLeadTurnsNoticesOffAndKeepsIt() {
        var settings = NoticeSettings(isOn: true, leads: [.five, .atStart])
        settings.toggle(.atStart)
        XCTAssertEqual(settings, NoticeSettings(isOn: true, leads: [.five]))
        settings.toggle(.five)
        XCTAssertEqual(settings, NoticeSettings(isOn: false, leads: [.five]))
        settings.setOn(true)
        XCTAssertEqual(settings.active, [.five])
    }

    func testStoredOnThisMac() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SessionNoticesTests"))
        defaults.removePersistentDomain(forName: "SessionNoticesTests")
        XCTAssertEqual(NoticeSettings.load(from: defaults), .defaults)
        NoticeSettings(isOn: true, leads: [.fifteen, .atStart]).save(to: defaults)
        XCTAssertEqual(NoticeSettings.load(from: defaults), NoticeSettings(isOn: true, leads: [.fifteen, .atStart]))
    }
}
