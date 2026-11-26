import SwiftUI

/// What the Tasks section asks of whoever owns the data.
struct TaskActions {
    /// A new task's title, and where it's planned (a day or week; an empty patch leaves it unplanned).
    var add: (String, TaskPatch) -> Void = { _, _ in }
    var toggle: (TaskItem) -> Void = { _ in }
    var edit: (TaskItem, TaskPatch) -> Void = { _, _ in }
    var delete: (TaskItem) -> Void = { _ in }
    /// The open tasks' ids in their new order.
    var reorder: ([String]) -> Void = { _ in }
    /// Moves a task to a day, a week or Unplanned (the patch's planned day and week, an empty string
    /// clearing), just before another task, or after them all when that's nil.
    var place: (TaskItem, TaskPatch, String?) -> Void = { _, _, _ in }
    /// Opens the planning board, when there is one.
    var plan: (() -> Void)?
    var acceptSuggestion: (TaskSuggestion) -> Void = { _ in }
    var passOnSuggestion: (TaskSuggestion) -> Void = { _ in }
    /// Runs a new read, which brings new suggestions.
    var refresh: () -> Void = {}
}

/// A goal's open tasks, grouped by how they're planned: for a day, for this week, for next week, or
/// Unplanned (captured, not committed to yet, and folded away). Click one to open it in place and add a
/// description; it saves when it closes (Esc, ⌘Return, a click elsewhere, or opening another).
/// Within a week or Unplanned, drag a row, or press ⌥↑ / ⌥↓ on it, to reorder: that order is what reads
/// and agendas follow. A row's plan pill gives it a day; its ⋯ menu moves it to another week or
/// Unplanned. Under the list, the latest read's suggestions to add or pass on.
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
    /// Opens with Unplanned unfolded, for snapshot tests.
    var initiallyShowsUnplanned = false
    /// For "Today 2:00 PM"; fixed in snapshots.
    var now = Date()
    var actions = TaskActions()

    @State private var draft: TaskDraft?
    @State private var newTitles: [TaskHorizon.Group: String] = [:]
    @State private var showsUnplanned = false
    @State private var drag: Drag?
    /// After a drop: how far the dropped row still is from its new slot, gliding to zero.
    @State private var settle: Settle?
    @State private var heights: [String: CGFloat] = [:]
    @FocusState private var focus: Field?

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
        case row(String), new(TaskHorizon.Group)
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

    /// Planned days follow their dates; weeks and Unplanned can be put in order.
    private func canReorder(_ rows: [TaskItem], in group: TaskHorizon.Group) -> Bool {
        group != .day && draft == nil && rows.count > 1 && !tasks.contains { $0.isPending }
    }

    var body: some View {
        let groups = self.groups
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tasks").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                    Text("What you’ve decided to do for this project, and when.").appText(.sm).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if let plan = actions.plan {
                    SmallButton(icon: .calendarSmall, title: "Plan tasks", action: plan)
                        .help("Plan this project’s tasks across days and weeks")
                }
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
            showsUnplanned = initiallyShowsUnplanned
            if let id = initiallyOpen, let task = tasks.first(where: { $0.id == id }) {
                draft = TaskDraft(task)
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
                keep: { actions.place(carried, TaskPatch(plannedFor: "", plannedWeek: thisWeek), nil) },
                later: { actions.place(carried, TaskPatch(plannedFor: "", plannedWeek: ""), nil) }
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        if !rows.isEmpty, group != .later || showsUnplanned {
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
                Text("Unplanned").appText(.xs, .medium).foregroundStyle(Theme.muted)
                if count > 0 {
                    Text("\(count)").appText(.xs).foregroundStyle(Theme.muted.opacity(0.7)).monospacedDigit()
                    Icon.chevronDown.image(size: 12).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(showsUnplanned ? 0 : -90))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, group == .day || (group == .thisWeek && groups[.day]?.isEmpty != false) ? 6 : 14)
        .padding(.bottom, 4)

        if group == .later, count > 0 {
            Button { withAnimation(.easeOut(duration: 0.15)) { showsUnplanned.toggle() } } label: { label.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(showsUnplanned ? "Fold away unplanned tasks" : "Show unplanned tasks")
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
                actions: actions,
                onClose: closeTask
            )
        } else {
            let reorderable = canReorder(rows, in: group)
            GoalTaskRow(
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
        default: "Add a task"
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
        let placement = switch group {
        case .thisWeek: TaskPatch(plannedWeek: thisWeek)
        case .nextWeek: TaskPatch(plannedWeek: nextWeek)
        default: TaskPatch()
        }
        actions.add(String(title.prefix(TaskItem.maxTitle)), placement)
        // So what was just added shows.
        if group == .later { showsUnplanned = true }
        // Enter adds it and keeps the cursor here for the next.
        focus = .new(group)
    }

    private func open(_ task: TaskItem) {
        guard !task.isPending else { return }
        if let draft, draft.id != task.id { commit(draft) }
        draft = TaskDraft(task)
    }

    private func closeTask() {
        guard let current = draft else { return }
        commit(current)
        draft = nil
    }

    /// Saves whatever changed in the open task.
    private func commit(_ draft: TaskDraft) {
        guard let task = tasks.first(where: { $0.id == draft.id }), let patch = draft.patch(for: task) else { return }
        actions.edit(task, patch)
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

/// "This has carried over twice": keep it for this week, or leave it unplanned.
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
            SmallButton(icon: .dashedCircle, title: "Unplan", action: later)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.wash.opacity(0.6), in: .rect(cornerRadius: 12))
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
        .contextPanel(isEnabled: !disabled) { SuggestionMenu(suggestion: suggestion, actions: actions) }
    }
}

/// Right-clicking a suggestion: the same two choices as its buttons.
private struct SuggestionMenu: View {
    let suggestion: TaskSuggestion
    let actions: TaskActions
    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel {
            MenuItem(icon: .add, title: "Add as task") {
                overlays?.dismiss()
                actions.acceptSuggestion(suggestion)
            }
            MenuItem(icon: .close, title: "Not now") {
                overlays?.dismiss()
                actions.passOnSuggestion(suggestion)
            }
        }
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
