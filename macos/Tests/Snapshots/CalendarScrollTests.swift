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
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return scrollViews(in: window.contentView!).first
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}
