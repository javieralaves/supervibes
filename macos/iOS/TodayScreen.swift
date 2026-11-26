import SwiftUI

/// Today in the shared DayView, wired to CalendarModel the same way the Mac's calendar screen is.
/// Spike: no events panel (Calendar import reads EventKit, not ported yet) and no goal pages to open.
struct TodayScreen: View {
    @State private var model: CalendarModel
    @State private var selectedId: String?
    @State private var dayHour = DayGrid.hour
    @State private var weekHour = WeekGrid.hour

    init(auth: AuthModel) {
        _model = State(initialValue: CalendarModel(auth: auth, span: .day))
    }

    var body: some View {
        Group {
            switch model.load {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load your calendar", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            case .loaded:
                day
            }
        }
        .background(Theme.background)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var day: some View {
        DayView(
            data: model.data,
            offset: model.offset,
            now: model.now,
            error: model.error,
            onStep: model.step,
            onToday: model.goToToday,
            first: model.window.first,
            firstRange: model.window.firstRange,
            onScroll: model.scroll,
            actions: CalendarActions(
                create: model.create(day:start:end:goalId:title:kind:),
                saveDetails: model.saveDetails(_:goalId:title:),
                setReserved: model.setReserved,
                setKind: model.setKind,
                move: model.move(_:edge:delta:days:),
                moveToTomorrow: model.moveToTomorrow,
                toggleDone: model.toggleDone,
                remove: model.remove,
                place: model.place(_:day:start:minutes:),
                plan: model.plan(_:day:),
                reorder: model.reorder(_:day:to:),
                markTaskDone: model.markTaskDone,
                deleteTask: model.deleteTask,
                changeTask: model.changeTask,
                giveTime: { model.giveTime($0, minutes: $1, to: $2) },
                defaultGoalId: { model.defaultGoalId },
                openGoal: { _ in },
                practices: PracticeActions(
                    logToday: model.logPractice,
                    plan: { model.planPractice($0, day: $1) },
                    setDone: model.setPracticeSessionDone,
                    remove: model.removePracticeSession
                )
            ),
            selectedId: $selectedId,
            panel: BlockPanelActions(
                setReserved: model.setReserved,
                setMissed: model.setMissed,
                setDescription: model.setDescription,
                prepareAgenda: model.prepareAgenda(_:when:),
                suggestFocus: model.suggestFocus(_:when:instead:),
                prepareRecap: model.prepareRecap,
                postRecap: model.postRecap(_:body:keep:markTaskDone:),
                discardRecap: model.discardRecap,
                setTaskDone: model.setTaskDone,
                toggleDone: model.toggleDone,
                openGoal: { _ in },
                takeChange: model.takeChange,
                keepBlock: model.keepBlock
            ),
            span: .day,
            dayCount: 3,
            onSetSpan: { _ in },
            dayHour: $dayHour,
            weekHour: $weekHour,
            eventsPanel: AnyView(EmptyView()),
            showsEvents: false,
            onToggleEvents: nil,
            eventChanges: 0,
            eventsHelp: "",
            eventPreview: nil,
            importChanges: [:]
        )
    }
}
