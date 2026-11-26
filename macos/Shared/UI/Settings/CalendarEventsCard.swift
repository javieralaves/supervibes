import SwiftUI

/// Settings' card for Calendar import: access to calendars, which Google calendars to list, the
/// goal and kind an import starts with, and whether to hide all-day events. Kept on this Mac
/// (Shared/Models/EventImport.swift), so it saves itself rather than through the page. Designed in
/// supervibes-design ("Calendar import", Connect).
struct CalendarEventsCard: View {
    let settings: EventImportSettings
    let access: CalendarAccess
    /// The Google calendars macOS Calendar has.
    let calendars: [ExternalCalendar]
    /// Goals an import can go to.
    let goals: [CalendarGoal]
    var onChange: (EventImportSettings) -> Void = { _ in }
    /// Asks macOS for access.
    var onAllow: () -> Void = {}
    var onOpenSystemSettings: () -> Void = {}

    var body: some View {
        Card {
            CardHeader(title: "Events from your calendars", description: description) {
                if access == .allowed {
                    Switch(label: "List events from your calendars", isOn: settings.isOn) { on in
                        var new = settings
                        new.isOn = on
                        onChange(new)
                    }
                }
            }

            switch access {
            case .notAsked:
                Text("Supervibes reads events from the Google calendars you’ve added to macOS Calendar. It only reads them; it never changes your calendars.")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    PrimaryButton(title: "Allow access to Calendar", action: onAllow)
                    Spacer()
                }
                .padding(.top, 16)
            case .denied:
                HStack(spacing: 4) {
                    Text("Calendar access is off for Supervibes in System Settings.")
                        .foregroundStyle(Theme.danger)
                    Button("Turn it on", action: onOpenSystemSettings)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.foreground)
                        .underline()
                        .pointerStyle(.link)
                }
                .appText(.sm)
            case .allowed:
                allowed
                    .opacity(settings.isOn ? 1 : 0.5)
                    .inactive(!settings.isOn)
            }
        }
    }

    private var description: String {
        switch access {
        case .allowed: "Listed in the Calendar’s events panel, ready to import one at a time. Nothing shows on your calendar until you import it."
        default: "See your meetings beside your projects’ and practices’ time, and import the ones that matter, one at a time."
        }
    }

    private var allowed: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Google calendars").appText(.xs, .medium).foregroundStyle(Theme.muted)
                .padding(.bottom, 4)
            if calendars.isEmpty {
                Text("No Google calendars in macOS Calendar yet. Add your Google account in System Settings › Internet Accounts, with Calendars on.")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                ForEach(calendars) { calendar in
                    Toggle(isOn: Binding(
                        get: { settings.includes(calendar) },
                        set: { on in
                            var new = settings
                            new.set(calendar, on: on, among: calendars)
                            onChange(new)
                        }
                    )) {
                        Text(calendar.title).appText(.sm).foregroundStyle(Theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                    .tint(Theme.foreground)
                    .frame(height: 32)
                }
            }

            Divider().overlay(Theme.cardBorder).padding(.vertical, 20)

            VStack(spacing: 16) {
                RowHeader(title: "Goes to", detail: "The project or practice an event goes to when you import it. You can pick another on the event.") {
                    goalMenu
                }
                RowHeader(title: "Block", detail: "A session to work in, or reserved time kept for itself.") {
                    kindMenu
                }
            }

            Divider().overlay(Theme.cardBorder).padding(.vertical, 20)

            RowHeader(title: "Hide all-day events", detail: "Leaves out events without a time, like holidays and trips.") {
                Switch(label: "Hide all-day events", isOn: settings.hidesAllDay) { on in
                    var new = settings
                    new.hidesAllDay = on
                    onChange(new)
                }
            }
        }
    }

    private var goalMenu: some View {
        let selected = settings.goal(among: goals.map(\.id))
        let goal = goals.first { $0.id == selected }
        return Menu {
            Picker("Project or practice", selection: Binding(
                get: { selected ?? "" },
                set: { id in
                    var new = settings
                    new.goalId = id
                    onChange(new)
                }
            )) {
                ForEach(GoalSections(goals).sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.goals) { goal in
                            Text(goal.title).tag(goal.id)
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuField {
                if let goal {
                    GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                    Text(goal.title).lineLimit(1)
                } else {
                    Text("No projects or practices yet").foregroundStyle(Theme.muted)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(goals.isEmpty)
    }

    private var kindMenu: some View {
        Menu {
            Picker("Block", selection: Binding(
                get: { settings.kind },
                set: { kind in
                    var new = settings
                    new.kind = kind
                    onChange(new)
                }
            )) {
                ForEach(ImportKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuField {
                (settings.kind == .session ? Icon.targetThin : Icon.lock).image(size: 16)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24)
                Text(settings.kind.label)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// A menu's button showing its choice: `h-9 w-72 rounded-lg` ringed, its content, a chevron.
private struct MenuField<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer(minLength: 8)
            Icon.chevronDown.image(size: 14).foregroundStyle(Theme.muted)
        }
        .appText(.sm)
        .foregroundStyle(Theme.foreground)
        .padding(.horizontal, 8)
        .frame(width: 288, height: 36)
        .background(Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
        .contentShape(.rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}

#Preview("Calendar events") {
    @Previewable @State var settings = EventImportSettings(calendarIds: ["work", "personal"], goalId: "g1")
    let calendars = [
        ExternalCalendar(id: "work", title: "Work"),
        ExternalCalendar(id: "personal", title: "Personal"),
        ExternalCalendar(id: "holidays", title: "Holidays in Spain"),
    ]
    VStack(spacing: 12) {
        CalendarEventsCard(settings: .defaults, access: .notAsked, calendars: [], goals: Fixtures.calendar.goals)
        CalendarEventsCard(settings: settings, access: .allowed, calendars: calendars, goals: Fixtures.calendar.goals) { settings = $0 }
    }
    .padding(32)
    .frame(width: 768)
    .background(Theme.background)
}
