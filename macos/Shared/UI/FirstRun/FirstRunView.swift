import SwiftUI

/// What first run's screens can do, wired to FirstRunModel in the app and to nothing in previews and tests.
struct FirstRunActions {
    var start: () -> Void = {}
    var back: () -> Void = {}
    var sort: () -> Void = {}
    var setPerWeek: (String, Int) -> Void = { _, _ in }
    var save: () -> Void = {}
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
    var actions = FirstRunActions()

    var body: some View {
        Group {
            switch state.step {
            case .welcome:
                FirstRunWelcome(firstName: state.firstName, onStart: actions.start)
            case .plate:
                FirstRunPlate(text: $plateText, isSorting: state.isBusy, error: state.error, onBack: actions.back, onSort: actions.sort)
            case .sorted:
                if let plate = state.sorted {
                    FirstRunSorted(
                        plate: plate, isSaving: state.isBusy, error: state.error,
                        onSetPerWeek: actions.setPerWeek, onBack: actions.back, onSave: actions.save
                    )
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
                        board: board, season: state.season, isStarting: state.isBusy, isStarted: state.seasonStarted, error: state.error,
                        onRename: actions.rename, onBack: actions.back, onStart: actions.startSeason
                    )
                }
            case .weekIntro, .week:
                // Route 1's week is drawn by the app, from its own model (see MainView).
                EmptyView()
            }
        }
        .padding(.top, 8)
        .background(Theme.background)
    }
}
