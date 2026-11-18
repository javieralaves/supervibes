import Foundation

/// Stand-in data for snapshot tests and the widget (until the widget can share the app's data).
enum Fixtures {
    /// A fixed moment, so snapshot tests render the same image every run.
    static let referenceNow: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Europe/Madrid")
        components.year = 2026
        components.month = 11
        components.day = 18
        components.hour = 10
        components.minute = 18
        return components.date!
    }()

    static let sky = Tint(light: "#0a8be0", dark: "#3cb8ff")
    static let pink = Tint(light: "#e6327f", dark: "#ff6fae")

    /// Today's blocks, laid out around `now`: one in progress and two still to come.
    static func blocks(around now: Date) -> [Block] {
        let minute: TimeInterval = 60
        let currentStart = now.addingTimeInterval(-48 * minute)
        let currentEnd = now.addingTimeInterval(42 * minute)
        return [
            Block(id: "current", title: "Scaffold the Mac app", goal: "Ship Supervibes for Mac",
                  start: currentStart, end: currentEnd, tint: sky),
            Block(id: "next", title: "Weekly review", goal: "Run a calm week",
                  start: currentEnd.addingTimeInterval(18 * minute),
                  end: currentEnd.addingTimeInterval(48 * minute), tint: pink),
            Block(id: "later", title: "Write the API sketch", goal: "Ship Supervibes for Mac",
                  start: currentEnd.addingTimeInterval(108 * minute),
                  end: currentEnd.addingTimeInterval(198 * minute), tint: sky),
        ]
    }

    static func current(at now: Date) -> Block? {
        blocks(around: now).first { $0.isHappening(at: now) }
    }

    static func upcoming(at now: Date) -> [Block] {
        blocks(around: now).filter { $0.start > now }
    }

    /// A month of calls to Claude, spread over the days before `referenceNow`.
    static var usageCalls: [UsageCall] {
        let features: [UsageCall.Feature] = [.progressRead, .progressRead, .recap, .agenda, .progressRead, .recap]
        let triggers = ["cron", "note", "auto", "manual", "recap", "draft"]
        let goals = ["Ship Supervibes for Mac", "Run a calm week", "Make time for movement"]
        return (0..<42).map { i in
            let feature = features[i % features.count]
            return UsageCall(
                id: "call-\(i)",
                feature: feature,
                trigger: triggers[i % triggers.count],
                goalTitle: goals[i % goals.count],
                model: "claude-sonnet-5-5",
                inputTokens: 18_000 + (i * 1_731) % 22_000,
                outputTokens: 900 + (i * 377) % 2_400,
                toolCalls: i % 4,
                durationMs: 6_000 + (i * 2_113) % 30_000,
                cost: feature == .agenda ? 0.021 + Double(i % 5) * 0.004 : 0.048 + Double(i % 7) * 0.011,
                createdAt: referenceNow.addingTimeInterval(-Double(i) * 16.5 * 3600)
            )
        }
    }
}
