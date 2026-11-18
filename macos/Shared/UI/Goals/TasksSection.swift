import SwiftUI

/// What the Tasks section asks of whoever owns the data.
struct TaskActions {
    var add: (String) -> Void = { _ in }
    var toggle: (TaskItem) -> Void = { _ in }
    var edit: (TaskItem, TaskPatch) -> Void = { _, _ in }
    var delete: (TaskItem) -> Void = { _ in }
    /// The open tasks' ids in their new order.
    var reorder: ([String]) -> Void = { _ in }
    var acceptSuggestion: (TaskSuggestion) -> Void = { _ in }
    var passOnSuggestion: (TaskSuggestion) -> Void = { _ in }
    /// Runs a new read, which brings new suggestions.
    var refresh: () -> Void = {}
}

/// A goal's open tasks, matching tasks-section.tsx. Click one to open it in place and add a
/// description; it saves when it closes (Esc, ⌘Return, a click elsewhere, or opening another).
/// Drag a row, or press ⌥↑ / ⌥↓ on it, to reorder: the order is the priority reads, agendas and
/// the calendar follow. Under the list, the latest read's suggestions to add or pass on.
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
    /// For "Today 2:00 PM"; fixed in snapshots.
    var now = Date()
    var actions = TaskActions()

    @State private var draft: Draft?
    @State private var newTitle = ""
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
        let from: Int
        var to: Int
        var dy: CGFloat
    }

    struct Settle: Equatable {
        let id: String
        var dy: CGFloat
    }

    enum Field: Hashable {
        case row(String), title, description, new
    }

    /// The space between rows (`gap-0.5`).
    private static let gap: CGFloat = 2

    private var canReorder: Bool {
        draft == nil && tasks.count > 1 && !tasks.contains { $0.isPending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tasks").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                Text("What you’ve decided to do for this goal.").appText(.sm).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                if !tasks.isEmpty {
                    VStack(spacing: Self.gap) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            row(task, index: index)
                        }
                    }
                }
                newTaskField
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
            if let id = initiallyOpen, let task = tasks.first(where: { $0.id == id }) {
                draft = Draft(id: task.id, title: task.title, description: task.description ?? "")
            }
        }
        .onChange(of: closeSignal) { closeTask() }
    }

    // MARK: Rows

    @ViewBuilder private func row(_ task: TaskItem, index: Int) -> some View {
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
            TaskRow(
                task: task,
                clock: clock,
                today: today,
                now: now,
                isDragging: drag?.id == task.id,
                isReorderable: canReorder,
                actions: actions,
                onOpen: { open(task) }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[task.id] = $0 }
            .offset(y: offset(for: task, at: index))
            .zIndex(drag?.id == task.id ? 1 : 0)
            // Rows the dragged one passes slide aside; the dragged one follows the pointer exactly.
            .animation(drag?.id == task.id ? nil : .easeOut(duration: 0.15), value: drag)
            // High priority, so a press on the title (a button) still becomes a drag once it moves
            // past a few points; a click without moving still opens the task.
            .highPriorityGesture(dragGesture(task, index: index), including: canReorder ? .all : .subviews)
            .focusable(canReorder && !task.isPending)
            .focusEffectDisabled()
            .focused($focus, equals: .row(task.id))
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                guard press.modifiers.contains(.option) else { return .ignored }
                move(task, by: press.key == .upArrow ? -1 : 1)
                return .handled
            }
        }
    }

    private var newTaskField: some View {
        HStack(spacing: 12) {
            Icon.add.image(size: 16).foregroundStyle(Theme.muted).frame(width: 18)
            TextField("", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.app(15.2))
                .foregroundStyle(Theme.foreground)
                .focused($focus, equals: .new)
                .placeholder("Add a task", when: newTitle.isEmpty, font: .app(15.2), color: Theme.muted.opacity(0.8))
                .accessibilityLabel("New task")
                .onSubmit(addTask)
                .onExitCommand { newTitle = "" }
            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("↵ to add").appText(.xs).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }

    // MARK: Editing

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newTitle = ""
        actions.add(String(title.prefix(TaskItem.maxTitle)))
        // Enter adds it and keeps the cursor here for the next.
        focus = .new
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
    /// passes slide aside to make room.
    private func offset(for task: TaskItem, at index: Int) -> CGFloat {
        if let settle, settle.id == task.id { return settle.dy }
        guard let drag else { return 0 }
        if task.id == drag.id { return drag.dy }
        let shift = (heights[drag.id] ?? 48) + Self.gap
        if drag.from < drag.to, index > drag.from, index <= drag.to { return -shift }
        if drag.to < drag.from, index >= drag.to, index < drag.from { return shift }
        return 0
    }

    private func dragGesture(_ task: TaskItem, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard canReorder || drag != nil else { return }
                let dy = value.translation.height
                // Its landing spot: past every other row whose middle it has crossed.
                var top: CGFloat = 0
                var tops: [CGFloat] = []
                for item in tasks {
                    tops.append(top)
                    top += (heights[item.id] ?? 48) + Self.gap
                }
                let center = tops[index] + (heights[task.id] ?? 48) / 2 + dy
                let to = tasks.indices.reduce(0) { count, i in
                    i != index && tops[i] + (heights[tasks[i].id] ?? 48) / 2 < center ? count + 1 : count
                }
                drag = Drag(id: task.id, from: index, to: to, dy: dy)
            }
            .onEnded { _ in
                guard let ended = drag else { return }
                // How far the new slot is from the old one: the rows it passed, and the gaps.
                let passed = ended.to > ended.from
                    ? Array(tasks[(ended.from + 1)...ended.to])
                    : ended.to < ended.from ? Array(tasks[ended.to..<ended.from]) : []
                let distance = passed.reduce(0) { $0 + (heights[$1.id] ?? 48) + Self.gap }
                let slot = ended.to > ended.from ? distance : -distance

                // In one step with no animation, the order changes and every row takes its new place,
                // with the dropped row held where the pointer left it. Then only that row glides the
                // last bit into its slot, so nothing moves twice.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    if ended.to != ended.from {
                        var ids = tasks.map(\.id)
                        ids.insert(ids.remove(at: ended.from), at: ended.to)
                        actions.reorder(ids)
                    }
                    drag = nil
                    settle = Settle(id: ended.id, dy: ended.dy - slot)
                }
                withAnimation(.easeOut(duration: 0.18)) { settle = nil }
            }
    }

    /// ⌥↑ / ⌥↓ on a task: one place up or down.
    private func move(_ task: TaskItem, by step: Int) {
        guard canReorder, let from = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let to = from + step
        guard tasks.indices.contains(to) else { return }
        var ids = tasks.map(\.id)
        ids.insert(ids.remove(at: from), at: to)
        withAnimation(.easeOut(duration: 0.18)) { actions.reorder(ids) }
        focus = .row(task.id)
    }
}

// MARK: - A closed row

/// `group relative flex min-h-12 items-start gap-3 rounded-xl px-3 py-1.5 hover:bg-wash/50`
private struct TaskRow: View {
    let task: TaskItem
    let clock: Clock
    let today: String
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
                MenuItem(icon: .delete, title: "Delete", isDestructive: true) {
                    overlays.dismiss()
                    actions.delete(task)
                }
            }
        }
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
