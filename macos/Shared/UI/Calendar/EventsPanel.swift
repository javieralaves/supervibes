import SwiftUI

/*
 * Calendar import's events panel: the events in the person's Google calendars, a day at a time,
 * where the block panel opens. Nothing from it is on the calendar until imported. Hovering an event
 * shows the goal it would go to (the default from Settings; click to pick another) and Import, and
 * its time is previewed on the grid. Designed in supervibes-design ("Calendar import", 2 and 3).
 */

/// One day's events in the panel.
struct EventDay: Identifiable, Hashable {
    /// Days from today.
    let day: Int
    let label: String
    let events: [ExternalEvent]
    var id: Int { day }
}

/// Where an event not on the calendar would go: drawn on the grid while it's hovered.
struct EventPreview: Hashable, Sendable {
    /// Days from today, and minutes from that day's midnight.
    let day: Int
    let start: Int
    let end: Int
    let title: String
    /// The goal colour it would take.
    let color: String

    init(day: Int, start: Int, end: Int, title: String, color: String) {
        self.day = day
        self.start = start
        self.end = end
        self.title = title
        self.color = color
    }

    /// An event's time on its first day, at least 15 minutes as a block would be.
    init(event: ExternalEvent, color: String, now: Date) {
        let times = ImportCheck.blockTimes(event.start, event.end)
        day = CalendarDayMath.dayOffset(times.start, from: now)
        start = CalendarDayMath.minutes(times.start)
        end = CalendarDayMath.dayOffset(times.end, from: now) > day ? CalendarDayMath.dayMinutes : CalendarDayMath.minutes(times.end)
        title = event.title
        self.color = color
    }
}

extension EventPreview {
    /// Whether it falls on a block that day: it's then drawn on the right half, over the block.
    func overlaps(_ blocks: [CalendarBlock], now: Date) -> Bool {
        blocks.contains { block in
            guard !block.isPending, CalendarDayMath.dayOffset(block.startsAt, from: now) == day else { return false }
            let blockStart = CalendarDayMath.minutes(block.startsAt)
            let blockEnd = CalendarDayMath.dayOffset(block.endsAt, from: now) > day ? CalendarDayMath.dayMinutes : CalendarDayMath.minutes(block.endsAt)
            return blockStart < end && start < blockEnd
        }
    }
}

extension EnvironmentValues {
    /// The hovered event's time, for the day and week grids to draw.
    @Entry var eventPreview: EventPreview?
}

struct EventsPanel: View {
    let days: [EventDay]
    let goals: [CalendarGoal]
    /// The goal each imported event went to, by event key.
    let imported: [String: String]
    /// The goal an import goes to unless another is picked.
    let defaultGoalId: String?
    /// When the events were last read.
    let lastRead: Date?
    var clock: Clock = .twelveHour
    /// The event just imported from here: its row offers Undo.
    var justImported: String?
    /// The event under the pointer, and the goal it would go to; nil when none.
    var onHover: (ExternalEvent?, String?) -> Void = { _, _ in }
    var onImport: (ExternalEvent, String) -> Void = { _, _ in }
    var onUndo: (ExternalEvent) -> Void = { _ in }
    var onSync: () -> Void = {}
    var onClose: () -> Void = {}

    @State private var hovered: String?
    /// Goals picked for an event instead of the default, by event key.
    @State private var picked: [String: String] = [:]

    init(days: [EventDay], goals: [CalendarGoal], imported: [String: String], defaultGoalId: String?, lastRead: Date?,
         clock: Clock = .twelveHour, justImported: String? = nil, hovered: String? = nil,
         onHover: @escaping (ExternalEvent?, String?) -> Void = { _, _ in }, onImport: @escaping (ExternalEvent, String) -> Void = { _, _ in },
         onUndo: @escaping (ExternalEvent) -> Void = { _ in }, onSync: @escaping () -> Void = {}, onClose: @escaping () -> Void = {}) {
        self.days = days
        self.goals = goals
        self.imported = imported
        self.defaultGoalId = defaultGoalId
        self.lastRead = lastRead
        self.clock = clock
        self.justImported = justImported
        self.onHover = onHover
        self.onImport = onImport
        self.onUndo = onUndo
        self.onSync = onSync
        self.onClose = onClose
        _hovered = State(initialValue: hovered)
    }

    private var synced: String {
        guard let lastRead else { return "From Google" }
        return "From Google · synced \(clock.format(minutes: CalendarDayMath.minutes(lastRead)))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Events").appText(.lg, .semibold, tracking: -0.01).foregroundStyle(Theme.foreground)
                        Text(synced).appText(.xs).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    PanelIconButton(icon: .refresh, label: "Sync now", action: onSync)
                    PanelIconButton(icon: .close, label: "Close", action: onClose)
                }

                if days.isEmpty {
                    Text("No events in your Google calendars on these days.")
                        .appText(.sm).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }

                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.label).appText(.xs, .medium).foregroundStyle(Theme.muted)
                        ForEach(day.events) { event in
                            row(event)
                        }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Events")
    }

    private func goalId(for event: ExternalEvent) -> String? {
        picked[event.key] ?? defaultGoalId
    }

    private func row(_ event: ExternalEvent) -> some View {
        EventRow(
            event: event,
            time: clock.format(minutes: CalendarDayMath.minutes(event.start)),
            length: durationLabel(event.end.timeIntervalSince(event.start) / 60),
            importedTo: imported[event.key].flatMap { id in goals.first { $0.id == id } },
            isJustImported: justImported == event.key,
            isHovered: hovered == event.key && imported[event.key] == nil,
            goal: goalId(for: event).flatMap { id in goals.first { $0.id == id } },
            goals: goals,
            onPick: { id in
                picked[event.key] = id
                onHover(event, id)
            },
            onImport: {
                guard let id = goalId(for: event) else { return }
                onImport(event, id)
                hovered = nil
                onHover(nil, nil)
            },
            onUndo: { onUndo(event) }
        )
        .onHover { inside in
            if inside {
                hovered = event.key
                onHover(imported[event.key] == nil ? event : nil, goalId(for: event))
            } else if hovered == event.key {
                hovered = nil
                onHover(nil, nil)
            }
        }
    }
}

/// One event: its start, title, calendar and length. Imported, it's quieter and says where it went;
/// under the pointer, the goal it would go to and Import.
private struct EventRow: View {
    let event: ExternalEvent
    let time: String
    let length: String
    let importedTo: CalendarGoal?
    let isJustImported: Bool
    let isHovered: Bool
    let goal: CalendarGoal?
    let goals: [CalendarGoal]
    let onPick: (String) -> Void
    let onImport: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Untitled event" : event.title)
                    .appText(.px(13), .medium)
                    .foregroundStyle(importedTo == nil ? Theme.foreground : Theme.muted)
                    .lineLimit(1)
                detail
                if isHovered {
                    HStack(spacing: 6) {
                        GoalChip(goal: goal, goals: goals, onPick: onPick)
                        ImportButton(action: onImport)
                    }
                    .padding(.top, 6)
                    if event.repeats {
                        Text("Imports only this one.").appText(.xs).foregroundStyle(Theme.muted).padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
        .padding(.horizontal, -8)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var detail: some View {
        if isJustImported, let importedTo {
            HStack(spacing: 6) {
                Icon.tick.image(size: 16).padding(.vertical, -2)
                Text("Imported to \(importedTo.title)").lineLimit(1)
                Button("Undo", action: onUndo)
                    .buttonStyle(.plain)
                    .font(.app(12, .semibold))
                    .pointerStyle(.link)
            }
            .appText(.xs)
            .foregroundStyle(Theme.foreground)
        } else if let importedTo {
            HStack(spacing: 6) {
                Circle().fill(GoalPalette.color(importedTo.color)).frame(width: 6, height: 6)
                Text("Imported to \(importedTo.title)").lineLimit(1)
            }
            .appText(.xs)
            .foregroundStyle(Theme.muted)
        } else {
            HStack(spacing: 4) {
                if event.repeats { Icon.repeats.image(size: 11) }
                Text("\(event.calendarName) · \(length)").lineLimit(1)
            }
            .appText(.xs)
            .foregroundStyle(Theme.muted)
        }
    }
}

/// The goal an import goes to, as a small menu: its colour, its title, a chevron.
private struct GoalChip: View {
    let goal: CalendarGoal?
    let goals: [CalendarGoal]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(goals) { option in
                Button {
                    onPick(option.id)
                } label: {
                    if option.id == goal?.id {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(goal.map { GoalPalette.color($0.color) } ?? Theme.muted).frame(width: 8, height: 8)
                Text(goal?.title ?? "No goals yet").lineLimit(1)
                Spacer(minLength: 4)
                Icon.chevronDown.image(size: 12).foregroundStyle(Theme.muted)
            }
            .appText(.xs)
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Theme.card, in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong))
            .contentShape(.rect(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(goals.isEmpty)
        .help("The goal it goes to")
    }
}

private struct ImportButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Import").appText(.xs, .semibold)
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.foreground, in: .rect(cornerRadius: 8))
                .opacity(isHovered ? 0.9 : 1)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .keyboardShortcut(.defaultAction)
    }
}

/// An event's time on the grid without it being on the calendar: a neutral card a shade off the
/// day, ringed with dashes in the goal's colour. Gone when the pointer leaves its row.
struct EventPreviewCard: View {
    let title: String
    let color: String
    let range: String
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.foreground(0.05))
            .background(Theme.card, in: .rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(GoalPalette.color(color).opacity(0.65), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Icon.calendarSmall.image(size: 11).foregroundStyle(Theme.muted)
                        Text(title).font(.app(12, .medium)).foregroundStyle(Theme.foreground(0.75))
                            .lineLimit(height >= 60 ? 2 : 1)
                    }
                    if height >= 56 {
                        Text(range).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, height >= 40 ? 6 : 2)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Events panel") {
    EventsPanel(
        days: Fixtures.eventDays,
        goals: Fixtures.calendar.goals,
        imported: ["research": "g3"],
        defaultGoalId: "g1",
        lastRead: Fixtures.referenceNow,
        hovered: "review"
    )
    .frame(width: 320, height: 640)
    .padding(24)
    .background(Theme.background)
}
