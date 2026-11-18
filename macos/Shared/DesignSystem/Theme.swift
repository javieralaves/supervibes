import AppKit
import CoreText
import SwiftUI

/*
 * Supervibes' design tokens, ported from src/app/globals.css: calm, cool, monochrome, with goal
 * colours as the only accent. Keep the two in step: a token changed there changes here.
 */

enum Theme {
    // MARK: Colours (light / dark, as in globals.css)

    static let background = Color.adaptive(light: .rgb(0xf6f7f8), dark: .rgb(0x0b0c0e))
    static let foreground = Color.adaptive(light: .rgb(0x0f1114), dark: .rgb(0xeceef1))
    static let muted = Color.adaptive(light: .rgb(0x676c75), dark: .rgb(0x8d939c))
    static let card = Color.adaptive(light: .rgb(0xffffff), dark: .rgb(0x131417))
    static let cardBorder = Color.adaptive(light: .rgb(0x0f1114, alpha: 0.08), dark: .rgb(0xffffff, alpha: 0.07))
    static let lineStrong = Color.adaptive(light: .rgb(0x0f1114, alpha: 0.16), dark: .rgb(0xffffff, alpha: 0.16))
    static let wash = Color.adaptive(light: .rgb(0x0f1114, alpha: 0.04), dark: .rgb(0xffffff, alpha: 0.04))
    /// Behind the app's window: the rail sits on it, a shade darker than the page.
    static let shell = Color.adaptive(light: .rgb(0xeceef1), dark: .rgb(0x060708))
    /// Chart series, in fixed order.
    static let viz1 = Color.adaptive(light: .rgb(0x2a78d6), dark: .rgb(0x3987e5))
    static let viz2 = Color.adaptive(light: .rgb(0xeb6834), dark: .rgb(0xd95926))
    static let viz3 = Color.adaptive(light: .rgb(0x1baf7a), dark: .rgb(0x199e70))
    /// Tailwind red-600 / red-400, for errors.
    static let danger = Color.adaptive(light: .rgb(0xdc2626), dark: .rgb(0xf87171))

    /// `foreground` at an opacity, like Tailwind's `bg-foreground/[.08]`.
    static func foreground(_ opacity: Double) -> Color {
        Color.adaptive(light: .rgb(0x0f1114, alpha: opacity), dark: .rgb(0xeceef1, alpha: opacity))
    }

    // MARK: Type

    static let fontFamily = "Instrument Sans"
}

// MARK: - Font

extension Font {
    /// Instrument Sans at `size`, like the web app's `font-sans`.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Fonts.registerOnce()
        return .custom(Theme.fontFamily, fixedSize: size).weight(weight)
    }
}

/// Tailwind's type scale (size, line height), for matching the web app's `text-*` classes.
enum TextSize: Equatable {
    case xs, sm, base, lg, xl, xl2, xl3, xl4
    case px(CGFloat)

    var size: CGFloat {
        switch self {
        case .xs: 12
        case .sm: 14
        case .base: 16
        case .lg: 18
        case .xl: 20
        case .xl2: 24
        case .xl3: 30
        case .xl4: 36
        case .px(let value): value
        }
    }

    /// Extra space between lines so the line box matches Tailwind's line height.
    var lineSpacing: CGFloat {
        let lineHeight: CGFloat = switch self {
        case .xs: 16
        case .sm: 20
        case .base: 24
        case .lg, .xl: 28
        case .xl2: 32
        case .xl3: 36
        case .xl4: 40
        case .px(let value): value * 1.5
        }
        return max(lineHeight - size * 1.2, 0)
    }
}

extension View {
    /// Text in the app font at a Tailwind size, with optional tracking in em (`tracking-[-0.03em]`).
    func appText(_ size: TextSize, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
        font(.app(size.size, weight))
            .tracking(tracking * size.size)
            .lineSpacing(size.lineSpacing)
    }
}

/// Registers the bundled Instrument Sans with the process. Runs once, from whichever bundle
/// this code is compiled into (the app, the widget or the tests).
enum Fonts {
    private final class BundleToken {}
    static let bundle = Bundle(for: BundleToken.self)

    nonisolated(unsafe) private static var registered = false
    private static let lock = NSLock()

    static func registerOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        registered = true
        guard let url = bundle.url(forResource: "InstrumentSans-Latin", withExtension: "woff2") else {
            Log.app.error("Instrument Sans isn't in the bundle")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            Log.app.error("Couldn't register Instrument Sans: \(error?.takeRetainedValue().localizedDescription ?? "-", privacy: .public)")
        }
    }
}

// MARK: - Icons

/// The Hugeicons the app uses, generated into Icons.xcassets by scripts/mac-icons.mjs.
enum Icon: String {
    case target = "Target02-1_8"
    case calendar = "Calendar03-1_8"
    case plug = "Plug01-1_8"
    case settings = "Settings02-1_5"
    case settingsBold = "Settings02-1_8"
    case logout = "Logout01-1_5"
    case moon = "Moon02-1_5"
    case sun = "Sun03-1_5"
    case tick = "Tick02-1_5"
    case chevronDown = "ArrowDown01-1_5"
    case more = "MoreHorizontal-1_5"
    case add = "Add01-1_5"
    case arrowRight = "ArrowRight01-1_5"
    case close = "Cancel01-1_5"
    case search = "Search01-1_5"
    case delete = "Delete02-1_5"
    case calendarSmall = "Calendar03-1_5"
    case arrowLeft = "ArrowLeft01-1_5"
    case edit = "PencilEdit02-1_5"
    case note = "Note01-1_5"
    case checklist = "CheckList-1_5"
    case clock = "Clock01-1_5"
    case dashedCircle = "DashedLineCircle-1_5"
    case grip = "DragDropVertical-1_5"
    case view = "View-1_5"
    case flag = "Flag02-1_5"
    case tickBold = "Tick02-2_5"
    case tickHeavy = "Tick02-3"
    case reopen = "ArrowTurnBackward-1_5"
    case refresh = "Refresh01-1_5"
    case unlink = "Unlink04-1_5"
    case linearMark = "LinearMark"
    case githubMark = "GitHubMark"
    case granolaMark = "GranolaMark"

    func image(size: CGFloat) -> some View {
        Image(rawValue, bundle: Fonts.bundle)
            .renderingMode(self == .granolaMark ? .original : .template)
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Rendering

extension EnvironmentValues {
    /// Set by snapshot tests: views that would animate on their own (spinners) stay still, so
    /// every render is the same image.
    @Entry var staticRendering = false
}

// MARK: - Dates

extension Date {
    /// Dates as the web app writes them (it formats in US English whatever the device's locale):
    /// "Nov 9, 2026".
    var webDay: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US")))
    }

    /// "Nov 9".
    var webMonthDay: String {
        formatted(.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US")))
    }

    /// "Nov 9, 10:18 AM".
    var webMonthDayTime: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(Locale(identifier: "en_US")))
    }
}

// MARK: - Colour helpers

extension Color {
    /// A colour that follows the appearance it's drawn in.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}
