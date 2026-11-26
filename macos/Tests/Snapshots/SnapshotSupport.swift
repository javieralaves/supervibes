import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// The snapshot classes render the native surfaces to PNGs in __Snapshots__/<Class>/, in light and dark.
/// Reference images are checked in; a changed view fails until it's re-recorded (scripts/snapshot.sh --record).
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
        Self.prepareFonts()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingController(
                rootView: view
                    .environment(\.staticRendering, true)
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .windowBackgroundColor))
            )
            host.view.appearance = NSAppearance(named: appearance)
            let fitting = host.sizeThatFits(in: CGSize(width: width, height: height ?? 2000))
            let size = CGSize(width: width, height: height ?? ceil(fitting.height))
            host.view.frame = CGRect(origin: .zero, size: size)
            settleLayout(host.view)
            // Rendering isn't byte-for-byte the same from run to run (text antialiasing, mostly), so
            // an exact match failed on changes no one could see. A pixel counts as the same within
            // 2% perceptual difference, and up to 1% of pixels may differ beyond that.
            assertSnapshot(
                of: host, as: .image(precision: Self.snapshotPrecision, perceptualPrecision: Self.snapshotPerceptualPrecision, size: size),
                named: name, file: file, testName: testName, line: line
            )
        }
    }

    /// The share of pixels that must match, and how close a pixel must be to count as matching.
    nonisolated static var snapshotPrecision: Float { 0.99 }
    nonisolated static var snapshotPerceptualPrecision: Float { 0.98 }

    @MainActor private static var fontsReady = false

    /// AppKit-backed controls, like an empty multi-line TextField, take their height from the font
    /// as AppKit sees it. The bundled font registers on first use, and AppKit only picks it up on a
    /// later turn of the run loop, so a field measured before that got the system font's line
    /// height, and everything below it moved from run to run. So the font is registered before
    /// any view is measured, with a moment for AppKit to catch up.
    @MainActor private static func prepareFonts() {
        guard !fontsReady else { return }
        fontsReady = true
        Fonts.registerOnce()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    /// Lets a view finish laying out before it's drawn; AppKit-backed controls settle their size on a later pass.
    @MainActor private func settleLayout(_ view: NSView) {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        view.layoutSubtreeIfNeeded()
    }
}
