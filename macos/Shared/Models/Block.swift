import Foundation

/// A block of time on the calendar, as the Mac surfaces show it.
/// Placeholder shape until the API exists; it will be generated from the server's schema.
struct Block: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let goal: String
    let start: Date
    let end: Date

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
