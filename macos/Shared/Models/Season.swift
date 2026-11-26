import Foundation

/// A stretch of weeks, 13 by default, in which the person closes part of the gap in a few areas (src/lib/seasons.ts).
/// One is being set up (a draft) or running (active) at a time; it ends by itself after its last day.
struct Season: Identifiable, Hashable, Sendable {
    enum State: String, Sendable { case draft, active, ended }

    let id: String
    var name: String
    /// "YYYY-MM-DD", both included.
    var startsOn: String
    var endsOn: String
    var state: State
    /// The week today falls in, 1 first; 0 before it starts.
    var week: Int
    var weeks: Int
    /// The worst of its chosen quests' efforts; nil with none yet.
    var status: GoalStatus?
    /// A draft's candidates, one per area read, and the chosen ones first; a running season's chosen ones.
    var quests: [Quest]

    /// Its chosen quests, in their order.
    var chosen: [Quest] { quests.filter(\.chosen).sorted { $0.position < $1.position } }

    /// "Nov 30 – Feb 28".
    var range: String { "\(CalendarDay.monthDay(startsOn)) – \(CalendarDay.monthDay(endsOn))" }
    /// "Feb 28".
    var endLabel: String { CalendarDay.monthDay(endsOn) }
}

/// Part of an area's gap a season sets out to close: where it's headed by the season's end (its name), where it
/// starts, and how much of the gap that is.
struct Quest: Identifiable, Hashable, Sendable {
    let id: String
    let seasonId: String
    let areaId: String
    /// Where it's headed by the season's end; also its name.
    var title: String
    /// Where it starts.
    var fromText: String
    /// How much of the area's gap the season would close, 5 to 95.
    var reach: Int
    var chosen: Bool
    /// Its number among the chosen, from 1 (0 while not chosen).
    var position: Int
    /// The projects and practices that move it.
    var goalIds: [String]
    /// The worst of its goals' statuses; nil with none yet.
    var effort: GoalStatus?

    /// "From not looking at it at all".
    var fromLine: String {
        guard let first = fromText.first else { return "" }
        return "From \(first.lowercased())\(fromText.dropFirst())"
    }

    /// "about a third of the way", for how far the season goes along the gap.
    var reachWords: String {
        switch reach {
        case ..<20: "a first step of the way"
        case ..<30: "about a quarter of the way"
        case ..<42: "about a third of the way"
        case ..<58: "about half of the way"
        case ..<72: "about two thirds of the way"
        default: "most of the way"
        }
    }
}

/// One of the usual life areas, offered when choosing a season's areas: a fixed list (POPULAR_AREAS in
/// src/lib/season-schema.ts), less those the person has already.
struct PopularArea: Hashable, Sendable {
    let name: String
    let icon: String
    let line: String
}

/// A project or practice Supervibes suggests for a quest; nothing is saved until it's added.
struct QuestSuggestion: Hashable, Sendable {
    let kind: GoalKind
    let title: String
    /// For a project, what done looks like; for a practice, how often and why.
    let line: String
    /// For a practice, how many times a week.
    let perWeek: Int?
}

/// The seasons the person has now (CurrentSeasons in src/lib/api/routes/seasons.ts).
struct CurrentSeasons: Hashable, Sendable {
    let today: String
    var active: Season?
    var draft: Season?
    /// One that ended in the last four weeks, to say so on Life.
    var ended: Season?
    var popularAreas: [PopularArea]
}

/// A season's name and days, as the person edits them (seasonInputSchema in src/lib/season-schema.ts).
struct SeasonInput: Hashable, Sendable {
    var name: String
    var startsOn: String
    var endsOn: String

    static let maxName = 40
    /// Under six months.
    static let maxDays = 26 * 7

    init(name: String, startsOn: String, endsOn: String) {
        self.name = name
        self.startsOn = startsOn
        self.endsOn = endsOn
    }

    init(editing season: Season) {
        self.init(name: season.name, startsOn: season.startsOn, endsOn: season.endsOn)
    }

    /// The server's checks, with its messages, so they show before anything is sent.
    var problem: String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the season a name." }
        if name.count > Self.maxName { return "Keep the name under \(Self.maxName) characters." }
        if endsOn <= startsOn { return "A season ends after it starts." }
        if CalendarDay.daysBetween(startsOn, endsOn) >= Self.maxDays { return "Keep a season under six months." }
        return nil
    }
}

extension CalendarDay {
    /// "Feb 28", with no year.
    static func monthDay(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
    }

    /// "Monday, Nov 30".
    static func weekdayMonthDay(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.wide).month(.abbreviated).day())
    }

    /// Whole days from `from` to `to`; negative when `to` is earlier.
    static func daysBetween(_ from: String, _ to: String) -> Int {
        daysUntil(to, today: from)
    }
}

extension QuestSuggestion {
    /// A goal icon for it, from the palette's labels and keywords matched against its words; the default otherwise.
    var icon: String {
        let words = Set(title.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
        var best: (name: String, score: Int)?
        for group in GoalPalette.iconGroups {
            for icon in group.icons {
                let terms = Set((icon.label + " " + icon.keywords).lowercased().split { !$0.isLetter }.map(String.init))
                let score = words.filter { word in terms.contains { $0.hasPrefix(word) || word.hasPrefix($0) && $0.count > 3 } }.count
                if score > (best?.score ?? 0) { best = (icon.name, score) }
            }
        }
        return best?.name ?? GoalPalette.defaultIcon
    }

    /// A colour for it, the same each time for the same words.
    var color: String {
        let colors = GoalPalette.colors.map(\.key)
        let sum = title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors.isEmpty ? GoalPalette.defaultColor : colors[sum % colors.count]
    }

    /// The goal it becomes once added, in the quest's area.
    func input(areaId: String) -> GoalInput {
        var input = GoalInput(kind: kind)
        input.title = String(title.prefix(GoalInput.maxTitle))
        input.icon = icon
        input.color = color
        input.areaId = areaId
        if kind == .practice { input.perWeek = perWeek ?? 1 } else { input.description = line }
        return input
    }
}
