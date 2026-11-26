import Foundation

/// Where starting a season is: choosing areas, where each stands (one at a time), choosing the focus, how each quest
/// moves (one at a time), and the review.
enum SeasonSetupStep: Hashable, Sendable {
    case areas
    case stand(Int)
    case focus
    case how(Int)
    case review
}

/// An area picked on Choose your areas: one of the person's, a popular one, or one they named, made on Continue.
enum AreaPick: Hashable, Sendable {
    case area(String)
    case popular(String)
    case custom(String)
}

/// Everything starting a season shows, as the app's SeasonSetupModel keeps it, so each step draws from plain data.
struct SeasonSetupState: Hashable, Sendable {
    var season: Season
    var today: String
    /// The person's areas, in order, with their words and gaps.
    var areas: [Area]
    /// Their projects and practices, to link.
    var goals: [Goal]
    /// The usual life areas they don't have yet.
    var popular: [PopularArea]
    /// Picked on the first step, in order. After it, only `.area`.
    var picked: [AreaPick]
    var step: SeasonSetupStep = .areas

    /// Saving or moving on.
    var isBusy = false
    /// Why the last step didn't go through.
    var error: String?
    /// The area whose stand is being read.
    var reading: String?
    /// Suggestions for each quest, once asked for.
    var suggestions: [String: [QuestSuggestion]] = [:]
    /// Quests whose suggestions are being found.
    var findingSuggestions: Set<String> = []
    /// Why a quest's suggestions didn't come.
    var suggestionErrors: [String: String] = [:]
    /// What each quest is set to move, by goal id, while it's being chosen.
    var linked: [String: [String]] = [:]
    /// Suggestions added to each quest, made when its step is left.
    var added: [String: [QuestSuggestion]] = [:]
    /// Goals made while starting the season, marked New.
    var created: Set<String> = []

    /// The picked areas, as the person's areas (after the first step).
    var pickedAreas: [Area] {
        picked.compactMap { pick in
            guard case .area(let id) = pick else { return nil }
            return areas.first { $0.id == id }
        }
    }

    /// The draft's quest for an area, once read.
    func candidate(for areaId: String) -> Quest? {
        season.quests.first { $0.areaId == areaId }
    }

    /// The quests to choose from: one per picked area that's been read, in the areas' order.
    var candidates: [Quest] {
        pickedAreas.compactMap { candidate(for: $0.id) }
    }

    var chosen: [Quest] { season.chosen }

    func area(_ id: String) -> Area? { areas.first { $0.id == id } }

    func goals(in area: Area) -> [Goal] {
        area.goalIds.compactMap { id in goals.first { $0.id == id } }
    }

    /// The goals a quest moves, as they'll be once its step is left: linked ones, in their order.
    func linkedGoals(_ quest: Quest) -> [Goal] {
        (linked[quest.id] ?? quest.goalIds).compactMap { id in goals.first { $0.id == id } }
    }
}
