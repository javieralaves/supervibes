import SwiftUI

#if os(iOS)
import UIKit

// The design system and models were written against AppKit's NSColor. On iOS these few shims
// map the parts they use onto UIColor, so the same colour code builds for both.

typealias NSColor = UIColor

extension UIColor {
    /// AppKit's appearance names, as far as the colour code asks about them.
    struct Appearance {
        enum Name { case aqua, darkAqua }
        let isDark: Bool

        func bestMatch(from names: [Name]) -> Name? {
            isDark ? (names.contains(.darkAqua) ? .darkAqua : names.first) : (names.contains(.aqua) ? .aqua : names.first)
        }
    }

    /// AppKit's `NSColor(name:dynamicProvider:)`: a colour that follows light and dark mode.
    convenience init(name: String?, dynamicProvider: @escaping @Sendable (Appearance) -> UIColor) {
        self.init { traits in dynamicProvider(Appearance(isDark: traits.userInterfaceStyle == .dark)) }
    }

    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    static var controlAccentColor: UIColor { .tintColor }

    /// AppKit's `blended(withFraction:of:)`: this colour mixed `fraction` of the way towards `color`.
    func blended(withFraction fraction: CGFloat, of color: UIColor) -> UIColor? {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1), color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        let t = min(max(fraction, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}

extension Color {
    init(nsColor: UIColor) {
        self.init(uiColor: nsColor)
    }
}

/// The Mac's pointer styles, which mean nothing under a finger: on iOS `pointerStyle` does nothing.
struct PointerStyle {
    enum FramePosition { case top, bottom, leading, trailing }
    static let link = PointerStyle()
    static let grabIdle = PointerStyle()
    static let grabActive = PointerStyle()
    static func frameResize(position: FramePosition) -> PointerStyle { PointerStyle() }
}

extension View {
    func pointerStyle(_ style: PointerStyle?) -> some View { self }
}
#endif

extension Color {
    /// The system's placeholder text colour.
    static var systemPlaceholder: Color {
        #if os(macOS)
        Color(nsColor: .placeholderTextColor)
        #else
        Color(uiColor: .placeholderText)
        #endif
    }
}

extension View {
    /// A button drawn as a link: AppKit's link style on the Mac, tinted plain text on iOS.
    @ViewBuilder func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.plain).foregroundStyle(.tint)
        #endif
    }
}

extension View {
    /// A checkbox on the Mac; iOS has no checkbox toggle, so a switch there.
    @ViewBuilder func checkboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
    }
}

extension View {
    /// Escape: the Mac's exit command, or Escape on a hardware keyboard on iOS.
    @ViewBuilder func onEscape(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        onKeyPress(.escape) { action(); return .handled }
        #endif
    }
}
