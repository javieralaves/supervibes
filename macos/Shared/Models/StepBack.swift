import Foundation

/*
 * Route 3, step back first (the design's "Route 3 · Step back first"): Start a season, fed by the plate, in first run's
 * frame. Which parts of life to look at, where each stands and the gap that names, the gaps as quests to choose up to
 * three of, what moves each, then the season and the week. It runs on SeasonSetupState and SeasonSetupModel, as Start
 * a season does; these are what first run's screens need on top.
 */

extension SeasonSetupState {
    /// The usual colour of each kind of area, for one with nothing in it yet.
    static let areaColors: [String: String] = [
        "Work": "violet", "Home": "amber", "Money": "slate", "Health": "green", "Growth": "indigo", "Play": "teal",
        "Relationships": "pink", "Mind": "sky", "Meaning": "coral",
    ]

    /// An area's colour: the colour of what's in it (the pricing page makes Work violet), or the usual one for its
    /// name.
    func color(of area: Area) -> String {
        goals(in: area).first?.color ?? Self.color(named: area.name)
    }

    static func color(named name: String) -> String {
        let color = areaColors[name] ?? "slate"
        return GoalPalette.colors.contains { $0.key == color } ? color : "slate"
    }

    /// The popular areas first run offers beside theirs: the first two they don't have.
    var offered: [PopularArea] { Array(popular.prefix(2)) }

    var span: SeasonSpan { SeasonSpan(startsOn: season.startsOn, endsOn: season.endsOn) }

    /// What moves a quest once its step is left: what's linked, then the suggestions added.
    func movers(_ quest: Quest) -> Int { linkedGoals(quest).count + (added[quest.id]?.count ?? 0) }

    /// Chosen quests with something to move them.
    var readyCount: Int { chosen.filter { movers($0) > 0 }.count }

    /// The first thing that moves a quest, for its track: what's linked, or else what's in its area.
    func firstMover(_ quest: Quest) -> Goal? {
        linkedGoals(quest).first ?? area(quest.areaId).flatMap { goals(in: $0).first }
    }

    /// The chosen quests as the season's cards.
    var seasonCards: [SeasonCard] {
        chosen.enumerated().compactMap { index, quest in
            guard let area = area(quest.areaId) else { return nil }
            let moving = linkedGoals(quest)
            let first = moving.first
            let mover = first.map { PlateBadge(icon: $0.icon, color: $0.color, isPractice: $0.isPractice) }
                ?? PlateBadge(icon: area.icon, color: color(of: area), isPractice: false)
            let named = moving.map { goal in
                goal.isPractice ? "\(goal.title), \(Self.rhythm(goal.practice?.perWeek))" : goal.title
            }
            let movedBy = named.count > 1 ? "\(named[0]) and \(named.count - 1) more" : named.first ?? ""
            return SeasonCard(
                id: quest.id, number: index + 1, areaName: area.name, areaIcon: area.icon, color: color(of: area),
                mover: mover, movedBy: movedBy, isNew: first.map { created.contains($0.id) } ?? false, reach: quest.reach
            )
        }
    }

    /// Everything on the plate that moves no quest: it all keeps going.
    var seasonRest: SeasonRest {
        let moving = Set(chosen.flatMap { linkedGoals($0).map(\.id) })
        return .keepsGoing(goals.filter { !moving.contains($0.id) && !created.contains($0.id) }
            .map { PlateBadge(icon: $0.icon, color: $0.color, isPractice: $0.isPractice) })
    }

    /// "3 times a week", "once a week".
    static func rhythm(_ perWeek: Int?) -> String {
        guard let perWeek else { return "every week" }
        return perWeek == 1 ? "once a week" : "\(perWeek) times a week"
    }
}
