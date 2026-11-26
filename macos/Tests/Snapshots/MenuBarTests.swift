import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The menu bar while a block runs or is coming, the widget, and sign-in.
@MainActor
final class MenuBarTests: XCTestCase {
    private let now = Fixtures.referenceNow

    func testMenuBarDuringBlock() {
        assertAppearances(
            MenuBarContent(current: Fixtures.current(at: now), upcoming: Fixtures.upcoming(at: now), now: now),
            width: 300
        )
    }

    func testMenuBarDuringPlannedBlock() {
        assertAppearances(
            MenuBarContent(current: Fixtures.planned(at: now), upcoming: Fixtures.upcoming(at: now), now: now),
            width: 300
        )
    }

    func testMenuBarStartingSoon() {
        // Eight minutes before the next block, with nothing under way.
        let soon = now.addingTimeInterval(52 * 60)
        let upcoming = Fixtures.blocks(around: now).filter { $0.start > soon }
        assertAppearances(MenuBarContent(current: nil, upcoming: upcoming, now: soon), width: 300)
    }

    func testMenuBarSuggestedFocus() {
        let block = Fixtures.current(at: now)!
        let untitled = Block(id: block.id, title: block.goal, goal: "Protected time", start: block.start, end: block.end, tint: block.tint, untitled: true)
        assertAppearances(
            SessionPlanView(block: untitled, suggestion: Fixtures.focusSuggestion).padding(16),
            width: 300
        )
    }

    func testMenuBarWithNothingScheduled() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now), width: 300)
    }

    func testMenuBarSignedOut() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now, isSignedIn: false), width: 300)
    }

    func testMenuBarDuringReservedTime() {
        // Reserved time shows what it is and when it ends, with no aim to set or plan to follow.
        let lunch = Block(id: "lunch", title: "Lunch with family", goal: "Run a calm week",
                          start: now.addingTimeInterval(-20 * 60), end: now.addingTimeInterval(40 * 60), tint: Fixtures.pink, reserved: true)
        assertAppearances(
            MenuBarContent(current: lunch, upcoming: Fixtures.upcoming(at: now), now: now, sessionActions: nil),
            width: 300
        )
    }

    /// A suggested focus, standing in the empty description until it's taken or set aside.
    func testFocusSuggestion() {
        let data = Fixtures.calendar
        let block = Fixtures.freshPanelBlocks.first { $0.title == nil && $0.description == nil && !$0.isIntention && !$0.reserved }!
        let actions = BlockPanelActions(
            setDescription: { _, _ in nil }, prepareAgenda: { _, _ in nil },
            suggestFocus: { _, _, _ in .failed("") }, prepareRecap: { _ in nil },
            postRecap: { _, _, _, _ in nil }, discardRecap: { _ in nil }, setTaskDone: { _, _ in nil },
            toggleDone: { _ in }, openGoal: { _ in }
        )
        assertAppearances(
            BlockPanel(
                block: block, goal: data.goal(block.goalId), goals: data.goals, description: nil,
                day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                openTaskIds: [], ended: false, now: now, actions: actions, calendar: .preview, suggestion: Fixtures.focusSuggestion
            )
            .frame(width: 320, height: 400)
            .padding(16)
            .background(Theme.background),
            width: 352, height: 432
        )
    }

    func testSignIn() {
        assertAppearances(SignInView(), width: 640, height: 360)
    }

    func testSignInWithMessage() {
        assertAppearances(
            SignInView(message: "This Google account isn't on the access list."),
            width: 640, height: 360
        )
    }

    func testWidgetSmall() {
        assertAppearances(
            CurrentBlockWidgetPreview(block: Fixtures.current(at: now), now: now),
            width: 170, height: 170
        )
    }

    /// Between blocks, and before the app has shared anything.
    func testWidgetFreeAndSignedOut() {
        let between = now.addingTimeInterval(50 * 60)
        assertAppearances(
            HStack(spacing: 12) {
                CurrentBlockWidgetPreview(block: nil, now: between, next: Fixtures.upcoming(at: now).first)
                    .frame(width: 170, height: 170)
                CurrentBlockWidgetPreview(block: nil, now: now, signedIn: false)
                    .frame(width: 170, height: 170)
            },
            width: 352, height: 170
        )
    }

    /// The widget's timeline: a block shows the moment it starts, and between blocks it says what's next.
    func testWidgetTimeline() {
        let blocks = Fixtures.blocks(around: now)
        let moments = WidgetTimeline.moments(blocks: blocks, from: now)
        XCTAssertEqual(moments.first?.date, now)
        XCTAssertEqual(moments.first?.current?.id, "current")
        // Every minute for the next hour, plus each later start and end within the day.
        XCTAssertTrue(moments.contains { $0.date == blocks[2].start && $0.current?.id == "later" })
        let afterCurrent = moments.first { $0.date == blocks[0].end }
        XCTAssertNil(afterCurrent?.current)
        XCTAssertEqual(afterCurrent?.next?.id, "next")
        XCTAssertEqual(moments.map(\.date), moments.map(\.date).sorted())
        XCTAssertEqual(moments.last?.date, blocks[2].end)
        XCTAssertNil(moments.last?.current)
        XCTAssertNil(moments.last?.next)
    }

    /// What the app writes, the widget reads back the same.
    func testSharedTodayRoundTrip() throws {
        let today = SharedToday(signedIn: true, fetchedAt: now, blocks: Fixtures.blocks(around: now))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(SharedToday.self, from: encoder.encode(today))
        XCTAssertEqual(back.blocks.map(\.id), today.blocks.map(\.id))
        XCTAssertEqual(back.blocks.first?.tint, today.blocks.first?.tint)
    }
}

/// Approximates the widget's frame for snapshots; WidgetKit itself only renders inside a widget host.
private struct CurrentBlockWidgetPreview: View {
    let block: Block?
    let now: Date
    var next: Block?
    var signedIn = true

    var body: some View {
        Group {
            if let block { CurrentBlockView(block: block, now: now) } else { NoBlockView(next: next, signedIn: signedIn) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
