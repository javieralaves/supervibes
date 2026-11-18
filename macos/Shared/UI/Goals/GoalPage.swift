import SwiftUI

/// Saving "This week": idle, saving, or why it failed.
enum WeekObjectiveState: Equatable {
    case idle, saving
    case failed(String)
}

/// A goal's own page, matching src/app/(app)/goals/[id]: "All goals", the header, this week's
/// objective and the progress card. Tasks, notes and sources follow in `sections`.
struct GoalPage<Sections: View>: View {
    let detail: GoalDetail
    /// A read was asked for here and hasn't been picked up yet.
    var requestingRead = false
    var readError: String?
    var headerError: String?
    var weekState: WeekObjectiveState = .idle
    /// For "2 hr ago"; fixed in snapshots.
    var now = Date()
    var onBack: () -> Void = {}
    var onUpdateStatus: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSaveWeek: (String) -> Void = { _ in }
    /// A click on the page outside its controls, e.g. to close an open task.
    var onBackgroundTap: () -> Void = {}
    @ViewBuilder var sections: Sections

    private var reading: Bool { detail.readPending || requestingRead }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(action: onBack).padding(.bottom, 32)
                GoalHeader(
                    detail: detail,
                    reading: reading,
                    error: headerError,
                    onUpdateStatus: onUpdateStatus,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
                WeekObjective(week: detail.week, state: weekState, onSave: onSaveWeek)
                    .id(detail.week.start)
                    .padding(.top, 32)
                ProgressCard(detail: detail, reading: reading, error: readError ?? detail.readError, now: now, onUpdate: onUpdateStatus)
                    .padding(.top, 40)
                sections
            }
            .frame(maxWidth: 768, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
            .background(Color.clear.contentShape(.rect).onTapGesture(perform: onBackgroundTap))
        }
        .scrollContentBackground(.hidden)
    }
}

extension GoalPage where Sections == EmptyView {
    init(
        detail: GoalDetail,
        requestingRead: Bool = false,
        readError: String? = nil,
        headerError: String? = nil,
        weekState: WeekObjectiveState = .idle,
        now: Date = Date()
    ) {
        self.init(
            detail: detail, requestingRead: requestingRead, readError: readError,
            headerError: headerError, weekState: weekState, now: now
        ) { EmptyView() }
    }
}

/// "← All goals": `text-sm font-medium text-muted hover:text-foreground`
private struct BackLink: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text("All goals").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Header

private struct GoalHeader: View {
    let detail: GoalDetail
    let reading: Bool
    let error: String?
    let onUpdateStatus: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.overlays) private var overlays
    @State private var menuAnchor = CGRect.zero

    var body: some View {
        let goal = detail.goal
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GoalBadge(icon: goal.icon, color: goal.color, size: .lg)
                Spacer()
                RoundIconButton(icon: .more, action: openMenu)
                    .modifier(AnchorReader(frame: $menuAnchor))
                    .accessibilityLabel("Goal options")
            }

            Text(goal.title)
                .appText(.xl3, .semibold, tracking: -0.03)
                .foregroundStyle(Theme.foreground)
                .padding(.top, 20)

            if let target = goal.targetDate {
                let days = CalendarDay.daysUntil(target, today: detail.today)
                HStack(spacing: 6) {
                    Icon.calendarSmall.image(size: 14)
                    Text("\(CalendarDay.format(target, today: detail.today)) · \(CalendarDay.relative(days))")
                        .appText(.sm).monospacedDigit()
                }
                .foregroundStyle(days < 0 ? Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24)) : Theme.muted)
                .padding(.top, 8)
            }

            if let description = goal.description, !description.isEmpty {
                Text(description)
                    .font(.app(15.2))
                    .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                    .foregroundStyle(Theme.foreground(0.75))
                    .frame(maxWidth: 672, alignment: .leading)
                    .padding(.top, 12)
            }

            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 16)
            }
        }
    }

    private func openMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: menuAnchor) {
            MenuPanel {
                MenuItem(
                    icon: .refresh,
                    title: reading ? "Updating…" : "Update status",
                    isDisabled: !detail.canRead || reading
                ) {
                    overlays.dismiss()
                    onUpdateStatus()
                }
                MenuItem(icon: .edit, title: "Edit goal") {
                    overlays.dismiss()
                    onEdit()
                }
                MenuItem(icon: .delete, title: "Delete goal", isDestructive: true) {
                    overlays.dismiss()
                    onDelete()
                }
            }
        }
    }
}

// MARK: - This week

/// "This week": what the week should move for this goal, saved when the field loses focus.
/// Last week's sits under an empty field for continuity.
private struct WeekObjective: View {
    let week: GoalDetail.Week
    let state: WeekObjectiveState
    let onSave: (String) -> Void

    @State private var draft: String
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(week: GoalDetail.Week, state: WeekObjectiveState, onSave: @escaping (String) -> Void) {
        self.week = week
        self.state = state
        self.onSave = onSave
        _draft = State(initialValue: week.objective ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("This week").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                Text(CalendarDay.formatWeek(week.start)).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
                if state == .saving {
                    Text("Saving…").appText(.xs).foregroundStyle(Theme.muted)
                }
            }

            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(15.2))
                .foregroundStyle(Theme.foreground(0.9))
                .lineLimit(1...8)
                .focused($isFocused)
                .placeholder("What should this week move for this goal? (optional)", when: draft.isEmpty, font: .app(15.2))
                .accessibilityLabel("What this week should move for this goal")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isHovered || isFocused ? Theme.wash.opacity(0.6) : .clear, in: .rect(cornerRadius: 8))
                .padding(.horizontal, -8)
                .padding(.top, 4)
                .frame(maxWidth: 672, alignment: .leading)
                .onHover { isHovered = $0 }
                .help("Progress reads judge the week against it, and agendas and recaps take it into account")
                .onChange(of: isFocused) { _, focused in if !focused { save() } }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    isFocused = false
                    return .handled
                }
                .onExitCommand {
                    draft = week.objective ?? ""
                    isFocused = false
                }

            if let lastWeek = week.lastWeek, draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("\(Text("Last week:").fontWeight(.medium)) \(lastWeek)")
                    .appText(.xs).foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .frame(maxWidth: 672, alignment: .leading)
                    .padding(.top, 2)
            }
            if case .failed(let message) = state {
                Text(message).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 4)
            }
        }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (week.objective ?? "") else { return }
        onSave(value)
    }
}

// MARK: - Progress

/// The single high-level read of progress on a goal: status, headline and summary, the last
/// weeks, and what it was based on.
private struct ProgressCard: View {
    let detail: GoalDetail
    let reading: Bool
    let error: String?
    let now: Date
    let onUpdate: () -> Void

    var body: some View {
        Card {
            if let read = detail.read {
                withRead(read)
            } else {
                firstRead
            }
        }
    }

    @ViewBuilder private var note: some View {
        if reading {
            Text("Reading your sources. This can take a minute.").appText(.xs).foregroundStyle(Theme.muted)
        } else if let error {
            Text(error).appText(.xs).foregroundStyle(Theme.danger)
        }
    }

    @ViewBuilder private var firstRead: some View {
        Text(detail.canRead ? "Ready for a first read" : "No read yet")
            .appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
        Text(detail.canRead
            ? "Supervibes will look at your tasks, notes and sources and tell you, in a few lines, whether you’re moving forward."
            : "Add a task, a note or a source below. Supervibes will read them and tell you, in a few lines, whether you’re moving forward.")
            .appText(.sm).foregroundStyle(Theme.muted)
            .padding(.top, 4)
        if detail.canRead {
            UpdateButton(reading: reading, action: onUpdate).padding(.top, 20)
        }
        note.padding(.top, 12)
    }

    @ViewBuilder private func withRead(_ read: GoalDetail.Read) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let status = detail.status {
                StatusPill(status: status.status, basis: status.basis).padding(.bottom, 12)
            }
            Text(read.headline)
                .appText(.xl, .semibold, tracking: -0.02)
                .foregroundStyle(Theme.foreground)
            Text(read.summary)
                .font(.app(15.2))
                .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
        }
        .compositingGroup()
        .opacity(reading ? 0.5 : 1)

        if detail.status != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last 4 weeks")
                    Spacer()
                    if let target = detail.goal.targetDate {
                        Text("Target \(CalendarDay.format(target, today: detail.today))").monospacedDigit()
                    }
                }
                .font(.app(11)).foregroundStyle(Theme.muted)
                TrajectoryDays(days: detail.goal.trajectory, today: detail.today)
                if detail.readsInTrajectory < 3 {
                    Text("A few more days of reads will show a trend.").font(.app(11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 20)
            .zIndex(1)
        }

        HStack(spacing: 12) {
            HStack(spacing: 8) {
                BasedOn(basedOn: read.basedOn)
                Text(read.createdAt.shortAgo(now: now)).appText(.xs)
            }
            if reading { SpinningIcon(size: 13) }
            note
        }
        .foregroundStyle(Theme.muted)
        .padding(.top, 20)
    }
}

/// `h-9 rounded-xl border px-3 text-sm font-medium`, its icon spinning while a read runs.
private struct UpdateButton: View {
    let reading: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if reading { SpinningIcon(size: 15) } else { Icon.refresh.image(size: 15) }
                Text(reading ? "Reading…" : "Update status").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .compositingGroup()
            .opacity(reading ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .inactive(reading)
        .onHover { isHovered = $0 }
    }
}

/// The refresh icon, turning.
struct SpinningIcon: View {
    let size: CGFloat
    @State private var turning = false
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        Icon.refresh.image(size: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turning)
            .onAppear { if !staticRendering { turning = true } }
    }
}

/// The apps and notes or tasks a read was based on, as small marks.
private struct BasedOn: View {
    let basedOn: [String]

    private var apps: [ConnectionItem.Provider] {
        var seen: [ConnectionItem.Provider] = []
        for value in basedOn {
            let key = value.lowercased()
            if let provider = ConnectionItem.Provider(rawValue: key), !seen.contains(provider) { seen.append(provider) }
        }
        return seen
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(apps, id: \.self) { ProviderMark(provider: $0, size: 18) }
            if basedOn.contains("notes") { Tile(icon: .note) }
            if basedOn.contains("tasks") { Tile(icon: .checklist) }
        }
    }

    /// `h-[18px] w-[18px] rounded-[5px] border bg-wash`
    private struct Tile: View {
        let icon: Icon

        var body: some View {
            icon.image(size: 11)
                .foregroundStyle(Theme.foreground)
                .frame(width: 18, height: 18)
                .background(Theme.wash, in: .rect(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
        }
    }
}
