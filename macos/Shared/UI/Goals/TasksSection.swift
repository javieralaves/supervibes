import SwiftUI

/// What the Tasks section asks of whoever owns the data.
struct TaskActions {
    /// A new task's title, and the week it's for (its Monday), or nil for Later.
    var add: (String, String?) -> Void = { _, _ in }
    var toggle: (TaskItem) -> Void = { _ in }
    var edit: (TaskItem, TaskPatch) -> Void = { _, _ in }
    var delete: (TaskItem) -> Void = { _ in }
    /// The open tasks' ids in their new order.
    var reorder: ([String]) -> Void = { _ in }
    /// Moves a task to a day, week or Later: the patch's planned day and week, an empty string clearing.
    var place: (TaskItem, TaskPatch) -> Void = { _, _ in }
    var acceptSuggestion: (TaskSuggestion) -> Void = { _ in }
    var passOnSuggestion: (TaskSuggestion) -> Void = { _ in }
    /// Runs a new read, which brings new suggestions.
    var refresh: () -> Void = {}
}

/// A goal's open tasks, grouped by how they're planned: for a day, for this week, for next week, or
/// Later (captured, not committed to yet, and folded away). Click one to open it in place and add a
/// description; it saves when it closes (Esc, ⌘Return, a click elsewhere, or opening another).
/// Within a week or Later, drag a row, or press ⌥↑ / ⌥↓ on it, to reorder: that order is what reads
/// and agendas follow. A row's plan pill gives it a day; its ⋯ menu moves it to another week or
/// Later. Under the list, the latest read's suggestions to add or pass on.
struct TasksSection: View {
    let tasks: [TaskItem]
    let suggestions: [TaskSuggestion]
    /// Before the first read there's nothing to suggest.
    let hasRead: Bool
    let reading: Bool
    let clock: Clock
    /// Today, "YYYY-MM-DD".
    let today: String
    var error: String?
    /// Changes when the page is clicked outside the tasks, closing an open one.
    var closeSignal = 0
    /// Opens with this task open, for snapshot tests.
    var initiallyOpen: String?
    /// Opens with Later unfolded, for snapshot tests.
    var initiallyShowsLater = false
    /// For "Today 2:00 PM"; fixed in snapshots.
    var now = Date()
    var actions = TaskActions()

    @State private var draft: Draft?
    @State private var newTitles: [TaskHorizon.Group: String] = [:]
    @State private var showsLater = false
    @State private var drag: Drag?
    /// After a drop: how far the dropped row still is from its new slot, gliding to zero.
    @State private var settle: Settle?
    @State private var heights: [String: CGFloat] = [:]
    @FocusState private var focus: Field?

    struct Draft: Equatable {
        let id: String
        var title: String
        var description: String
    }

    struct Drag: Equatable {
        let id: String
        let group: TaskHorizon.Group
        let from: Int
        var to: Int
        var dy: CGFloat
    }

    struct Settle: Equatable {
        let id: String
        var dy: CGFloat
    }

    enum Field: Hashable {
        case row(String), title, description, new(TaskHorizon.Group)
    }

    /// The space between rows (`gap-0.5`).
    private static let gap: CGFloat = 2

    /// The Mondays this week and next start on.
    private var thisWeek: String { CalendarDay.weekStart(today) }
    private var nextWeek: String { CalendarDay.addDays(thisWeek, 7) }

    /// The open tasks by where they stand, each group in the person's order; planned days soonest first.
    private var groups: [TaskHorizon.Group: [TaskItem]] {
        var groups = Dictionary(grouping: tasks) { $0.horizon(today: today).group }
        groups[.day] = groups[.day]?.enumerated()
            .sorted { ($0.element.plannedFor ?? "", $0.offset) < ($1.element.plannedFor ?? "", $1.offset) }
            .map(\.element)
        return groups
    }

    /// Planned days follow their dates; weeks and Later can be put in order.
    private func canReorder(_ rows: [TaskItem], in group: TaskHorizon.Group) -> Bool {
        group != .day && draft == nil && rows.count > 1 && !tasks.contains { $0.isPending }
    }

    var body: some View {
        let groups = self.groups
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tasks").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                Text("What you’ve decided to do for this goal, and when.").appText(.sm).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 0) {
                if let planned = groups[.day], !planned.isEmpty {
                    section(.day, rows: planned)
                }
                section(.thisWeek, rows: groups[.thisWeek] ?? [])
                section(.nextWeek, rows: groups[.nextWeek] ?? [])
                section(.later, rows: groups[.later] ?? [])
            }
            .padding(6)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))

            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 8)
            }

            if hasRead {
                SuggestionsList(suggestions: suggestions, reading: reading, actions: actions)
                    .padding(.top, 24)
            }
        }
        .padding(.top, 48)
        .onAppear {
            showsLater = initiallyShowsLater
            if let id = initiallyOpen, let task = tasks.first(where: { $0.id == id }) {
                draft = Draft(id: task.id, title: task.title, description: task.description ?? "")
            }
        }
        .onChange(of: closeSignal) { closeTask() }
    }

    // MARK: Sections

    @ViewBuilder private func section(_ group: TaskHorizon.Group, rows: [TaskItem]) -> some View {
        sectionHeader(group, count: rows.count)
        if group == .thisWeek, let carried = rows.first(where: { !$0.isPending && $0.horizon(today: today).carriedWeeks >= 2 }) {
            CarriedOverPrompt(
                task: carried,
                weeks: carried.horizon(today: today).carriedWeeks,
                keep: { actions.place(carried, TaskPatch(plannedFor: "", plannedWeek: thisWeek)) },
                later: { actions.place(carried, TaskPatch(plannedFor: "", plannedWeek: "")) }
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        if !rows.isEmpty, group != .later || showsLater {
            VStack(spacing: Self.gap) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                    row(task, index: index, rows: rows, group: group)
                }
            }
        }
        if group != .day { newTaskField(group) }
    }

    @ViewBuilder private func sectionHeader(_ group: TaskHorizon.Group, count: Int) -> some View {
        let label = HStack(spacing: 6) {
            switch group {
            case .day:
                Text("Planned").appText(.xs, .medium).foregroundStyle(Theme.muted)
            case .thisWeek:
                Text("This week").appText(.xs, .medium).foregroundStyle(Theme.muted)
                Text(CalendarDay.formatWeek(thisWeek)).appText(.xs).foregroundStyle(Theme.muted.opacity(0.7))
            case .nextWeek:
                Text("Next week").appText(.xs, .medium).foregroundStyle(Theme.muted)
                Text(CalendarDay.formatWeek(nextWeek)).appText(.xs).foregroundStyle(Theme.muted.opacity(0.7))
            case .later:
                Text("Later").appText(.xs, .medium).foregroundStyle(Theme.muted)
                if count > 0 {
                    Text("\(count)").appText(.xs).foregroundStyle(Theme.muted.opacity(0.7)).monospacedDigit()
                    Icon.chevronDown.image(size: 12).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(showsLater ? 0 : -90))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, group == .day || (group == .thisWeek && groups[.day]?.isEmpty != false) ? 6 : 14)
        .padding(.bottom, 4)

        if group == .later, count > 0 {
            Button { withAnimation(.easeOut(duration: 0.15)) { showsLater.toggle() } } label: { label.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(showsLater ? "Fold away Later" : "Show Later")
        } else {
            label
        }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ task: TaskItem, index: Int, rows: [TaskItem], group: TaskHorizon.Group) -> some View {
        if let draft, draft.id == task.id {
            OpenTaskRow(
                task: task,
                draft: Binding(get: { self.draft ?? draft }, set: { self.draft = $0 }),
                today: today,
                focus: $focus,
                actions: actions,
                onClose: closeTask
            )
        } else {
            let reorderable = canReorder(rows, in: group)
            TaskRow(
                task: task,
                horizon: task.horizon(today: today),
                clock: clock,
                today: today,
                thisWeek: thisWeek,
                nextWeek: nextWeek,
                now: now,
                isDragging: drag?.id == task.id,
                isReorderable: reorderable,
                actions: actions,
                onOpen: { open(task) }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[task.id] = $0 }
            .offset(y: offset(for: task, at: index, in: group))
            .zIndex(drag?.id == task.id ? 1 : 0)
            // Rows the dragged one passes slide aside; the dragged one follows the pointer exactly.
            .animation(drag?.id == task.id ? nil : .easeOut(duration: 0.15), value: drag)
            // High priority, so a press on the title (a button) still becomes a drag once it moves
            // past a few points; a click without moving still opens the task.
            .highPriorityGesture(dragGesture(task, index: index, rows: rows, group: group), including: reorderable ? .all : .subviews)
            .focusable(reorderable && !task.isPending)
            .focusEffectDisabled()
            .focused($focus, equals: .row(task.id))
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                guard press.modifiers.contains(.option) else { return .ignored }
                move(task, by: press.key == .upArrow ? -1 : 1, in: rows, group: group)
                return .handled
            }
        }
    }

    private func newTaskField(_ group: TaskHorizon.Group) -> some View {
        let title = Binding(get: { newTitles[group] ?? "" }, set: { newTitles[group] = $0 })
        let placeholder = switch group {
        case .thisWeek: "Add to this week"
        case .nextWeek: "Add to next week"
        default: "Add a task for later"
        }
        return HStack(spacing: 12) {
            Icon.add.image(size: 16).foregroundStyle(Theme.muted).frame(width: 18)
            TextField("", text: title)
                .textFieldStyle(.plain)
                .font(.app(15.2))
                .foregroundStyle(Theme.foreground)
                .focused($focus, equals: .new(group))
                .placeholder(placeholder, when: title.wrappedValue.isEmpty, font: .app(15.2), color: Theme.muted.opacity(0.8))
                .accessibilityLabel(placeholder)
                .onSubmit { addTask(to: group) }
                .onExitCommand { newTitles[group] = "" }
            if !title.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("↵ to add").appText(.xs).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    // MARK: Editing

    private func addTask(to group: TaskHorizon.Group) {
        let title = (newTitles[group] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTitles[group] = ""
        let week: String? = switch group {
        case .thisWeek: thisWeek
        case .nextWeek: nextWeek
        default: nil
        }
        actions.add(String(title.prefix(TaskItem.maxTitle)), week)
        // So what was just added shows.
        if group == .later { showsLater = true }
        // Enter adds it and keeps the cursor here for the next.
        focus = .new(group)
    }

    private func open(_ task: TaskItem) {
        guard !task.isPending else { return }
        if let draft, draft.id != task.id { commit(draft) }
        draft = Draft(id: task.id, title: task.title, description: task.description ?? "")
        focus = .description
    }

    private func closeTask() {
        guard let current = draft else { return }
        commit(current)
        draft = nil
    }

    /// Saves whatever changed in the open task. An emptied title keeps the old one.
    private func commit(_ draft: Draft) {
        guard let task = tasks.first(where: { $0.id == draft.id }) else { return }
        var patch = TaskPatch()
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != task.title { patch.title = String(title.prefix(TaskItem.maxTitle)) }
        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description != (task.description ?? "") { patch.description = String(description.prefix(TaskItem.maxDescription)) }
        if patch != TaskPatch() { actions.edit(task, patch) }
    }

    // MARK: Reordering

    /// Where a row sits while a task is dragged: the dragged one follows the pointer, the ones it
    /// passes in its group slide aside to make room.
    private func offset(for task: TaskItem, at index: Int, in group: TaskHorizon.Group) -> CGFloat {
        if let settle, settle.id == task.id { return settle.dy }
        guard let drag, drag.group == group else { return 0 }
        if task.id == drag.id { return drag.dy }
        let shift = (heights[drag.id] ?? 48) + Self.gap
        if drag.from < drag.to, index > drag.from, index <= drag.to { return -shift }
        if drag.to < drag.from, index >= drag.to, index < drag.from { return shift }
        return 0
    }

    private func dragGesture(_ task: TaskItem, index: Int, rows: [TaskItem], group: TaskHorizon.Group) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard canReorder(rows, in: group) || drag != nil else { return }
                let dy = value.translation.height
                // Its landing spot: past every other row in its group whose middle it has crossed.
                var top: CGFloat = 0
                var tops: [CGFloat] = []
                for item in rows {
                    tops.append(top)
                    top += (heights[item.id] ?? 48) + Self.gap
                }
                let center = tops[index] + (heights[task.id] ?? 48) / 2 + dy
                let to = rows.indices.reduce(0) { count, i in
                    i != index && tops[i] + (heights[rows[i].id] ?? 48) / 2 < center ? count + 1 : count
                }
                drag = Drag(id: task.id, group: group, from: index, to: to, dy: dy)
            }
            .onEnded { _ in
                guard let ended = drag else { return }
                // How far the new slot is from the old one: the rows it passed, and the gaps.
                let passed = ended.to > ended.from
                    ? Array(rows[(ended.from + 1)...ended.to])
                    : ended.to < ended.from ? Array(rows[ended.to..<ended.from]) : []
                let distance = passed.reduce(0) { $0 + (heights[$1.id] ?? 48) + Self.gap }
                let slot = ended.to > ended.from ? distance : -distance

                // In one step with no animation, the order changes and every row takes its new place,
                // with the dropped row held where the pointer left it. Then only that row glides the
                // last bit into its slot, so nothing moves twice.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    if ended.to != ended.from {
                        var ids = rows.map(\.id)
                        ids.insert(ids.remove(at: ended.from), at: ended.to)
                        reorder(group: ids)
                    }
                    drag = nil
                    settle = Settle(id: ended.id, dy: ended.dy - slot)
                }
                withAnimation(.easeOut(duration: 0.18)) { settle = nil }
            }
    }

    /// ⌥↑ / ⌥↓ on a task: one place up or down in its group.
    private func move(_ task: TaskItem, by step: Int, in rows: [TaskItem], group: TaskHorizon.Group) {
        guard canReorder(rows, in: group), let from = rows.firstIndex(where: { $0.id == task.id }) else { return }
        let to = from + step
        guard rows.indices.contains(to) else { return }
        var ids = rows.map(\.id)
        ids.insert(ids.remove(at: from), at: to)
        withAnimation(.easeOut(duration: 0.18)) { reorder(group: ids) }
        focus = .row(task.id)
    }

    /// A group's new order, as the whole list: its tasks take the same slots among the others, in this order.
    private func reorder(group ids: [String]) {
        let moved = Set(ids)
        var next = ids.makeIterator()
        actions.reorder(tasks.map { moved.contains($0.id) ? next.next() ?? $0.id : $0.id })
    }
}

/// "This has carried over twice": keep it for this week, or let it go to Later.
private struct CarriedOverPrompt: View {
    let task: TaskItem
    let weeks: Int
    let keep: () -> Void
    let later: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Icon.refresh.image(size: 14).foregroundStyle(Theme.muted)
            Text("\(Text(task.title).foregroundStyle(Theme.foreground)) has carried over \(weeks == 2 ? "twice" : "\(weeks) weeks"). Keep it this week?")
                .foregroundStyle(Theme.muted)
                .appText(.sm)
                .lineLimit(2)
            Spacer(minLength: 8)
            SmallButton(icon: .tick, title: "Keep", action: keep)
            SmallButton(icon: .dashedCircle, title: "Move to Later", action: later)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.wash.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}

// MARK: - A closed row

/// `group relative flex min-h-12 items-start gap-3 rounded-xl px-3 py-1.5 hover:bg-wash/50`
private struct TaskRow: View {
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
        HStack(spacing: 10) {
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

    private var planPill: TaskDayPill {
        TaskDayPill(kind: .plan, value: task.plannedFor, today: today, isQuiet: !isEngaged, owner: task.id) {
            actions.edit(task, TaskPatch(plannedFor: $0 ?? ""))
        }
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
                // Moving to a week drops its day; Later clears both.
                if horizon.group != .thisWeek {
                    MenuItem(icon: .calendarSmall, title: "Move to this week") { move(week: thisWeek) }
                }
                if horizon.group != .nextWeek {
                    MenuItem(icon: .arrowForward, title: "Move to next week") { move(week: nextWeek) }
                }
                if horizon.group != .later {
                    MenuItem(icon: .dashedCircle, title: "Move to Later") { move(week: "") }
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
        actions.place(task, TaskPatch(plannedFor: "", plannedWeek: week))
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
private struct OpenTaskRow: View {
    let task: TaskItem
    @Binding var draft: TasksSection.Draft
    let today: String
    var focus: FocusState<TasksSection.Field?>.Binding
    let actions: TaskActions
    let onClose: () -> Void

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
                    .focused(focus, equals: .title)
                    .accessibilityLabel("Task")
                    // Return moves on to the description, as on the web.
                    .onSubmit { focus.wrappedValue = .description }
                    .padding(.top, 6)
                TextField("", text: $draft.description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1...12)
                    .focused(focus, equals: .description)
                    .placeholder("Add a description…", when: draft.description.isEmpty, font: .app(14))
                    .accessibilityLabel("Description")
                HStack(spacing: 8) {
                    EstimatePill(minutes: task.minutes) { actions.edit(task, TaskPatch(minutes: $0)) }
                    TaskDayPill(kind: .plan, value: task.plannedFor, today: today) {
                        actions.edit(task, TaskPatch(plannedFor: $0 ?? ""))
                    }
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
        .onExitCommand(perform: onClose)
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onClose()
            return .handled
        }
    }
}

// MARK: - Pieces

/// The round checkbox: `h-[18px] w-[18px] rounded-full border-[1.5px] border-foreground/30`,
/// a faint tick on hover.
private struct Checkbox: View {
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

// MARK: - Suggestions

/// "Suggested from your latest read": candidates to add as tasks or pass on, or a way to ask for new ones.
private struct SuggestionsList: View {
    let suggestions: [TaskSuggestion]
    let reading: Bool
    let actions: TaskActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Suggested").appText(.sm, .medium).foregroundStyle(Theme.foreground)
                Text("from your latest read").appText(.sm).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)

            if suggestions.isEmpty {
                HStack(spacing: 12) {
                    Text(reading ? "Looking for what’s next…" : "Nothing suggested right now.")
                        .appText(.sm).foregroundStyle(Theme.muted)
                    Spacer()
                    RefreshSuggestionsButton(reading: reading, action: actions.refresh)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(suggestions, id: \.title) { suggestion in
                        SuggestedRow(suggestion: suggestion, disabled: reading, actions: actions)
                    }
                }
                .compositingGroup()
                .opacity(reading ? 0.5 : 1)
            }
        }
    }
}

/// A suggestion: laid out like a task, but dashed and without a checkbox, since it isn't yours yet.
private struct SuggestedRow: View {
    let suggestion: TaskSuggestion
    let disabled: Bool
    let actions: TaskActions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon.dashedCircle.image(size: 21).foregroundStyle(Theme.muted.opacity(0.7))
                .frame(width: 18, height: 21)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title).font(.app(15.2)).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if !suggestion.why.isEmpty {
                    Text(suggestion.why).appText(.sm).foregroundStyle(Theme.muted).lineLimit(2)
                }
                TaskPill(icon: .clock, text: TaskItem.minutesLabel(suggestion.minutes)).padding(.top, 4)
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                SmallButton(icon: .add, title: "Add", isDisabled: disabled) { actions.acceptSuggestion(suggestion) }
                    .help("Add as task")
                IconOnlyButton(icon: .close, isDisabled: disabled) { actions.passOnSuggestion(suggestion) }
                    .help("Not now")
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

/// `h-7 rounded-lg border bg-card px-2 text-xs font-medium shadow`
private struct SmallButton: View {
    let icon: Icon
    let title: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                icon.image(size: 13)
                Text(title).appText(.xs, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .compositingGroup()
            .opacity(isDisabled ? 0.5 : 1)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(isDisabled)
        .onHover { isHovered = $0 }
    }
}

/// `h-7 w-7 rounded-lg text-muted hover:bg-wash hover:text-foreground`
private struct IconOnlyButton: View {
    let icon: Icon
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.image(size: 14)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 28, height: 28)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .compositingGroup()
                .opacity(isDisabled ? 0.5 : 1)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(isDisabled)
        .onHover { isHovered = $0 }
    }
}

/// "Get new suggestions": `h-8 rounded-lg border bg-card px-3 text-sm font-medium shadow`.
private struct RefreshSuggestionsButton: View {
    let reading: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if reading { SpinningIcon(size: 14) } else { Icon.refresh.image(size: 14) }
                Text(reading ? "Reading…" : "Get new suggestions").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .compositingGroup()
            .opacity(reading ? 0.5 : 1)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(reading)
        .onHover { isHovered = $0 }
    }
}

#Preview("Tasks") {
    TasksSection(
        tasks: Fixtures.tasks, suggestions: Fixtures.suggestions, hasRead: true, reading: false,
        clock: .twelveHour, today: "2026-11-18", now: Fixtures.referenceNow
    )
    .padding(.horizontal, 32)
    .frame(width: 832, height: 1320, alignment: .top)
    .background(Theme.background)
}
