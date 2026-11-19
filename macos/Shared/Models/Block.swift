import AppKit
import Foundation
import SwiftUI

/// A block of time on the calendar, as the Mac surfaces show it.
struct Block: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    /// The goal's title, or "Protected time" when the block is the goal's own time.
    let goal: String
    let start: Date
    let end: Date
    var tint: Tint? = nil
    /// For protected time: what the person wants out of the session, if they said.
    var aim: String? = nil
    /// The plan prepared for the session, if there is one.
    var agenda: SessionAgenda? = nil

    func progress(at now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    func minutesLeft(at now: Date) -> Int {
        max(Int((end.timeIntervalSince(now) / 60).rounded(.up)), 0)
    }

    func isHappening(at now: Date) -> Bool {
        start <= now && now < end
    }
}

/// A session's prepared plan, as the menu bar shows it during the session.
struct SessionAgenda: Hashable, Sendable, Codable {
    struct Item: Identifiable, Hashable, Sendable, Codable {
        let id: String
        let title: String
        let minutes: Int
        var done: Bool
    }

    let text: String
    /// The tasks it draws on, most relevant first.
    var tasks: [Item]
}

/// A goal's colour, as hex for light and dark mode (the server's palette, src/lib/goal-colors.ts).
struct Tint: Hashable, Sendable, Codable {
    let light: String
    let dark: String

    var color: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light) ?? .controlAccentColor
        })
    }
}

extension NSColor {
    /// "#rrggbb"
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}

extension Block {
    static func timeRange(_ block: Block) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(block.start.formatted(style)) – \(block.end.formatted(style))"
    }

    static func remaining(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }
}
