import Foundation

/// One recorded call to Claude, as the Usage tab sees it.
struct UsageCall: Identifiable, Hashable, Sendable {
    enum Feature: String, CaseIterable, Hashable, Sendable {
        case progressRead = "progress_read"
        case recap
        case agenda
        case areaRead = "area_read"
        case gapRead = "gap_read"
        case standRead = "stand_read"
        case questSuggest = "quest_suggest"
        case seasonRead = "season_read"
        case questRead = "quest_read"

        var label: String {
            switch self {
            case .progressRead: "Progress reads"
            case .recap: "Session recaps"
            case .agenda: "Agendas"
            case .areaRead: "Area reads"
            case .gapRead: "Gaps named"
            case .standRead: "Season setup reads"
            case .questSuggest: "Quest suggestions"
            case .seasonRead: "Season reads"
            case .questRead: "Quest reads"
            }
        }
    }

    let id: String
    let feature: Feature
    /// What set it off: "cron", "manual", …
    let trigger: String
    let goalTitle: String?
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let toolCalls: Int
    let durationMs: Int
    /// The last stop reason, e.g. "end_turn", or "error".
    var outcome: String = "end_turn"
    /// Dollars, or nil for a model without a known price.
    let cost: Double?
    let createdAt: Date

    var triggerLabel: String { Self.triggerLabel(trigger) }

    static func triggerLabel(_ trigger: String) -> String {
        switch trigger {
        case "manual": "Update status"
        case "note": "After a note"
        case "recap": "After a recap"
        case "cron": "Daily read"
        case "draft": "First draft"
        case "redraft": "Drafted again"
        case "auto": "After a session"
        default: trigger
        }
    }
}

/// Totals and breakdowns for the Usage tab, worked out on this Mac so days are local ones.
struct UsageSummary: Sendable {
    /// One day's spend, split by feature.
    struct Day: Identifiable, Hashable, Sendable {
        struct Part: Hashable, Sendable {
            let feature: UsageCall.Feature
            var cost: Double = 0
            var calls: Int = 0
        }

        var id: Date { day }
        let day: Date
        /// One per feature, in fixed order.
        let parts: [Part]
        var total: Double { parts.reduce(0) { $0 + $1.cost } }
    }

    /// Calls for one feature and trigger.
    struct FeatureRow: Identifiable, Hashable, Sendable {
        var id: String { "\(feature.rawValue):\(trigger)" }
        let feature: UsageCall.Feature
        let trigger: String
        let calls: Int
        let avgInput: Double
        let avgOutput: Double
        let avgTools: Double
        let avgSeconds: Double
        let avgCost: Double
        let total: Double
    }

    struct GoalRow: Identifiable, Hashable, Sendable {
        var id: String { title }
        let title: String
        let calls: Int
        let total: Double
    }

    let days: Int
    let calls: [UsageCall]
    let total: Double
    let unpriced: Int
    let inputTokens: Int
    let outputTokens: Int
    let daily: [Day]
    let byFeature: [FeatureRow]
    let byGoal: [GoalRow]

    init(calls: [UsageCall], days: Int = 30, today: Date = Date(), calendar: Calendar = .current) {
        self.days = days
        self.calls = calls
        total = calls.reduce(0) { $0 + ($1.cost ?? 0) }
        unpriced = calls.filter { $0.cost == nil }.count
        inputTokens = calls.reduce(0) { $0 + $1.inputTokens }
        outputTokens = calls.reduce(0) { $0 + $1.outputTokens }

        let start = calendar.startOfDay(for: today)
        let dayList = (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }
        var parts: [Date: [UsageCall.Feature: Day.Part]] = [:]
        for call in calls {
            let day = calendar.startOfDay(for: call.createdAt)
            var part = parts[day]?[call.feature] ?? Day.Part(feature: call.feature)
            part.cost += call.cost ?? 0
            part.calls += 1
            parts[day, default: [:]][call.feature] = part
        }
        daily = dayList.map { day in
            Day(day: day, parts: UsageCall.Feature.allCases.map { parts[day]?[$0] ?? Day.Part(feature: $0) })
        }

        // Per feature (in fixed order), then per trigger, biggest spend first; as the web app does.
        byFeature = UsageCall.Feature.allCases.flatMap { feature -> [FeatureRow] in
            let mine = calls.filter { $0.feature == feature }
            let triggers = mine.reduce(into: [String]()) { if !$0.contains($1.trigger) { $0.append($1.trigger) } }
            return triggers.map { trigger -> FeatureRow in
            let group = mine.filter { $0.trigger == trigger }
            let n = Double(group.count)
            let total = group.reduce(0) { $0 + ($1.cost ?? 0) }
            return FeatureRow(
                feature: feature,
                trigger: UsageCall.triggerLabel(trigger),
                calls: group.count,
                avgInput: Double(group.reduce(0) { $0 + $1.inputTokens }) / n,
                avgOutput: Double(group.reduce(0) { $0 + $1.outputTokens }) / n,
                avgTools: Double(group.reduce(0) { $0 + $1.toolCalls }) / n,
                avgSeconds: Double(group.reduce(0) { $0 + $1.durationMs }) / n / 1000,
                avgCost: total / n,
                total: total
            )
            }
            .sorted { $0.total > $1.total }
        }

        byGoal = Dictionary(grouping: calls) { $0.goalTitle ?? "Deleted goals" }
            .map { GoalRow(title: $0.key, calls: $0.value.count, total: $0.value.reduce(0) { $0 + ($1.cost ?? 0) }) }
            // Ties go alphabetically, so the order doesn't shuffle between loads.
            .sorted { ($0.total, $1.title) > ($1.total, $0.title) }
    }

    var averageCost: Double { calls.isEmpty ? 0 : total / Double(calls.count) }

    /// "$0", "$0.0042", "$0.078", "$1.23", like the web app.
    static func money(_ value: Double?) -> String {
        guard let value else { return "–" }
        if value == 0 { return "$0" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.3f", value) }
        return String(format: "$%.2f", value)
    }

    /// "6.9s", "11s".
    static func seconds(milliseconds: Double) -> String {
        String(format: milliseconds < 10_000 ? "%.1fs" : "%.0fs", milliseconds / 1000)
    }

    /// 1, 2 or 5 times a power of ten, at or above `x`; for round chart gridlines.
    static func niceStep(_ x: Double) -> Double {
        let power = pow(10, floor(log10(x)))
        let n = x / power
        return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * power
    }

    /// "1.2M", "34.5k", "812".
    static func tokens(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", value / 1_000) }
        return String(Int(value.rounded()))
    }
}
