import SwiftUI

/// What first run's screens can do, wired to FirstRunModel in the app and to nothing in previews and tests.
struct FirstRunActions {
    var start: () -> Void = {}
    var back: () -> Void = {}
    var sort: () -> Void = {}
    var setPerWeek: (String, Int) -> Void = { _, _ in }
    var save: () -> Void = {}
    /// The questions before sorting: an option picked (or picked again, to clear it), words added, on or past one.
    var pick: (Int) -> Void = { _ in }
    var setMore: (String) -> Void = { _ in }
    var nextQuestion: () -> Void = {}
    var skipQuestion: () -> Void = {}
    var sortWithoutAnswers: () -> Void = {}
    /// Changing what was sorted.
    var applyEdit: (SortedEdit, SortedSelection) -> Void = { _, _ in }
    var remove: (SortedSelection) -> Void = { _ in }
    var add: (String, PlateKind, String) -> Void = { _, _, _ in }
    var addArea: (String, String) -> Void = { _, _ in }
    /// Say it instead: start listening on the plate, or stop.
    var dictate: () -> Void = {}
    var choose: (FirstRunChoice) -> Void = { _ in }
    /// Route 2's board.
    var focus = FocusActions()
    /// From the board on to the season.
    var toSeason: () -> Void = {}
    /// A quest renamed on its card, by its goal's id.
    var rename: (String, String) -> Void = { _, _ in }
    var startSeason: () -> Void = {}
}

/// First run's shared start, a full window per step: welcome, your plate, sorted, what matters; then Route 2's focus
/// and season.
struct FirstRunView: View {
    let state: FirstRunState
    @Binding var plateText: String
    /// Say it instead, on the plate.
    var dictation = DictationState()
    var actions = FirstRunActions()

    var body: some View {
        Group {
            switch state.step {
            case .welcome:
                FirstRunWelcome(firstName: state.firstName, onStart: actions.start)
            case .plate:
                FirstRunPlate(
                    text: $plateText, isSorting: state.isBusy, error: state.error, dictation: dictation, onDictate: actions.dictate,
                    onBack: actions.back, onSort: actions.sort
                )
            case .clarify:
                FirstRunClarify(clarify: state.clarify, isSorting: state.isBusy, error: state.error, dictation: dictation, actions: actions)
            case .sorted:
                if let plate = state.sorted {
                    FirstRunSorted(plate: plate, isSaving: state.isBusy, error: state.error, actions: actions)
                }
            case .whatMatters:
                if let plate = state.sorted {
                    FirstRunWhatMatters(plate: plate, seasonEnd: state.seasonEnd, error: state.error, onBack: actions.back, onChoose: actions.choose)
                }
            case .focus:
                if let board = state.board {
                    FirstRunFocus(board: board, season: state.season, actions: actions.focus, onBack: actions.back, onContinue: actions.toSeason)
                }
            case .season:
                if let board = state.board {
                    FirstRunSeasonReview(
                        cards: board.seasonCards, season: state.season,
                        subtitle: FirstRunSeasonReview.focusSubtitle(count: board.focus.count, season: state.season),
                        rest: board.seasonRest, name: { board.name($0) }, isStarting: state.isBusy, isStarted: state.seasonStarted,
                        error: state.error, onRename: actions.rename, onBack: actions.back, onStart: actions.startSeason
                    )
                }
            case .weekIntro, .week, .stepBack:
                // The week, and Route 3's steps, are drawn by the app from their own models (see MainView).
                EmptyView()
            }
        }
        .padding(.top, 8)
        .background(Theme.background)
    }
}
