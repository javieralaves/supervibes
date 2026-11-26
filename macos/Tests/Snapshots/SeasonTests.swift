import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// Starting a season: Life's panel before one, and each step of setting Winter up on Wednesday, Nov 18.
@MainActor
final class SeasonTests: XCTestCase {
    /// Life's panel with no season: the question, one line, Start a season, and the three quest tracks.
    func testNoSeasonPanel() {
        assertAppearances(
            NoSeasonPanel(onStart: {}).padding(32).frame(maxHeight: .infinity, alignment: .top).background(Theme.background),
            width: 1088, height: 300
        )
    }

    /// The same panel with Winter being set up: it picks up where it was.
    func testNoSeasonPanelDraft() {
        assertAppearances(
            NoSeasonPanel(draft: Fixtures.draftSeason, onStart: {}).padding(32).frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background),
            width: 1088, height: 300
        )
    }

    /// Life with no season: the panel between the greeting and Projects.
    func testLifeNoSeason() {
        let seasons = CurrentSeasons(today: "2026-11-18", active: nil, draft: nil, ended: nil, popularAreas: Fixtures.seasonPopular)
        assertAppearances(
            LifeHome(firstName: "Javier", goals: Fixtures.lifeWithPractices, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                     areas: Fixtures.practiceAreas, now: Fixtures.referenceNow, seasons: seasons, onStartSeason: {})
                .background(Theme.background),
            width: 1180, height: 900
        )
    }

    /// Choosing areas: yours with their projects and practices, Popular areas dashed until picked, Add your own.
    func testChooseAreas() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupAreas).background(Theme.background), width: 1200, height: 1020)
    }

    /// Work, read: its words, the track inked to Feb 21, the gap, and what Winter could reach.
    func testAreaStandRead() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupStandRead).background(Theme.background), width: 1200, height: 1000)
    }

    /// Money, just added: both sides empty, nothing to read yet.
    func testAreaStandEmpty() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupStandEmpty).background(Theme.background), width: 1200, height: 760)
    }

    /// Four possible quests, two chosen and numbered.
    func testChooseFocus() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupFocus).background(Theme.background), width: 1200, height: 900)
    }

    /// Work's quest: Build Supervibes linked, suggestions to add, one added and marked New.
    func testQuestHow() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupHow).background(Theme.background), width: 1200, height: 1060)
    }

    /// A quest's words read the same everywhere: "From" and its start, and how far the season goes.
    func testQuestWords() {
        let quest = Fixtures.draftSeason.quests[2]
        XCTAssertEqual(quest.fromLine, "From active when the week allows")
        XCTAssertEqual(quest.reachWords, "about half of the way")
        XCTAssertEqual(Fixtures.draftSeason.range, "Nov 23 – Feb 21")
        XCTAssertEqual(CalendarDay.weekdayMonthDay("2026-11-23"), "Monday, Nov 23")
    }

    /// The server's checks on a season's name and days, before anything is sent.
    func testSeasonInputChecks() {
        XCTAssertNil(SeasonInput(editing: Fixtures.draftSeason).problem)
        XCTAssertEqual(SeasonInput(name: " ", startsOn: "2026-11-23", endsOn: "2027-02-21").problem, "Give the season a name.")
        XCTAssertEqual(SeasonInput(name: "Winter", startsOn: "2026-11-23", endsOn: "2026-11-23").problem, "A season ends after it starts.")
        XCTAssertEqual(SeasonInput(name: "Winter", startsOn: "2026-11-23", endsOn: "2027-06-01").problem, "Keep a season under six months.")
    }

    /// A suggestion becomes a goal in the quest's area: a practice with its rhythm, a project with its line.
    func testSuggestionInput() {
        let practice = QuestSuggestion(kind: .practice, title: "Read before bed", line: "To wind down", perWeek: 4).input(areaId: "health")
        XCTAssertEqual(practice.kind, .practice)
        XCTAssertEqual(practice.perWeek, 4)
        XCTAssertEqual(practice.areaId, "health")
        XCTAssertNil(practice.problem)
        let project = QuestSuggestion(kind: .project, title: "Write the memo", line: "Done by Jan 9", perWeek: nil).input(areaId: "work")
        XCTAssertEqual(project.description, "Done by Jan 9")
        XCTAssertNil(project.problem)
    }

    /// Ready for Winter? The season and a column per quest, with what moves each.
    func testSeasonReview() {
        assertAppearances(SeasonSetupView(state: Fixtures.setupReview).background(Theme.background), width: 1200, height: 900)
    }
}
