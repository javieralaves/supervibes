import SwiftUI

/// Settings' card for what the Calendar opens on: Day, the next 3, 5 or 7 days, or the week. Kept
/// on this Mac (Shared/Models/CalendarSpan.swift), so it saves itself rather than through the page.
struct CalendarViewCard: View {
    let span: CalendarSpan
    var onChange: (CalendarSpan) -> Void = { _ in }

    var body: some View {
        Card {
            CardHeader(title: "Calendar", description: "What the Calendar shows when you open it.") {}
            ToggleGroup(
                selection: Binding(get: { span }, set: { onChange($0) }),
                options: CalendarSpan.all.map { .init(value: $0, label: $0.label) }
            )
            Text(Self.explanation(span))
                .appText(.sm)
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)
        }
    }

    static func explanation(_ span: CalendarSpan) -> String {
        switch span {
        case .day: "Opens on today."
        case .days(let n): "Opens on the next \(n) days, with today first. The switch at the top of the Calendar changes it until you leave."
        case .week: "Opens on this week, Monday to Sunday. The switch at the top of the Calendar changes it until you leave."
        }
    }
}

#Preview("Calendar card") {
    @Previewable @State var span = CalendarSpan.days(3)
    CalendarViewCard(span: span) { span = $0 }
        .padding(32)
        .frame(width: 768)
        .background(Theme.background)
}
