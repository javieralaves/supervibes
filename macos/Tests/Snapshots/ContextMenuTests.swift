import SwiftUI
import XCTest

/// Which view a right-click opens a menu on.
@MainActor
final class ContextMenuTests: XCTestCase {
    private func target(_ frame: CGRect, isEnabled: Bool = true, opened: @escaping (CGPoint) -> Void) -> ContextTarget {
        let target = ContextTarget()
        target.frame = frame
        target.isEnabled = isEnabled
        target.open = opened
        return target
    }

    func testOpensTheInnermostTargetUnderThePointer() {
        let center = OverlayCenter()
        var opened: [String] = []
        center.contextTargets[UUID()] = target(CGRect(x: 0, y: 0, width: 400, height: 400)) { _ in opened.append("lane") }
        center.contextTargets[UUID()] = target(CGRect(x: 20, y: 20, width: 200, height: 60)) { _ in opened.append("card") }

        XCTAssertTrue(center.openContextMenu(at: CGPoint(x: 40, y: 40)))
        XCTAssertTrue(center.openContextMenu(at: CGPoint(x: 300, y: 300)))
        XCTAssertEqual(opened, ["card", "lane"])
    }

    func testLeavesTheClickAloneWhereThereIsNothingToOpen() {
        let center = OverlayCenter()
        var opened = false
        center.contextTargets[UUID()] = target(CGRect(x: 0, y: 0, width: 100, height: 100), isEnabled: false) { _ in opened = true }

        XCTAssertFalse(center.openContextMenu(at: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(center.openContextMenu(at: CGPoint(x: 150, y: 150)))
        XCTAssertFalse(opened)
    }

    func testOpensAtThePointer() {
        let center = OverlayCenter()
        center.contextTargets[UUID()] = target(CGRect(x: 0, y: 0, width: 100, height: 100)) { point in
            center.showMenu(at: point) { EmptyView() }
        }
        XCTAssertTrue(center.openContextMenu(at: CGPoint(x: 30, y: 70)))
        guard case .point(let point) = center.presented?.placement else { return XCTFail("No menu at the pointer") }
        XCTAssertEqual(point, CGPoint(x: 30, y: 70))
    }

    func testDoesNothingUnderADialog() {
        let center = OverlayCenter()
        var opened = false
        center.contextTargets[UUID()] = target(CGRect(x: 0, y: 0, width: 100, height: 100)) { _ in opened = true }
        center.showDialog { EmptyView() }

        XCTAssertFalse(center.openContextMenu(at: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(opened)
    }

    /// A menu's rows reach the overlay layer they're drawn in, to close the menu or swap in a further choice.
    func testAMenuCanReachItsOverlays() {
        let center = OverlayCenter()
        var reached: OverlayCenter?
        center.showMenu(at: CGPoint(x: 10, y: 10)) { OverlaysProbe { reached = $0 } }
        let host = NSHostingController(rootView: Color.clear.frame(width: 200, height: 200).overlayHost(center))
        host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        host.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(reached === center)
    }
}

private struct OverlaysProbe: View {
    let report: (OverlayCenter?) -> Void
    @Environment(\.overlays) private var overlays

    var body: some View {
        Color.clear.frame(width: 10, height: 10).onAppear { report(overlays) }
    }
}
