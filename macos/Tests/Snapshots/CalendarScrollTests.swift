import AppKit
import SwiftUI
import XCTest

/// The day and the week open scrolled to about an hour before now, at the hour height last pinched
/// to. Snapshots lay the grid out whole, so this hosts each in a real window and reads its scroll view.
@MainActor
final class CalendarScrollTests: XCTestCase {
    /// Fixtures.referenceNow is 10:18, so both open with 9 AM at the top.
    private let focusHour = 9

    func testDayOpensOnNow() {
        XCTAssertEqual(scrollOffset(isWeek: false), DayGrid.standard.y(focusHour * 60) - DayGrid.pad)
    }

    func testWeekOpensOnNow() {
        XCTAssertEqual(scrollOffset(isWeek: true), WeekGrid.standard.y(focusHour * 60) - WeekGrid.pad)
    }

    func testDayOpensAtPinchedHeight() {
        let grid = HourGrid(hour: 88, pad: DayGrid.pad)
        let scroll = scrollView(isWeek: false, dayHour: 88)
        XCTAssertEqual(scroll?.documentView?.frame.height, grid.height)
        XCTAssertEqual(scroll?.documentVisibleRect.origin.y, grid.y(focusHour * 60) - DayGrid.pad)
    }

    func testWeekOpensAtPinchedHeight() {
        let grid = HourGrid(hour: 100, pad: WeekGrid.pad)
        let scroll = scrollView(isWeek: true, weekHour: 100)
        XCTAssertEqual(scroll?.documentView?.frame.height, grid.height)
        XCTAssertEqual(scroll?.documentVisibleRect.origin.y, grid.y(focusHour * 60) - WeekGrid.pad)
    }

    func testSavedHeightBelowWholeDayIsHeldToIt() {
        // An hour of 4pt would leave the day short of the view; it stops at the whole day in view.
        let scroll = scrollView(isWeek: false, dayHour: 4)
        XCTAssertEqual(scroll?.documentView?.frame.height ?? 0, scroll?.contentView.bounds.height ?? -1, accuracy: 1)
    }

    func testPinchKeepsTimeInPlace() {
        // 10 AM sits 200pt down the view; zoomed out to half, it's still 200pt down.
        let zoomed = HourGrid(hour: DayGrid.hour / 2, pad: DayGrid.pad)
        let scrollY = zoomed.scrollY(keeping: 600, at: 200, viewport: 600)
        XCTAssertEqual(zoomed.y(600) - scrollY, 200)
    }

    func testPinchStaysWithinWhatScrolls() {
        let grid = DayGrid.standard
        XCTAssertEqual(grid.scrollY(keeping: 30, at: 400, viewport: 600), 0)
        XCTAssertEqual(grid.scrollY(keeping: 23 * 60 + 50, at: 0, viewport: 600), grid.height - 600)
    }

    func testPinchRange() {
        let range = HourGrid.range(viewport: 600, pad: DayGrid.pad, most: DayGrid.maxHour)
        XCTAssertEqual(range.lowerBound, (600 - 24) / 24)
        XCTAssertEqual(range.upperBound, DayGrid.hour * 2)
    }

    func testTwoFingersSidewaysMoveTheWeekByWholeDays() {
        var moved = 0
        let window = weekWindow { moved += $0 }
        defer { window.orderOut(nil); window.contentView = nil }
        let hours = scrollViews(in: window.contentView!).first
        let top = hours?.documentVisibleRect.origin.y

        // Fingers moving left, 1.6 columns' worth (the week is 1400pt less its 52pt gutter).
        let column = (1400 - WeekGrid.gutter) / 7
        swipe(in: window, dx: -column * 1.6, dy: 3)

        // Two days on (past half a column the next day leads), and the hours stayed put.
        XCTAssertEqual(moved, 2)
        XCTAssertEqual(hours?.documentVisibleRect.origin.y, top)
    }

    func testTwoFingersDownLeaveTheDaysAlone() {
        var moved = 0
        let window = weekWindow { moved += $0 }
        defer { window.orderOut(nil); window.contentView = nil }
        swipe(in: window, dx: 20, dy: -300)
        XCTAssertEqual(moved, 0)
    }

    /// The week in a window, scrolling sideways into `onStepWeek`.
    private func weekWindow(onStepWeek: @escaping (Int) -> Void) -> NSWindow {
        let view = DayView(data: Fixtures.calendar, offset: 0, now: Fixtures.referenceNow, onStepWeek: onStepWeek,
                           isWeek: true, onSetWeek: { _ in })
            .background(Theme.background)
            .frame(width: 1400, height: 760)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return window
    }

    /// A trackpad gesture over the middle of the window: fingers down, ten moves adding up to
    /// `dx`, `dy`, and up, with no momentum.
    private func swipe(in window: NSWindow, dx: CGFloat, dy: CGFloat) {
        let point = NSPoint(x: 700, y: 300)
        // Quartz's scroll phases: began 1, changed 2, ended 4.
        func send(_ phase: Int64, _ x: CGFloat, _ y: CGFloat) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                   wheel1: Int32(y.rounded()), wheel2: Int32(x.rounded()), wheel3: 0) else { return }
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(y))
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(x))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.location = window.convertPoint(toScreen: point).flipped(onScreenOf: window)
            // Without a window: its location is on the screen, over the week.
            guard let event = NSEvent(cgEvent: cg) else { return }
            NSApp.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        send(1, dx / 10, dy / 10)
        for _ in 1..<10 { send(2, dx / 10, dy / 10) }
        send(4, 0, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    private func scrollOffset(isWeek: Bool) -> CGFloat? {
        scrollView(isWeek: isWeek)?.documentVisibleRect.origin.y
    }

    private func scrollView(isWeek: Bool, dayHour: CGFloat? = nil, weekHour: CGFloat? = nil) -> NSScrollView? {
        let view = DayView(data: Fixtures.calendar, offset: 0, now: Fixtures.referenceNow, isWeek: isWeek, onSetWeek: { _ in },
                           dayHour: dayHour.map { .constant($0) }, weekHour: weekHour.map { .constant($0) })
            .background(Theme.background)
            .frame(width: 1400, height: 760)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return scrollViews(in: window.contentView!).first
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}

private extension NSPoint {
    /// From AppKit's screen space (origin bottom left) to Quartz's (origin top left).
    func flipped(onScreenOf window: NSWindow) -> CGPoint {
        CGPoint(x: x, y: (NSScreen.screens.first?.frame.height ?? 0) - y)
    }
}
