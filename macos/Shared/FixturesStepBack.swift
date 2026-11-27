import Foundation

/// Route 3, step back first, as Alex goes through it: the season Nov 30 to Feb 28, from the plate on the First run page
/// in supervibes-design, with Relationships added and Play left out.
extension Fixtures {
    private static func goal(_ item: PlateItem, area: String) -> Goal {
        Goal(
            id: item.id, title: item.title, icon: item.icon, color: item.color, trajectory: [], areaId: area,
            kind: item.isPractice ? .practice : .project,
            practice: item.isPractice ? Practice(perWeek: item.perWeek ?? 3, week: .init(start: "2026-11-23", done: 0, planned: 0)) : nil
        )
    }

    /// The plate as made: each project and practice in its area.
    static var stepBackGoals: [Goal] {
        sortedPlate.areas.flatMap { area in area.items.map { goal($0, area: area.id) } }
    }

    /// Their six areas from the plate, Health with its words and gap.
    static var stepBackAreas: [Area] {
        sortedPlate.areas.map { area in
            var made = Area(id: area.id, name: area.name, icon: area.icon, goalIds: area.items.map(\.id))
            if area.id == "health" {
                made.now = "I run when I can, which lately is rarely. Sleep is all over the place."
                made.want = "Running a few times a week without thinking about it, and waking up rested."
                made.gap = AreaGap(
                    title: "From running rarely to a steady rhythm, and rest",
                    body: "By Feb 28 this season could make running a habit: three times a week, most weeks. Sleep can follow next season.",
                    by: .supervibes, at: referenceNow
                )
            }
            return made
        }
    }

    static let relationships = Area(id: "relationships", name: "Relationships", icon: "Agreement01Icon", goalIds: [])

    private static func stepQuest(_ id: String, _ area: String, _ title: String, _ from: String, reach: Int, position: Int = 0) -> Quest {
        Quest(id: id, seasonId: "first", areaId: area, title: title, fromText: from, reach: reach,
              chosen: position > 0, position: position, goalIds: [], effort: nil)
    }

    /// The draft once every area's read: a quest for each, the first three chosen if `chosen`.
    static func stepBackSeason(chosen: Bool = true) -> Season {
        Season(
            id: "first", name: "Winter", startsOn: "2026-11-30", endsOn: "2027-02-28", state: .draft, week: 0, weeks: 13,
            status: nil,
            quests: [
                stepQuest("q-health", "health", "A steady running rhythm", "Running rarely", reach: 38, position: chosen ? 1 : 0),
                stepQuest("q-home", "home", "Settled in a new flat", "Not having found one", reach: 70, position: chosen ? 2 : 0),
                stepQuest("q-rel", "relationships", "A weekly evening that’s just for friends", "Seeing them when it happens", reach: 30,
                          position: chosen ? 3 : 0),
                stepQuest("q-work", "work", "Pricing shipped, and a designer hired", "Both in flight", reach: 60),
                stepQuest("q-growth", "growth", "Conversational Spanish", "Keeping it up loosely", reach: 25),
                stepQuest("q-money", "money", "Taxes done, and a simple budget", "Papers still to gather", reach: 55),
            ]
        )
    }

    private static func stepBack(_ step: SeasonSetupStep, season: Season = stepBackSeason()) -> SeasonSetupState {
        SeasonSetupState(
            season: season, today: "2026-11-26", areas: stepBackAreas + [relationships], goals: stepBackGoals,
            popular: [
                PopularArea(name: "Mind", icon: "BrainIcon", line: "How you feel day to day: calm, stress, sleep."),
                PopularArea(name: "Meaning", icon: "Leaf01Icon", line: "What matters to you, and what you give back."),
            ],
            picked: ["work", "home", "money", "health", "growth", "relationships"].map { .area($0) }, step: step
        )
    }

    /// Choosing areas: five of theirs picked, Play left out, Relationships picked from the two worth a look.
    static var stepBackPick: SeasonSetupState {
        var state = stepBack(.areas, season: Season(
            id: "first", name: "Winter", startsOn: "2026-11-30", endsOn: "2027-02-28", state: .draft, week: 0, weeks: 13,
            status: nil, quests: []
        ))
        state.areas = stepBackAreas
        state.popular = [
            PopularArea(name: "Relationships", icon: "Agreement01Icon", line: "The people close to you, and time with them."),
            PopularArea(name: "Mind", icon: "BrainIcon", line: "How you feel day to day: calm, stress, sleep."),
            PopularArea(name: "Meaning", icon: "Leaf01Icon", line: "What matters to you, and what you give back."),
        ]
        state.picked = ["work", "home", "money", "health", "growth"].map { .area($0) } + [.popular("Relationships")]
        return state
    }

    /// Health, 4 of 6, read: its words, its gap, and how far this season could get.
    static var stepBackStand: SeasonSetupState { stepBack(.stand(3), season: stepBackSeason(chosen: false)) }

    /// Relationships, 6 of 6, nothing said yet.
    static var stepBackStandEmpty: SeasonSetupState {
        var season = stepBackSeason(chosen: false)
        season.quests.removeAll { $0.areaId == "relationships" }
        return stepBack(.stand(5), season: season)
    }

    /// The gaps as quests, Health, Home and Relationships chosen.
    static var stepBackQuests: SeasonSetupState { stepBack(.focus) }

    /// What moves each: Run and the move from the plate, a suggested practice for Relationships.
    static var stepBackMoves: SeasonSetupState {
        var state = stepBack(.how(0))
        state.linked = ["q-health": ["run"], "q-home": ["move"]]
        state.added = ["q-rel": [QuestSuggestion(kind: .practice, title: "Friends’ evening", line: "One evening a week that’s just for friends", perWeek: 1)]]
        return state
    }

    /// The season, made: each quest moved, Friends’ evening made while starting it.
    static var stepBackReview: SeasonSetupState {
        var state = stepBack(.review)
        let friends = Goal(id: "friends", title: "Friends’ evening", icon: "UserGroupIcon", color: "pink", trajectory: [],
                           areaId: "relationships", kind: .practice,
                           practice: Practice(perWeek: 1, week: .init(start: "2026-11-23", done: 0, planned: 0)))
        state.goals.append(friends)
        state.created = ["friends"]
        state.season.quests[0].goalIds = ["run"]
        state.season.quests[1].goalIds = ["move"]
        state.season.quests[2].goalIds = ["friends"]
        return state
    }
}
