import SwiftUI

/*
 * The small pills on a task: its estimate, and the day it's planned for and due, each opening a
 * menu. Matches the web's PILL in tasks-section.tsx and src/components/day-pill.tsx.
 */

/// `inline-flex rounded-full border px-2 py-0.5 text-[11px] font-medium tabular-nums`
struct TaskPill: View {
    let icon: Icon
    let text: String
    var tone: Color = Theme.muted
    /// An empty day pill: dashed, waiting to be set.
    var isEmpty = false
    var isActive = false
    var action: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        let label = HStack(spacing: 4) {
            icon.image(size: 12)
            Text(text).font(.app(11, .medium)).monospacedDigit()
        }
        .foregroundStyle(isHovered || isActive ? Theme.foreground : tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(isEmpty ? .clear : Theme.card, in: .capsule)
        .overlay(
            Capsule().strokeBorder(
                isHovered || isActive ? Theme.lineStrong : Theme.cardBorder,
                style: StrokeStyle(lineWidth: 1, dash: isEmpty ? [3, 2] : [])
            )
        )
        .contentShape(.capsule)

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
        } else {
            label
        }
    }
}

/// The two kinds of day a task can have.
enum TaskDayKind {
    /// The day they mean to do it, without a time.
    case plan
    /// The day it has to be done by.
    case due

    var icon: Icon { self == .plan ? .calendarSmall : .flag }
    var empty: String { self == .plan ? "Plan" : "Due" }
    var menuTitle: String { self == .plan ? "Plan for" : "Due on" }
    var clearTitle: String { self == .plan ? "Clear plan" : "Clear due date" }

    /// What the pill says for `day`, and in what colour.
    func describe(_ day: String, today: String) -> (text: String, tone: Color) {
        let days = CalendarDay.daysUntil(day, today: today)
        let label = CalendarDay.relativeLabel(day, today: today)
        switch self {
        case .plan:
            // A planned day that's gone by without the task getting done.
            return (label, days < 0 ? Theme.amber : Theme.muted)
        case .due:
            if days < 0 { return ("Overdue · \(label)", Theme.danger) }
            let text = label == "Today" || label == "Tomorrow" ? "Due \(label.lowercased())" : "Due \(label)"
            return (text, days <= 1 ? Theme.foreground : Theme.muted)
        }
    }
}

/// A plan or due pill, opening a menu of the next week's days, any other day, and Clear.
struct TaskDayPill: View {
    let kind: TaskDayKind
    let value: String?
    let today: String
    /// Set when the row is closed and not hovered: an empty pill hides until then.
    var isQuiet = false
    /// Who opened the menu (the task's id), so its row stays active while it's open.
    var owner: String?
    /// A plan pill's week (its Monday), shown when there's no day: "This week" or "Next week".
    var week: String?
    /// For a plan pill, offers this week and next above the days.
    var onWeek: ((String) -> Void)?
    var onChange: (String?) -> Void

    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    /// "This week" or "Next week" for a week-only plan (a carried-over week counts as this one).
    private var weekLabel: String? {
        guard value == nil, onWeek != nil, let week else { return nil }
        if week <= thisWeek { return "This week" }
        return week == nextWeek ? "Next week" : nil
    }

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero
    /// The tag on this pill's own menu: its task's id and which pill.
    private var menuOwner: String? { owner.map { "\($0)#\(kind == .plan ? "plan" : "due")" } }

    /// This pill's own menu is showing.
    private var isMenuOpen: Bool { menuOwner != nil && overlays?.presented?.owner == menuOwner }

    var body: some View {
        let shown = value.map { kind.describe($0, today: today) } ?? weekLabel.map { (text: $0, tone: Theme.muted) }
        TaskPill(
            icon: kind.icon,
            text: shown?.text ?? kind.empty,
            tone: shown?.tone ?? Theme.muted,
            isEmpty: shown == nil,
            isActive: isMenuOpen,
            action: openMenu
        )
        .modifier(AnchorReader(frame: $anchor))
        .opacity(shown == nil && isQuiet && !isMenuOpen ? 0 : 1)
        .layoutValue(key: FlowOptional.self, value: shown == nil && isQuiet && !isMenuOpen)
    }

    private func openMenu() {
        guard let overlays else { return }
        // Lined up with the pill's left edge (`align="start"`), so the anchor's right edge is pushed out.
        let menuAnchor = CGRect(x: anchor.minX, y: anchor.minY, width: 224, height: anchor.height)
        overlays.showMenu(anchor: menuAnchor, owner: menuOwner) {
            DayMenu(kind: kind, value: value, today: today, week: week, onWeek: onWeek, onChange: onChange)
        }
    }
}

/// A plan or due day's choices, as a whole panel: this week and next (for a plan), the next seven
/// days, any other day, and Clear. A pill opens it, and so does a task's own menu.
struct DayMenu: View {
    let kind: TaskDayKind
    let value: String?
    let today: String
    /// A plan's week (its Monday), when it has no day.
    var week: String?
    /// For a plan, offers this week and next above the days.
    var onWeek: ((String) -> Void)?
    let onChange: (String?) -> Void

    @Environment(\.overlays) private var overlays
    @Environment(\.isSubmenu) private var isSubmenu

    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    /// "This week" or "Next week" for a week-only plan (a carried-over week counts as this one).
    private var weekLabel: String? {
        guard value == nil, onWeek != nil, let week else { return nil }
        if week <= thisWeek { return "This week" }
        return week == nextWeek ? "Next week" : nil
    }

    private var days: [String] {
        (0..<7).compactMap { offset in
            CalendarDay.date(today).map { CalendarDay.string($0.addingTimeInterval(Double(offset) * 86_400)) }
        }
    }

    var body: some View {
        let days = days
        MenuPanel(width: 224) {
            MenuLabel(kind.menuTitle)
            if let onWeek {
                DayRow(title: "This week", detail: CalendarDay.formatWeek(thisWeek), isSelected: weekLabel == "This week") {
                    overlays?.dismiss()
                    onWeek(thisWeek)
                }
                DayRow(title: "Next week", detail: CalendarDay.formatWeek(nextWeek), isSelected: weekLabel == "Next week") {
                    overlays?.dismiss()
                    onWeek(nextWeek)
                }
                MenuSeparator()
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                DayRow(
                    title: index == 0 ? "Today" : index == 1 ? "Tomorrow" : CalendarDay.weekday(day),
                    detail: CalendarDay.format(day, today: today),
                    isSelected: day == value
                ) {
                    overlays?.dismiss()
                    onChange(day)
                }
            }
            MenuSeparator()
            DayRow(
                title: "Another day…",
                detail: value.flatMap { days.contains($0) ? nil : CalendarDay.format($0, today: today) },
                isSelected: value.map { !days.contains($0) } ?? false
            ) {
                // In a submenu the calendar takes the submenu's place; from a pill, the menu's.
                if isSubmenu {
                    overlays?.replaceSubmenu { AnotherDayMenu(kind: kind, value: value, today: today, onChange: onChange) }
                } else {
                    overlays?.replaceMenu { AnotherDayMenu(kind: kind, value: value, today: today, onChange: onChange) }
                }
            }
            if value != nil || weekLabel != nil {
                DayRow(title: kind.clearTitle, isDestructive: true) {
                    overlays?.dismiss()
                    onChange(nil)
                }
            }
        }
    }
}

/// Any day, on a month's calendar.
private struct AnotherDayMenu: View {
    let kind: TaskDayKind
    let value: String?
    let today: String
    let onChange: (String?) -> Void

    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel(width: 260) {
            MenuLabel(kind.menuTitle)
            DatePicker(
                kind.menuTitle,
                selection: Binding(
                    get: { value.flatMap(CalendarDay.date) ?? CalendarDay.date(today) ?? Date() },
                    set: { picked in
                        overlays?.dismiss()
                        onChange(CalendarDay.string(picked))
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .padding(4)
        }
    }
}

/// The estimate pill, opening a menu of 15 min to 2 hr.
struct EstimatePill: View {
    let minutes: Int
    var isPending = false
    /// Who opened the menu (the task's id), so its row stays active while it's open.
    var owner: String?
    let onChange: (Int) -> Void

    @Environment(\.overlays) private var overlays
    @Environment(\.shortHours) private var shortHours
    @State private var anchor = CGRect.zero

    private func label(_ minutes: Int) -> String { shortHours ? BoardDuration.text(minutes) : TaskItem.minutesLabel(minutes) }

    var body: some View {
        let action: (() -> Void)? = isPending ? nil : { openMenu() }
        return TaskPill(icon: .clock, text: label(minutes), action: action)
            .modifier(AnchorReader(frame: $anchor))
            .accessibilityLabel("Estimate: \(label(minutes))")
    }

    private func openMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: anchor, owner: owner.map { "\($0)#estimate" }) {
            EstimateMenu(minutes: minutes, shortHours: shortHours, onChange: onChange)
        }
    }
}

/// An estimate's choices, 15 min to 2 hr, as a whole panel.
struct EstimateMenu: View {
    let minutes: Int
    /// "2 h" rather than "2 hr", as on the planning board. Passed in: the menu draws in the overlay
    /// layer, outside the board's environment.
    var shortHours = false
    let onChange: (Int) -> Void

    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel(width: 144) {
            MenuLabel("Estimate")
            ForEach(TaskItem.estimates, id: \.self) { option in
                DayRow(title: shortHours ? BoardDuration.text(option) : TaskItem.minutesLabel(option), isSelected: option == minutes) {
                    overlays?.dismiss()
                    onChange(option)
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Durations with hours as "h" ("2 h", "1 h 30 min"), as on the planning board.
    @Entry var shortHours = false
}

// MARK: - Menu pieces

/// A menu's small heading: `px-2.5 pb-1 pt-1.5 text-xs font-medium text-muted`.
struct MenuLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).appText(.xs, .medium).foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }
}

/// `mx-1 my-1 h-px bg-card-border`
struct MenuSeparator: View {
    var body: some View {
        Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 4).padding(.vertical, 4)
    }
}

/// A menu row with an optional detail and tick on the right: `h-8 rounded-lg px-2.5 text-sm`.
struct DayRow: View {
    let title: String
    var detail: String?
    var isSelected = false
    var isDestructive = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).appText(.sm).foregroundStyle(isDestructive ? Theme.danger : Theme.foreground)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let detail { Text(detail).appText(.xs).monospacedDigit().lineLimit(1).fixedSize() }
                    if isSelected { Icon.tick.image(size: 13) }
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension CalendarDay {
    /// "Friday", for a calendar day.
    static func weekday(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.wide))
    }
}
