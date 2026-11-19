import SwiftUI

/*
 * A task's row, closed and open for editing, shared by the goal page's Tasks section and the
 * planning board. Closed: its checkbox, title, first line of description and pills (estimate,
 * plan, due), with a ⋯ menu on hover. Open: the title and description edited in place, saved
 * when it closes.
 */

/// An open task's title and description while they're edited.
struct TaskDraft: Equatable {
    let id: String
    var title: String
    var description: String

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        description = task.description ?? ""
    }

    /// What changed against `task`, or nil when nothing did. An emptied title keeps the old one.
    func patch(for task: TaskItem) -> TaskPatch? {
        var patch = TaskPatch()
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != task.title { patch.title = String(title.prefix(TaskItem.maxTitle)) }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description != (task.description ?? "") { patch.description = String(description.prefix(TaskItem.maxDescription)) }
        return patch == TaskPatch() ? nil : patch
    }
}

// MARK: - A closed row

/// `group relative flex min-h-12 items-start gap-3 rounded-xl px-3 py-1.5 hover:bg-wash/50`
struct GoalTaskRow: View {
    let task: TaskItem
    let horizon: TaskHorizon
    let clock: Clock
    let today: String
    /// The Mondays this week and next start on, for moving it.
    let thisWeek: String
    let nextWeek: String
    let now: Date
    let isDragging: Bool
    let isReorderable: Bool
    let actions: TaskActions
    let onOpen: () -> Void

    @State private var isHovered = false
    @State private var moreAnchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Checkbox(isDone: task.done, isDisabled: task.isPending) { actions.toggle(task) }
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.app(15.2)).foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = task.firstLine {
                            Text(line).appText(.sm).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .inactive(task.isPending)
                .padding(.top, 6)
                .accessibilityLabel("Open “\(task.title)”")

                pills
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 48, alignment: .top)
        .background(background, in: .rect(cornerRadius: 12))
        .overlay {
            if isDragging { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder) }
        }
        .shadow(color: isDragging ? .black.opacity(0.18) : .clear, radius: 14, y: 10)
        .overlay(alignment: .topLeading) {
            // A grip in the left margin: a hint on hover.
            if isReorderable {
                Icon.grip.image(size: 12).foregroundStyle(Theme.muted)
                    .opacity(isDragging ? 0.6 : isEngaged ? 0.5 : 0)
                    .frame(width: 18, height: 21)
                    .offset(x: -6, y: 12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Floats over the content's corner on hover, so the text keeps the full width.
            if !task.isPending {
                SmallMoreButton(isActive: menuIsOpen, action: openMenu)
                    .modifier(AnchorReader(frame: $moreAnchor))
                    .padding(.trailing, 8)
                    .padding(.top, 10)
                    .opacity(isEngaged ? 1 : 0)
            }
        }
        .opacity(task.isPending ? 0.6 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isEngaged)
    }

    /// One of this row's menus is open (its pills or ⋯): the pointer is off in the menu, but the row
    /// stays as it was on hover, like the web's `group-has-[[data-state=open]]`.
    private var menuIsOpen: Bool { overlays?.presented?.owner?.hasPrefix(task.id) == true }

    /// Hovered, or one of its menus is open.
    private var isEngaged: Bool { isHovered || menuIsOpen }

    private var background: Color {
        if isDragging { return Theme.card }
        return isEngaged ? Theme.wash.opacity(0.5) : .clear
    }

    @ViewBuilder private var pills: some View {
        FlowLayout(spacing: 8) {
            EstimatePill(minutes: task.minutes, isPending: task.isPending, owner: task.id) { actions.edit(task, TaskPatch(minutes: $0)) }
            if horizon.carriedWeeks > 0 {
                TaskPill(icon: .refresh, text: horizon.carriedWeeks == 1 ? "Carried over" : "Carried over ×\(horizon.carriedWeeks)", tone: Self.amber)
                    .help("Planned for an earlier week and not done yet")
            }
            if let at = task.scheduledAt {
                HStack(spacing: 4) {
                    Icon.calendarSmall.image(size: 12)
                    Text(Self.scheduleLabel(at, clock: clock, now: now)).appText(.xs)
                }
                .foregroundStyle(Theme.muted)
            }
            // A time on the calendar says when already; the planned day follows it.
            // Set pills first and empty ones after, so a hidden empty pill never leaves a gap.
            let plan = task.scheduledAt == nil ? planPill : nil
            if task.plannedFor == nil, task.dueOn != nil {
                duePill
                plan
            } else {
                plan
                duePill
            }
        }
    }

    /// As a planned day that slipped (TaskDayKind.describe).
    private static let amber = Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24))

    private var planPill: TaskPlanPill {
        TaskPlanPill(task: task, today: today, isQuiet: !isEngaged, owner: task.id) { actions.edit(task, $0) }
    }

    private var duePill: TaskDayPill {
        TaskDayPill(kind: .due, value: task.dueOn, today: today, isQuiet: !isEngaged, owner: task.id) {
            actions.edit(task, TaskPatch(dueOn: $0 ?? ""))
        }
    }

    private func openMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: moreAnchor, owner: task.id) {
            MenuPanel {
                MenuItem(icon: .view, title: "Open") {
                    overlays.dismiss()
                    onOpen()
                }
                MenuSeparator()
                // Moving to a week drops its day; Unplanned clears both.
                if horizon.group != .thisWeek {
                    MenuItem(icon: .calendarSmall, title: "Move to this week") { move(week: thisWeek) }
                }
                if horizon.group != .nextWeek {
                    MenuItem(icon: .arrowForward, title: "Move to next week") { move(week: nextWeek) }
                }
                if horizon.group != .later {
                    MenuItem(icon: .dashedCircle, title: "Move to Unplanned") { move(week: "") }
                }
                MenuSeparator()
                MenuItem(icon: .delete, title: "Delete", isDestructive: true) {
                    overlays.dismiss()
                    actions.delete(task)
                }
            }
        }
    }

    private func move(week: String) {
        overlays?.dismiss()
        actions.place(task, TaskPatch(plannedFor: "", plannedWeek: week), nil)
    }

    /// "Today 2:00 PM", "Tomorrow 09:30" or "Thu 14:00", in this Mac's time zone.
    static func scheduleLabel(_ at: Date, clock: Clock, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: at)).day ?? 0
        let day = days == 0 ? "Today" : days == 1 ? "Tomorrow" : at.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "en_US")))
        let parts = calendar.dateComponents([.hour, .minute], from: at)
        return "\(day) \(clock.format(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0)))"
    }
}

// MARK: - An open row

/// The task being edited, in place: `rounded-xl bg-wash/70 px-3 pb-3 pt-1.5`.
struct OpenTaskRow: View {
    let task: TaskItem
    @Binding var draft: TaskDraft
    let today: String
    let actions: TaskActions
    let onClose: () -> Void

    /// Opens on the description, ready to add to it.
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, description }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Checkbox(isDone: task.done, isDisabled: false) {
                onClose()
                actions.toggle(task)
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.app(15.2))
                    .foregroundStyle(Theme.foreground)
                    .focused($focus, equals: .title)
                    .accessibilityLabel("Task")
                    // Return moves on to the description, as on the web.
                    .onSubmit { focus = .description }
                    .padding(.top, 6)
                TextField("", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1...12)
                    .focused($focus, equals: .description)
                    .placeholder("Add a description…", when: draft.description.isEmpty, font: .app(14))
                    .accessibilityLabel("Description")
                FlowLayout(spacing: 8) {
                    EstimatePill(minutes: task.minutes) { actions.edit(task, TaskPatch(minutes: $0)) }
                    TaskPlanPill(task: task, today: today) { actions.edit(task, $0) }
                    TaskDayPill(kind: .due, value: task.dueOn, today: today) {
                        actions.edit(task, TaskPatch(dueOn: $0 ?? ""))
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash.opacity(0.7), in: .rect(cornerRadius: 12))
        .onAppear { focus = .description }
        .onExitCommand(perform: onClose)
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onClose()
            return .handled
        }
    }
}

// MARK: - Pieces

/// The plan pill: a day, this week or next, or nothing yet. Clearing it leaves the task unplanned.
struct TaskPlanPill: View {
    let task: TaskItem
    let today: String
    var isQuiet = false
    var owner: String?
    let onPatch: (TaskPatch) -> Void

    var body: some View {
        TaskDayPill(
            kind: .plan, value: task.plannedFor, today: today, isQuiet: isQuiet, owner: owner,
            week: task.plannedWeek,
            onWeek: { onPatch(TaskPatch(plannedFor: "", plannedWeek: $0)) }
        ) { day in
            onPatch(day.map { TaskPatch(plannedFor: $0) } ?? TaskPatch(plannedFor: "", plannedWeek: ""))
        }
    }
}

/// The round checkbox: `h-[18px] w-[18px] rounded-full border-[1.5px] border-foreground/30`,
/// a faint tick on hover.
struct Checkbox: View {
    let isDone: Bool
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.tickBold.image(size: 12)
                .foregroundStyle(isDone ? Theme.foreground : isHovered ? Theme.foreground(0.4) : .clear)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.foreground(isHovered ? 0.6 : 0.3), lineWidth: 1.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .inactive(isDisabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Mark as done")
    }
}

