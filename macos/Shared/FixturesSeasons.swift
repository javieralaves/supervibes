import Foundation

/// Starting a season, for previews and snapshot tests: Winter, set up on Wednesday, Nov 18, from Monday the 23rd.
extension Fixtures {
    /// The areas with practices, Money just added from Popular areas, and words where the flow needs them.
    static var seasonAreas: [Area] {
        var list = practiceAreas
        list[0].gap = AreaGap(
            title: "From shipping fast to showing something worth following.",
            body: "Supervibes moves quickly but isn’t ready to show Pablo and Denis. What’s missing is a version that makes the case on its own.",
            by: .supervibes, at: referenceNow.addingTimeInterval(-600)
        )
        list[3].now = "Walks most days, workouts when the week allows."
        list.append(Area(id: "money", name: "Money", icon: "Wallet01Icon", goalIds: []))
        return list
    }

    /// The projects and practices the areas hold.
    static var seasonGoals: [Goal] {
        lifeGoals.filter { $0.id != "5" } + practices
    }

    static var seasonPopular: [PopularArea] {
        [
            PopularArea(name: "Home", icon: "Sofa01Icon", line: "Where you live, and how it feels to be there."),
            PopularArea(name: "Growth", icon: "Mortarboard01Icon", line: "What you’re learning, and who you’re becoming."),
            PopularArea(name: "Play", icon: "PartyIcon", line: "Rest, hobbies, and time that’s just for fun."),
            PopularArea(name: "Mind", icon: "BrainIcon", line: "How you feel day to day: calm, stress, sleep."),
            PopularArea(name: "Meaning", icon: "Leaf01Icon", line: "What matters to you, and what you give back."),
        ]
    }

    private static func quest(_ id: String, _ area: String, _ title: String, _ from: String, reach: Int,
                              chosen: Bool = false, position: Int = 0, goals: [String] = []) -> Quest {
        Quest(id: id, seasonId: "winter", areaId: area, title: title, fromText: from, reach: reach,
              chosen: chosen, position: position, goalIds: goals, effort: nil)
    }

    /// Winter being set up: a candidate quest for Work, Madrid and Health, none chosen yet.
    static var draftSeason: Season {
        Season(
            id: "winter", name: "Winter", startsOn: "2026-11-23", endsOn: "2027-02-21", state: .draft, week: 0, weeks: 13,
            status: nil,
            quests: [
                quest("q-work", "work", "A Supervibes build Pablo and Denis ask to try", "Fast, but not ready to show", reach: 38),
                quest("q-madrid", "madrid", "Three friends housed through the rent app", "One user, and no visits yet", reach: 30),
                quest("q-health", "health", "Moving five days a week", "Active when the week allows", reach: 45),
            ]
        )
    }

    private static func setup(_ step: SeasonSetupStep, season: Season = draftSeason) -> SeasonSetupState {
        SeasonSetupState(
            season: season, today: "2026-11-18", areas: seasonAreas, goals: seasonGoals, popular: seasonPopular,
            picked: [.area("work"), .area("madrid"), .area("health"), .area("money")], step: step
        )
    }

    /// Choosing areas: four of yours picked, Rest & play and Home & money left out, and Play picked from Popular areas.
    static var setupAreas: SeasonSetupState {
        var state = setup(.areas)
        state.areas = practiceAreas
        state.picked = [.area("work"), .area("madrid"), .area("people"), .area("health"), .popular("Play")]
        return state
    }

    /// Work, read: its gap and what Winter could reach.
    static var setupStandRead: SeasonSetupState { setup(.stand(0)) }

    /// Money, just added: nothing said yet, so nothing to read.
    static var setupStandEmpty: SeasonSetupState { setup(.stand(3)) }

    /// Choosing the focus: Work first, Health second, one more to go.
    static var setupFocus: SeasonSetupState {
        var season = draftSeason
        season.quests[0].chosen = true
        season.quests[2].chosen = true
        season.quests[2].position = 1
        season.quests.append(quest("q-money", "money", "Knowing where the money goes", "Not looking at it at all", reach: 40))
        return setup(.focus, season: season)
    }

    /// Work's quest: Build Supervibes linked, two suggestions, and one of them added.
    static var setupHow: SeasonSetupState {
        var state = setupFocus
        state.step = .how(0)
        state.linked["q-work"] = ["1"]
        let explore = QuestSuggestion(kind: .practice, title: "Show a build to someone every week", line: "A demo, a video or a call", perWeek: 1)
        state.suggestions["q-work"] = [
            QuestSuggestion(kind: .project, title: "A demo Pablo and Denis can click through", line: "Finish by Jan 15, before the January review", perWeek: nil),
            QuestSuggestion(kind: .project, title: "Write the story Supervibes tells", line: "Finish by Dec 18: a page that makes the case", perWeek: nil),
            explore,
        ]
        state.added["q-work"] = [explore]
        return state
    }

    /// The review: Work's quest moved by Build Supervibes and a practice made while starting, Health's by its two.
    static var setupReview: SeasonSetupState {
        var state = setupFocus
        state.step = .review
        let made = Goal(id: "new-1", title: "Show a build to someone every week", icon: "Presentation01Icon", color: "violet",
                        trajectory: [], areaId: "work", kind: .practice,
                        practice: Practice(perWeek: 1, week: .init(start: "2026-11-16", done: 0, planned: 0)))
        state.goals.append(made)
        state.created = ["new-1"]
        state.season.quests[0].goalIds = ["1", "new-1"]
        state.season.quests[2].goalIds = ["p1", "p2"]
        return state
    }

    // MARK: - A season running

    /// Winter in its first week (Monday Nov 16 to Feb 14, so Wednesday the 18th is week 1): Work's quest moved by Build
    /// Supervibes and the community, Health's by its two practices.
    static var activeSeason: Season {
        Season(
            id: "winter", name: "Winter", startsOn: "2026-11-16", endsOn: "2027-02-14", state: .active, week: 1, weeks: 13,
            status: .atRisk,
            quests: [
                quest("q-work", "work", "A Supervibes build Pablo and Denis ask to try", "Fast, but not ready to show", reach: 38,
                      chosen: true, position: 1, goals: ["1", "p4"]).with(effort: .onTrack),
                quest("q-health", "health", "Moving five days a week", "Active when the week allows", reach: 45,
                      chosen: true, position: 2, goals: ["p1", "p2"]).with(effort: .atRisk),
            ]
        )
    }

    static var runningSeasons: CurrentSeasons {
        CurrentSeasons(today: "2026-11-18", active: activeSeason, draft: nil, ended: nil, popularAreas: [])
    }

    static var seasonRead: AreaRead {
        AreaRead(
            headline: "Work is moving; Health is still finding its rhythm",
            summary: "Build Supervibes is on track and the community is keeping pace. Workouts are at 1 of 3 with two planned, so Thursday’s session decides whether Health’s quest starts the season moving.",
            goalIds: ["1", "p4", "p1", "p2"], usedCalendar: true, createdAt: referenceNow.addingTimeInterval(-2 * 3600)
        )
    }

    static var seasonPage: SeasonPageData {
        SeasonPageData(season: activeSeason, read: seasonRead, goals: lifeWithPractices, weeks: goalWeeks,
                       areas: seasonAreas, today: "2026-11-18")
    }

    static var questPage: QuestPageData {
        QuestPageData(quest: activeSeason.quests[1], season: activeSeason, gap: nil, read: nil, goals: lifeWithPractices,
                      weeks: goalWeeks, areas: seasonAreas, today: "2026-11-18")
    }

    /// Health's page with Winter running: its quest under This season, its practices marked.
    static var areaDetailInSeason: AreaDetail {
        var detail = practiceAreaDetail
        detail.area.now = "Walks most days, workouts when the week allows."
        detail.quest = activeSeason.quests[1]
        detail.season = activeSeason
        return detail
    }
}

extension Quest {
    func with(effort: GoalStatus?) -> Quest {
        var copy = self
        copy.effort = effort
        return copy
    }
}
