import AppKit
import SwiftUI
import XCTest

/// The day and the week open scrolled to about an hour before now. Snapshots lay the grid out
/// whole, so this hosts each in a real window and reads where its scroll view landed.
@MainActor
final class CalendarScrollTests: XCTestCase {
    /// Fixtures.referenceNow is 10:18, so both open with 9 AM at the top.
    private let focusHour = 9

    func testDayOpensOnNow() {
        XCTAssertEqual(scrollOffset(isWeek: false), DayGrid.y(focusHour * 60) - DayGrid.pad)
    }

    func testWeekOpensOnNow() {
        XCTAssertEqual(scrollOffset(isWeek: true), WeekGrid.y(focusHour * 60) - WeekGrid.pad)
    }

    private func scrollOffset(isWeek: Bool) -> CGFloat? {
        let view = DayView(data: Fixtures.calendar, offset: 0, now: Fixtures.referenceNow, isWeek: isWeek, onSetWeek: { _ in })
            .background(Theme.background)
            .frame(width: 1400, height: 760)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        return scrollViews(in: window.contentView!).first?.documentVisibleRect.origin.y
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }
}
