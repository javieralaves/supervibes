import Foundation

/*
 * First run's shared start, before Life opens: a welcome, emptying the plate in your own words, checking how it was
 * sorted into projects and practices in the parts of life they sit in, and choosing how far ahead to look. The server
 * side is src/lib/first-run.ts; the design is the First run page in supervibes-design.
 */

/// Where someone is in the shared start.
enum FirstRunStep: Int, CaseIterable, Hashable, Sendable {
    case welcome, plate, sorted, whatMatters
    /// Route 2: choosing up to three focuses, then the season they make.
    case focus, season
    /// Every route: the way into the week, then the week itself.
    case weekIntro, week
}

/// The three ways ahead from What matters. Step back first isn't built yet; for now it opens the nearest thing the app
/// already has.
enum FirstRunChoice: String, CaseIterable, Hashable, Sendable {
    /// Just this week: straight to planning the week.
    case week
    /// The next few months: up to three focuses as quests.
    case season
    /// Step back first: where each area stands, its gaps as quests.
    case stepBack

    /// The row of steps once this way is chosen; every route ends in Your week.
    var steps: [String] {
        switch self {
        case .week: ["Your plate", "Sorted", "What matters", "Your week"]
        case .season: ["Your plate", "Sorted", "What matters", "Focus", "Your week"]
        case .stepBack: ["Your plate", "Sorted", "What matters", "Areas", "Quests", "Your week"]
        }
    }
}

/// One thing from the plate, sorted: a project or a practice, with what helps place it.
struct PlateItem: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Hashable, Codable, Sendable { case project, practice }

    /// Local only, for lists; the server makes the real one on save.
    let id: String
    var title: String
    var kind: Kind
    /// A few words they said: "Before Q1 planning", "In February, with Marta".
    var detail: String?
    /// A practice's times a week; nil until said (the app asks before saving).
    var perWeek: Int?
    /// A project's done-by day, "YYYY-MM-DD".
    var targetDate: String?
    var icon: String
    var color: String
    /// One-off things to do on a project, saved to Later.
    var tasks: [String]

    var isPractice: Bool { kind == .practice }
}

/// A part of life, with what was sorted into it.
struct PlateArea: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var icon: String
    var items: [PlateItem]
}

/// The plate as sorted, before it's made.
struct SortedPlate: Hashable, Codable, Sendable {
    var areas: [PlateArea]

    var items: [PlateItem] { areas.flatMap(\.items) }
    /// Practices that still need a rhythm before saving.
    var needsRhythm: [PlateItem] { items.filter { $0.isPractice && $0.perWeek == nil } }
    /// Enough on the plate that the next step is about what can wait, not what to do with the room.
    var isHeavy: Bool { items.count >= 6 }

    mutating func setPerWeek(_ perWeek: Int, for itemId: String) {
        for a in areas.indices {
            if let i = areas[a].items.firstIndex(where: { $0.id == itemId }) {
                areas[a].items[i].perWeek = perWeek
            }
        }
    }
}

/// Everything the shared start's screens show, so they can be drawn from fixtures.
struct FirstRunState: Hashable, Sendable {
    var step: FirstRunStep = .welcome
    var firstName: String
    var plateText = ""
    var sorted: SortedPlate?
    var isBusy = false
    var error: String?
    /// The last day of a season starting next Monday, for "until February".
    var seasonEnd: Date
    /// The way ahead chosen at What matters.
    var route: FirstRunChoice = .week
    /// Route 2's board, once it's opened.
    var board: FocusBoard?
    /// Route 2's season once it's started, so going back and on again doesn't start it twice.
    var seasonStarted = false

    var season: SeasonSpan { SeasonSpan(endsOn: seasonEnd) }
}
