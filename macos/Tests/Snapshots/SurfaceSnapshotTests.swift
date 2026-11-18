import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Renders the native surfaces to PNGs in __Snapshots__/, in light and dark.
/// Reference images are checked in; a changed view fails until it's re-recorded (scripts/snapshot.sh --record).
@MainActor
final class SurfaceSnapshotTests: XCTestCase {
    private let now = Fixtures.referenceNow

    func testMenuBarDuringBlock() {
        assertAppearances(
            MenuBarContent(current: Fixtures.current(at: now), upcoming: Fixtures.upcoming(at: now), now: now),
            width: 300
        )
    }

    func testMenuBarWithNothingScheduled() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now), width: 300)
    }

    func testMenuBarSignedOut() {
        assertAppearances(MenuBarContent(current: nil, upcoming: [], now: now, isSignedIn: false), width: 300)
    }

    func testSettingsPage() {
        let settings = SleepSettings(sleepStart: 23 * 60 + 30, wakeTime: 8 * 60, clock: .twelveHour)
        assertAppearances(
            SettingsPage(
                settings: .constant(settings),
                status: (.sleep, .saved),
                usage: UsageSummary(calls: Fixtures.usageCalls, today: now)
            )
            .background(Theme.background),
            width: 900, height: 2600
        )
    }

    func testSettingsPageWithProblem() {
        let settings = SleepSettings(sleepStart: 8 * 60, wakeTime: 8 * 60, clock: nil)
        assertAppearances(
            SettingsPage(settings: .constant(settings), status: (.sleep, .failed(settings.problem!)), usage: nil)
                .background(Theme.background),
            width: 900, height: 900
        )
    }

    func testShellWithSettings() {
        let account = RailAccount(name: "Javi", email: "you@example.com", imageURL: nil)
        let settings = SleepSettings(sleepStart: 23 * 60 + 30, wakeTime: 8 * 60, clock: .twelveHour)
        assertAppearances(
            HStack(spacing: 0) {
                Rail(active: nil, account: account, topInset: 28)
                AppWindowFrame {
                    ZStack {
                        Backdrop()
                        SettingsPage(settings: .constant(settings), usage: UsageSummary(calls: Fixtures.usageCalls, today: now))
                    }
                }
            }
            .background(Theme.shell),
            width: 1280, height: 820
        )
    }

    func testRailAndAccountMenu() {
        let account = RailAccount(name: "Javi", email: "you@example.com", imageURL: nil)
        assertAppearances(
            HStack(alignment: .bottom, spacing: 12) {
                Rail(active: .calendar, account: account, isMenuOpen: true)
                AccountMenu(account: account).padding(.bottom, 12)
            }
            .frame(height: 360, alignment: .leading)
            .background(Theme.shell),
            width: 360, height: 360
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
}

/// Approximates the widget's frame for snapshots; WidgetKit itself only renders inside a widget host.
private struct CurrentBlockWidgetPreview: View {
    let block: Block?
    let now: Date

    var body: some View {
        Group {
            if let block { CurrentBlockView(block: block, now: now) } else { NoBlockView() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension XCTestCase {
    /// Snapshots `view` once per appearance, named `<test>.light.png` and `<test>.dark.png`.
    /// Height defaults to whatever the view needs at `width`.
    @MainActor
    func assertAppearances<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingController(
                rootView: view
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            host.view.appearance = NSAppearance(named: appearance)
            let fitting = host.sizeThatFits(in: CGSize(width: width, height: height ?? 2000))
            let size = CGSize(width: width, height: height ?? ceil(fitting.height))
            host.view.frame = CGRect(origin: .zero, size: size)
            assertSnapshot(of: host, as: .image(size: size), named: name, file: file, testName: testName, line: line)
        }
    }
}
