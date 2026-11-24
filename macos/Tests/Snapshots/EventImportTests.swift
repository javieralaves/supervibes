import XCTest

/// Calendar import's rules: the key an imported block keeps for its event, which calendars count
/// as Google ones, the settings kept on this Mac, and what a sync offers when an event changes.
final class EventImportTests: XCTestCase {
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        return components.date!
    }

    // MARK: - Keys

    func testAOneOffEventKeepsItsUIDThroughAMove() {
        // A one-off's occurrence date follows its start, so it can't be in the key.
        let before = EventKey.make(externalId: "abc@google.com", isOccurrence: false, occurrenceDate: at(24, 13))
        let after = EventKey.make(externalId: "abc@google.com", isOccurrence: false, occurrenceDate: at(24, 15))
        XCTAssertEqual(before, "abc@google.com")
        XCTAssertEqual(before, after)
    }

    func testOccurrencesOfASeriesGetTheirOwnKeys() {
        let first = EventKey.make(externalId: "weekly@google.com", isOccurrence: true, occurrenceDate: at(24, 14))
        let second = EventKey.make(externalId: "weekly@google.com", isOccurrence: true, occurrenceDate: at(25, 14))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, "weekly@google.com|2026-11-24T13:00:00Z")
    }

    func testAMovedOccurrenceKeepsItsKey() {
        // Google gives a moved occurrence a UID ending in /RID= and its original time, and EventKit
        // keeps that original time as its occurrence date.
        let original = EventKey.make(externalId: "weekly@google.com", isOccurrence: true, occurrenceDate: at(24, 14))
        let moved = EventKey.make(externalId: "weekly@google.com/RID=816879600", isOccurrence: true, occurrenceDate: at(24, 14))
        XCTAssertEqual(original, moved)
    }

    func testGoogleAccountsAreCalDAVButNotICloud() {
        XCTAssertTrue(EventKey.isGoogleAccount(isCalDAV: true, title: "javi@gmail.com"))
        XCTAssertFalse(EventKey.isGoogleAccount(isCalDAV: true, title: "iCloud"))
        XCTAssertFalse(EventKey.isGoogleAccount(isCalDAV: false, title: "Other"))
    }

    // MARK: - Settings

    func testEveryCalendarIsTickedUntilThePersonPicks() {
        let work = ExternalCalendar(id: "w", title: "Work")
        let holidays = ExternalCalendar(id: "h", title: "Holidays in Spain")
        var settings = EventImportSettings.defaults
        XCTAssertTrue(settings.includes(work))
        XCTAssertTrue(settings.includes(holidays))

        // Unticking one pins the rest as they were, so a calendar added later starts unticked.
        settings.set(holidays, on: false, among: [work, holidays])
        XCTAssertTrue(settings.includes(work))
        XCTAssertFalse(settings.includes(holidays))
        XCTAssertFalse(settings.includes(ExternalCalendar(id: "new", title: "New")))
    }

    func testTheDefaultGoalFallsBackToTheFirstWhenItsGone() {
        var settings = EventImportSettings.defaults
        XCTAssertEqual(settings.goal(among: ["g1", "g2"]), "g1")
        settings.goalId = "g2"
        XCTAssertEqual(settings.goal(among: ["g1", "g2"]), "g2")
        XCTAssertEqual(settings.goal(among: ["g1"]), "g1")
        XCTAssertNil(settings.goal(among: []))
    }

    func testSettingsAreKeptOnThisMac() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "EventImportTests"))
        defaults.removePersistentDomain(forName: "EventImportTests")
        let settings = EventImportSettings(isOn: false, calendarIds: ["w"], goalId: "g2", kind: .reserved, hidesAllDay: false)
        settings.save(to: defaults)
        XCTAssertEqual(EventImportSettings.load(from: defaults), settings)
    }

    // MARK: - Changes

    private let source = EventSource(
        key: "review@google.com",
        calendar: "Work",
        snapshot: .init(title: "Design review", startsAt: Date(timeIntervalSince1970: 1_795_000_000), endsAt: Date(timeIntervalSince1970: 1_795_001_800))
    )

    private func event(title: String = "Design review", shift: TimeInterval = 0) -> ExternalEvent {
        ExternalEvent(
            key: source.key, calendarId: "w", calendarName: "Work", title: title,
            start: source.snapshot.startsAt.addingTimeInterval(shift), end: source.snapshot.endsAt.addingTimeInterval(shift)
        )
    }

    private func check(title: String? = "Design review", shift: TimeInterval = 0, event: ExternalEvent?) -> ImportCheck {
        ImportCheck.check(
            source, title: title,
            start: source.snapshot.startsAt.addingTimeInterval(shift), end: source.snapshot.endsAt.addingTimeInterval(shift),
            event: event
        )
    }

    func testNothingChangedIsInStep() {
        XCTAssertEqual(check(event: event()), .inStep)
        // The server keeps milliseconds; EventKit whole seconds.
        XCTAssertEqual(check(shift: 0.0004, event: event()), .inStep)
    }

    func testTheMeetingMovedOffersItsNewTimes() throws {
        guard case .changed(let change) = check(event: event(shift: 1800)) else { return XCTFail("Expected a change") }
        XCTAssertEqual(change.times?.start, source.snapshot.startsAt.addingTimeInterval(1800))
        XCTAssertNil(change.title)
        XCTAssertFalse(change.bothMoved)
        XCTAssertEqual(change.event, event(shift: 1800).snapshot)
    }

    func testTheMeetingRenamedOffersItsTitle() throws {
        guard case .changed(let change) = check(event: event(title: "Design review: blocks")) else { return XCTFail("Expected a change") }
        XCTAssertEqual(change.title, "Design review: blocks")
        XCTAssertNil(change.times)
    }

    func testBothMovedSomewhereDifferentShowsBoth() throws {
        guard case .changed(let change) = check(shift: 900, event: event(shift: 1800)) else { return XCTFail("Expected a change") }
        XCTAssertTrue(change.bothMoved)
    }

    func testBothMovedToTheSameTimeCatchesUpWithoutAsking() {
        XCTAssertEqual(check(shift: 1800, event: event(shift: 1800)), .catchUp(event(shift: 1800).snapshot))
    }

    func testOnlyTheBlockChangingIsInStep() {
        // Moving or renaming the block yourself isn't something to answer.
        XCTAssertEqual(check(title: "My review", shift: 900, event: event()), .inStep)
    }

    func testAGoneEventIsOffered() throws {
        guard case .changed(let change) = check(event: nil) else { return XCTFail("Expected a change") }
        XCTAssertTrue(change.isGone)
    }

    func testALongTitleCutToFitIsntARename() {
        let long = String(repeating: "Quarterly planning ", count: 10)
        let source = EventSource(key: "k", calendar: "Work", snapshot: .init(title: long, startsAt: self.source.snapshot.startsAt, endsAt: self.source.snapshot.endsAt))
        let event = ExternalEvent(key: "k", calendarId: "w", calendarName: "Work", title: long, start: source.snapshot.startsAt, end: source.snapshot.endsAt)
        XCTAssertEqual(
            ImportCheck.check(source, title: ImportCheck.blockTitle(long), start: source.snapshot.startsAt, end: source.snapshot.endsAt, event: event),
            .inStep
        )
    }
}
