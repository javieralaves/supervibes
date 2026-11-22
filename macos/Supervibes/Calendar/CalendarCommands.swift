import SwiftUI

/// What the View menu can do while the Calendar is showing.
struct CalendarCommands {
    let span: CalendarSpan
    /// The count Next N days last showed.
    let dayCount: Int
    /// The window is wide enough for the multi-day views.
    let canShowDays: Bool
    let setSpan: (CalendarSpan) -> Void
    let today: () -> Void
}

extension FocusedValues {
    @Entry var calendarCommands: CalendarCommands?
}

/// The View menu's Calendar items: Day ⌘1, Next N days ⌘2, Week ⌘3, Today ⌘T. Dimmed when the
/// Calendar isn't showing.
struct CalendarMenuCommands: Commands {
    @FocusedValue(\.calendarCommands) private var calendar

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Day") { calendar?.setSpan(.day) }
                .keyboardShortcut("1")
                .disabled(calendar == nil)
            Button("Next \(calendar?.dayCount ?? CalendarSpan.lastDayCount()) Days") {
                if let calendar { calendar.setSpan(.days(calendar.dayCount)) }
            }
            .keyboardShortcut("2")
            .disabled(calendar?.canShowDays != true)
            Button("Week") { calendar?.setSpan(.week) }
                .keyboardShortcut("3")
                .disabled(calendar?.canShowDays != true)
            Button("Today") { calendar?.today() }
                .keyboardShortcut("t")
                .disabled(calendar == nil)
            Divider()
        }
    }
}
