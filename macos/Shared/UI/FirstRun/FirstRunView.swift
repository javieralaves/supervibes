import SwiftUI

/// What first run's screens can do, wired to FirstRunModel in the app and to nothing in previews and tests.
struct FirstRunActions {
    var start: () -> Void = {}
    var back: () -> Void = {}
    var sort: () -> Void = {}
    var setPerWeek: (String, Int) -> Void = { _, _ in }
    var save: () -> Void = {}
    var choose: (FirstRunChoice) -> Void = { _ in }
}

/// First run's shared start, a full window per step: welcome, your plate, sorted, what matters.
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
                    FirstRunWhatMatters(plate: plate, seasonEnd: state.seasonEnd, onBack: actions.back, onChoose: actions.choose)
                }
            }
        }
        .padding(.top, 8)
        .background(Theme.background)
    }
}
