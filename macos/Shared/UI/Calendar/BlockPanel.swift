import SwiftUI

/*
 * The block you clicked, beside the calendar on the right: a session (time to work on the goal),
 * reserved time (kept for its own sake: lunch, family, an event), or a task's time. Every kind reads
 * the same way: its goal, its title, a description, and rows for its goal, day, time and type, each
 * opening a menu to change it. A task's time is described by the task itself, and its time can be
 * cleared, leaving the task planned for the day.
 *
 * The description offers help with Tab while it's empty: a session that doesn't say what it's for
 * gets a suggested focus (Return takes it, Tab asks for another, Esc sets it aside); one that does
 * gets an agenda, with the tasks it draws on. Once a block has ended it can be recapped; then it
 * reads as a record: the description, the posted recap, and the agenda folded away.
 */

/// What the panel can do, each returning an error to show, or nil.
struct BlockPanelActions {
    var setReserved: (_ blockId: String, _ reserved: Bool) -> Void = { _, _ in }
    var setDescription: (_ blockId: String, _ text: String) async -> String?
    var prepareAgenda: (_ blockId: String, _ when: String) async -> String?
    var suggestFocus: (_ blockId: String, _ when: String, _ instead: [String]) async -> FocusOutcome
    var prepareRecap: (_ blockId: String) async -> String?
    var postRecap: (_ blockId: String, _ body: String, _ keep: [NoteItem.Breadcrumb], _ markTaskDone: Bool) async -> String?
    var discardRecap: (_ blockId: String) async -> String?
    var setTaskDone: (_ taskId: String, _ done: Bool) async -> String?
    var toggleDone: (_ blockId: String) -> Void
    var openGoal: (_ goalId: String) -> Void
    /// Answering a change to an imported block's event: take it, or keep the block as it is.
    var takeChange: (_ blockId: String, _ change: ImportChange) -> Void = { _, _ in }
    var keepBlock: (_ blockId: String, _ change: ImportChange) -> Void = { _, _ in }
}

struct BlockPanel: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    /// Goals it can move to.
    var goals: [CalendarGoal] = []
    /// Its own description, or its task's for a task's time.
    let description: String?
    /// Its day, in days from today, and its time on that day in minutes from midnight.
    let day: Int
    let start: Int
    let end: Int
    var clock: Clock = .twelveHour
    /// How the block reads in this time zone, for the agenda.
    let when: String
    /// Open tasks across goals; a related task that isn't open anymore shows as done.
    let openTaskIds: Set<String>
    /// Whether the session is over; it can then be recapped.
    let ended: Bool
    let now: Date
    let actions: BlockPanelActions?
    /// The calendar's own changes: rename, goal, day, time, type, and the ⋯ menu.
    var calendar: CalendarActions?
    /// For an imported block: how its event has changed since, to answer here.
    var importChange: ImportChange?
    var onClose: () -> Void = {}

    @State private var preparing = false
    @State private var agendaError: String?
    /// A focus suggested for a session that doesn't say what it's for, until it's taken or set aside.
    @State private var suggestion: FocusSuggestion?
    @State private var suggesting = false
    /// Aims suggested here and passed over, so the next suggestion differs.
    @State private var passed: [String] = []
    @State private var moreAnchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    init(block: CalendarBlock, goal: CalendarGoal?, goals: [CalendarGoal] = [], description: String?, day: Int, start: Int, end: Int,
         clock: Clock = .twelveHour, when: String, openTaskIds: Set<String>, ended: Bool, now: Date,
         actions: BlockPanelActions?, calendar: CalendarActions? = nil, suggestion: FocusSuggestion? = nil,
         importChange: ImportChange? = nil, onClose: @escaping () -> Void = {}) {
        self.block = block
        self.goal = goal
        self.goals = goals
        self.description = description
        self.day = day
        self.start = start
        self.end = end
        self.clock = clock
        self.when = when
        self.openTaskIds = openTaskIds
        self.ended = ended
        self.now = now
        self.actions = actions
        self.calendar = calendar
        self.importChange = importChange
        self.onClose = onClose
        _suggestion = State(initialValue: suggestion)
    }

    private var recapped: Bool { block.recapPost != nil }
    private var hasDescription: Bool { !(description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Nothing says yet what the session is for, so the useful help is picking a focus, not planning one.
    private var needsFocus: Bool { !block.isIntention && block.title == nil && !hasDescription }
    /// A task that's done (or gone) isn't open to describe here anymore.
    private var describable: Bool { !recapped && (block.taskId.map(openTaskIds.contains) ?? true) }

    /// What Tab does in an empty description: suggest a focus, plan the session, or nothing.
    private var tab: DescriptionField.Tab {
        guard actions != nil, !ended, block.isSession, !block.isPending, block.agenda == nil, !preparing else { return .none }
        return needsFocus ? .suggest : .plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if let goal {
                        GoalBadge(icon: goal.icon, color: goal.color, size: .field).help(goal.title)
                    }
                    Spacer(minLength: 0)
                    if calendar != nil, !block.isPending {
                        PanelIconButton(icon: .more, label: "More", action: showMore)
                            .modifier(AnchorReader(frame: $moreAnchor))
                    }
                    PanelIconButton(icon: .close, label: "Close", action: onClose)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if block.taskId != nil {
                        DoneCircle(done: block.taskDone, color: goal?.color ?? "slate") { actions?.toggleDone(block.id) }
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                    TitleField(block: block, placeholder: goal?.title ?? "Add a title", isEditable: calendar != nil && !block.isPending) { title in
                        calendar?.saveDetails(block.id, block.goalId, title)
                    }
                }
                .padding(.top, 16)

                DescriptionField(
                    blockId: block.id,
                    text: description,
                    isEditable: describable && actions != nil && !block.isPending,
                    tab: tab,
                    suggesting: suggesting,
                    suggestion: suggestion,
                    onSave: { text in await actions?.setDescription(block.id, text) },
                    onTab: { tab == .suggest ? suggest() : prepare() },
                    onTakeSuggestion: adopt,
                    onDropSuggestion: dropSuggestion
                )
                .padding(.top, 4)

                // Once it says what it's for, planning is a quiet link: Tab only offers it while empty.
                if tab == .plan, hasDescription {
                    QuietButton(icon: .checklist, title: "Plan session", action: prepare)
                        .help("A short plan for getting what this session is for, from the goal’s tasks, notes and latest read")
                        .padding(.top, 4)
                }

                if let agendaError {
                    Text(agendaError).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 8)
                }

                // Its event changed since: what happened, and the two answers.
                if let importChange, let source = block.source {
                    ChangeNotice(
                        copy: ImportChangeCopy(importChange, block: block, source: source, clock: clock, now: now),
                        isEnabled: actions != nil && !block.isPending,
                        onTake: { actions?.takeChange(block.id, importChange) },
                        onKeep: { actions?.keepBlock(block.id, importChange) }
                    )
                    .padding(.top, 12)
                }

                PropertyRows(
                    block: block, goal: goal, goals: goals, day: day, start: start, end: end, clock: clock, now: now,
                    calendar: block.isPending ? nil : calendar,
                    sourceChanged: importChange != nil
                )
                .padding(.top, 16)

                // Reserved time has no recap to write; one posted while it was a session still shows.
                if ended, block.isSession || recapped {
                    RecapSection(block: block, actions: actions).padding(.top, 24)
                }

                if block.isSession {
                    AgendaSection(
                        block: block, color: goal?.color ?? "slate", ended: ended, now: now, openTaskIds: openTaskIds,
                        preparing: preparing, actions: actions, onPrepare: prepare
                    )
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
        .accessibilityLabel("\(block.kindLabel): \(block.title ?? goal?.title ?? "Protected time")")
    }

    private func showMore() {
        guard let calendar, let overlays else { return }
        overlays.showMenu(anchor: moreAnchor, owner: block.id) {
            BlockMenu(block: block, day: day, actions: calendar)
        }
    }

    private func prepare() {
        guard let actions, !preparing else { return }
        agendaError = nil
        preparing = true
        let blockId = block.id
        Task {
            agendaError = await actions.prepareAgenda(blockId, when)
            preparing = false
        }
    }

    private func suggest() {
        guard let actions, !suggesting else { return }
        agendaError = nil
        if let suggestion { passed.append(suggestion.aim) }
        suggesting = true
        let blockId = block.id, instead = passed
        Task {
            switch await actions.suggestFocus(blockId, when, instead) {
            case .suggested(let next): suggestion = next
            case .failed(let message): agendaError = message
            }
            suggesting = false
        }
    }

    private func dropSuggestion() {
        if let suggestion { passed.append(suggestion.aim) }
        suggestion = nil
    }

    /// Takes the suggestion as the description; from there Tab, or the link, plans the session.
    private func adopt() {
        guard let actions, let taken = suggestion else { return }
        suggestion = nil
        let blockId = block.id
        Task {
            if let message = await actions.setDescription(blockId, taken.aim) {
                agendaError = message
                suggestion = taken
            } else {
                passed = []
            }
        }
    }
}

// MARK: - Title

/// The block's name, edited in place and saved when the field lets go. An untitled block shows its
/// goal's title, faded; a task's time keeps its task's title when emptied.
private struct TitleField: View {
    let block: CalendarBlock
    let placeholder: String
    let isEditable: Bool
    let onSave: (String?) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    /// MAX_BLOCK_TITLE
    private static let maxTitle = 120

    init(block: CalendarBlock, placeholder: String, isEditable: Bool, onSave: @escaping (String?) -> Void) {
        self.block = block
        self.placeholder = placeholder
        self.isEditable = isEditable
        self.onSave = onSave
        _draft = State(initialValue: block.title ?? "")
    }

    var body: some View {
        TextField("", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.app(17, .semibold))
            .tracking(-0.17)
            .foregroundStyle(Theme.foreground)
            .focused($isFocused)
            .disabled(!isEditable)
            .placeholder(placeholder, when: draft.isEmpty, font: .app(17, .semibold))
            .onKeyPress(.return, phases: .down) { _ in
                isFocused = false
                return .handled
            }
            .onExitCommand {
                draft = block.title ?? ""
                isFocused = false
            }
            .onChange(of: draft) { if draft.count > Self.maxTitle { draft = String(draft.prefix(Self.maxTitle)) } }
            .onChange(of: isFocused) { if !isFocused { save() } }
            .onChange(of: block.title) { if !isFocused { draft = block.title ?? "" } }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEditable && (isHovered || isFocused) ? Theme.wash.opacity(0.6) : .clear, in: .rect(cornerRadius: 8))
            .onHover { isHovered = $0 }
            .padding(.horizontal, -6)
            .accessibilityLabel("Title")
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A task's time is named by its task: emptied, it keeps the name.
        if trimmed.isEmpty, block.isIntention {
            draft = block.title ?? ""
            return
        }
        guard trimmed != (block.title ?? "") else { return }
        onSave(trimmed.isEmpty ? nil : trimmed)
    }
}

/// A task's circle before its title: tick it off, or reopen it.
private struct DoneCircle: View {
    let done: Bool
    let color: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if done {
                    Icon.tickHeavy.image(size: 11).foregroundStyle(Theme.background)
                        .frame(width: 18, height: 18).background(Theme.foreground, in: .circle)
                } else {
                    Icon.circle.image(size: 18).foregroundStyle(GoalPalette.color(color)).frame(width: 18, height: 18)
                }
            }
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(done ? "Reopen task" : "Mark done")
        .accessibilityLabel(done ? "Reopen task" : "Mark done")
    }
}

// MARK: - Description

/// What the block is about, in the person's words. Saved when the field lets go. While it's empty,
/// Tab suggests a focus or plans the session; a suggestion shows in the field until it's taken
/// (Return), swapped for another (Tab) or set aside (Esc, or typing).
private struct DescriptionField: View {
    enum Tab { case none, suggest, plan }

    let blockId: String
    let text: String?
    let isEditable: Bool
    let tab: Tab
    let suggesting: Bool
    let suggestion: FocusSuggestion?
    let onSave: (String) async -> String?
    let onTab: () -> Void
    let onTakeSuggestion: () -> Void
    let onDropSuggestion: () -> Void

    @State private var draft: String
    @State private var error: String?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    /// MAX_BLOCK_DESCRIPTION, and a task's is longer, but a block's is what can be read here.
    private static let maxLength = 1000

    init(blockId: String, text: String?, isEditable: Bool, tab: Tab, suggesting: Bool, suggestion: FocusSuggestion?,
         onSave: @escaping (String) async -> String?, onTab: @escaping () -> Void,
         onTakeSuggestion: @escaping () -> Void, onDropSuggestion: @escaping () -> Void) {
        self.blockId = blockId
        self.text = text
        self.isEditable = isEditable
        self.tab = tab
        self.suggesting = suggesting
        self.suggestion = suggestion
        self.onSave = onSave
        self.onTab = onTab
        self.onTakeSuggestion = onTakeSuggestion
        self.onDropSuggestion = onDropSuggestion
        _draft = State(initialValue: text ?? "")
    }

    private var placeholder: String {
        if suggesting { return "Suggesting a focus…" }
        switch tab {
        case .none: return "Add a description"
        case .suggest: return "Add a description or Tab to suggest a focus…"
        case .plan: return "Add a description or Tab to plan session…"
        }
    }

    /// A suggestion stands in the empty field.
    private var shown: FocusSuggestion? { draft.isEmpty ? suggestion : nil }

    var body: some View {
        if !isEditable {
            if let text, !text.isEmpty {
                Text(text).appText(.sm).lineSpacing(4).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    // A suggestion stands in the field at its full length, wrapping as the text would.
                    if let shown {
                        Text(shown.aim).font(.app(14)).lineSpacing(4).foregroundStyle(Theme.foreground(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(14))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.foreground(0.9))
                        .focused($isFocused)
                        .placeholder(placeholder, when: draft.isEmpty && shown == nil, font: .app(14))
                }
                    .onKeyPress(.tab, phases: .down) { _ in
                        guard draft.isEmpty, tab == .suggest || (tab == .plan && suggestion == nil), !suggesting else { return .ignored }
                        onTab()
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        if shown != nil {
                            onTakeSuggestion()
                            return .handled
                        }
                        guard press.modifiers.contains(.command) else { return .ignored }
                        isFocused = false
                        return .handled
                    }
                    .onExitCommand {
                        if shown != nil {
                            onDropSuggestion()
                            return
                        }
                        draft = text ?? ""
                        isFocused = false
                    }
                    .onChange(of: draft) {
                        if draft.count > Self.maxLength { draft = String(draft.prefix(Self.maxLength)) }
                        // Writing your own sets the suggestion aside.
                        if !draft.isEmpty, suggestion != nil { onDropSuggestion() }
                    }
                    .onChange(of: isFocused) { if !isFocused { save() } }
                    // Set from outside the field too, like taking a suggested focus.
                    .onChange(of: text) { if !isFocused || shown == nil { draft = text ?? "" } }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(isHovered || isFocused ? Theme.wash.opacity(0.6) : .clear, in: .rect(cornerRadius: 8))
                    .onHover { isHovered = $0 }
                    .padding(.horizontal, -6)
                    .accessibilityLabel("Description")

                if let shown {
                    VStack(alignment: .leading, spacing: 4) {
                        if !shown.why.isEmpty {
                            Text(shown.why).appText(.xs).lineSpacing(3).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Return to use it · Tab for another · Esc to set it aside")
                            .appText(.xs, .medium).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Suggested focus: \(shown.aim). \(shown.why)")
                }

                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 4)
                }
            }
        }
    }

    private func save() {
        error = nil
        let value = draft
        Task { error = await onSave(value) }
    }
}

// MARK: - Rows

/// The block's goal, day, time and type, one row each, each opening a menu to change it.
private struct PropertyRows: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let goals: [CalendarGoal]
    let day: Int
    let start: Int
    let end: Int
    let clock: Clock
    let now: Date
    let calendar: CalendarActions?
    /// An imported block's event has changed since: its source row says so.
    var sourceChanged = false

    @Environment(\.overlays) private var overlays

    private var today: String { CalendarDay.today(now) }
    private var dayISO: String { CalendarDay.addDays(today, day) }
    private var untitled: Bool { (block.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Imported: where it came from, first.
            if let source = block.source {
                SourceRow(calendar: source.calendar, changed: sourceChanged)
            }

            PropertyRow(title: goal?.title ?? "No goal", accessibility: "Goal", isEnabled: calendar != nil && goals.count > 1) {
                if let goal { GoalIconImage(name: goal.icon, size: 16) } else { Icon.target.image(size: 16) }
            } menu: {
                GoalMenu(goals: goals, selected: block.goalId) { calendar?.saveDetails(block.id, $0, block.title) }
            }

            PropertyRow(title: dayLabel, accessibility: "Day", isEnabled: calendar != nil) {
                Icon.calendarSmall.image(size: 16)
            } menu: {
                DayMenu(kind: .blockDay, value: dayISO, today: today) { picked in
                    guard let picked else { return }
                    let days = CalendarDay.daysUntil(picked, today: dayISO)
                    if days != 0 { calendar?.move(block.id, .move, 0, days) }
                }
            }

            PropertyRow(title: clock.formatRange(start, end), detail: durationLabel(Double(end - start)), accessibility: "Time", isEnabled: calendar != nil) {
                Icon.clock.image(size: 16)
            } menu: {
                TimeMenu(
                    start: start, end: end, clock: clock,
                    // Only a task's time that hasn't started can go back to being planned for the day.
                    canClear: block.taskId != nil && block.startsAt > now,
                    onStart: { calendar?.move(block.id, .move, $0 - start, 0) },
                    onEnd: { calendar?.move(block.id, .end, $0 - end, 0) },
                    onClear: { if let taskId = block.taskId { calendar?.plan(taskId, day) } }
                )
            }

            PropertyRow(title: block.kind.longLabel + (block.taskDone ? " · Done" : ""), accessibility: "Type", isEnabled: calendar != nil) {
                block.kind.icon.image(size: 16)
            } menu: {
                MenuPanel(width: 208) {
                    MenuLabel("Type")
                    ForEach(BlockKind.allCases, id: \.self) { kind in
                        MenuItem(
                            icon: kind.icon, title: kind.longLabel,
                            // A task is made from the block's title.
                            isDisabled: kind == .task && block.kind != .task && untitled,
                            isChecked: kind == block.kind
                        ) {
                            overlays?.dismiss()
                            calendar?.setKind(block.id, kind)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, -8)
    }

    /// "Today", "Tomorrow", or "Wednesday, Nov 18".
    private var dayLabel: String {
        switch day {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default:
            CalendarDayMath.midnight(day, from: now)
                .formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(Locale(identifier: "en_US")))
        }
    }
}

/// A change to an imported block's event: a heading, where it was seen, the values side by side,
/// and two answers. Either answer settles it until the event changes again.
private struct ChangeNotice: View {
    let copy: ImportChangeCopy
    let isEnabled: Bool
    let onTake: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                (copy.takeRemoves ? Icon.calendarRemoved : Icon.refresh).image(size: 14)
                Text(copy.heading).appText(.px(13), .semibold)
            }
            .foregroundStyle(Theme.foreground)
            Text(copy.source).appText(.xs).foregroundStyle(Theme.muted).padding(.top, 2)

            if !copy.lines.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(Array(copy.lines.enumerated()), id: \.offset) { _, line in
                        GridRow {
                            Text(line.label).appText(.xs).foregroundStyle(Theme.muted)
                            Text(line.value)
                                .appText(.px(13), line.isNew ? .medium : .regular)
                                .monospacedDigit()
                                .strikethrough(line.was, color: Theme.muted)
                                .foregroundStyle(line.was ? Theme.muted : Theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 10)
            }
            if let body = copy.body {
                Text(body).appText(.px(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            HStack(spacing: 6) {
                if copy.keepFirst {
                    AnswerButton(title: copy.keep, style: .primary, action: onKeep)
                    AnswerButton(title: copy.take, style: copy.takeRemoves ? .destructive : .secondary, action: onTake)
                } else {
                    AnswerButton(title: copy.take, style: copy.takeRemoves ? .destructive : .primary, action: onTake)
                    AnswerButton(title: copy.keep, style: .secondary, action: onKeep)
                }
            }
            .padding(.top, 12)
            .inactive(!isEnabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

/// The answers to a change: `h-7 rounded-lg px-3 text-xs`, filled, ringed, or ringed in red.
struct AnswerButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let style: Style
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.xs, style == .primary ? .semibold : .medium)
                .foregroundStyle(style == .primary ? Theme.background : style == .destructive ? Theme.danger : Theme.foreground)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(style == .primary ? Theme.foreground : Theme.card, in: .rect(cornerRadius: 8))
                .overlay {
                    if style != .primary { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.lineStrong) }
                }
                .opacity(isHovered ? 0.85 : 1)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// An imported block's row for where it came from: the events button's icon and "From General ·
/// Google", in the property rows' shape, with nothing to open. Changed once its event has.
private struct SourceRow: View {
    let calendar: String
    let changed: Bool

    var body: some View {
        HStack(spacing: 12) {
            Icon.calendarImport.image(size: 16).foregroundStyle(Theme.muted).frame(width: 18, height: 18)
            Text("From \(calendar) · Google").appText(.sm).foregroundStyle(Theme.foreground).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if changed {
                HStack(spacing: 4) {
                    Circle().fill(Theme.foreground).frame(width: 6, height: 6)
                    Text("Changed").appText(.xs, .medium).foregroundStyle(Theme.foreground)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(changed ? "Imported from \(calendar), changed since" : "Imported from \(calendar)")
    }
}

/// `h-9 rounded-lg px-2`: an icon, a value, an optional detail on the right, and a chevron, opening
/// `menu` below it.
private struct PropertyRow<Leading: View, Menu: View>: View {
    let title: String
    var detail: String?
    let accessibility: String
    let isEnabled: Bool
    @ViewBuilder let icon: () -> Leading
    @ViewBuilder let menu: () -> Menu

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero
    @State private var isHovered = false

    init(title: String, detail: String? = nil, accessibility: String, isEnabled: Bool,
         @ViewBuilder icon: @escaping () -> Leading, @ViewBuilder menu: @escaping () -> Menu) {
        self.title = title
        self.detail = detail
        self.accessibility = accessibility
        self.isEnabled = isEnabled
        self.icon = icon
        self.menu = menu
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                icon().foregroundStyle(Theme.muted).frame(width: 18, height: 18)
                Text(title).appText(.sm).foregroundStyle(Theme.foreground).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
                if isEnabled {
                    Icon.chevronDown.image(size: 14).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(isEnabled && isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .inactive(!isEnabled)
        .modifier(AnchorReader(frame: $anchor))
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(accessibility): \(title)")
    }

    private func open() {
        guard isEnabled, let overlays else { return }
        overlays.showMenu(anchor: anchor, alignLeading: true) { menu() }
    }
}

/// The goals a block can be moved to.
private struct GoalMenu: View {
    let goals: [CalendarGoal]
    let selected: String
    let onPick: (String) -> Void

    @Environment(\.overlays) private var overlays

    var body: some View {
        MenuPanel(width: 264) {
            MenuLabel("Goal")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(goals) { goal in
                        GoalMenuRow(goal: goal, isSelected: goal.id == selected) {
                            overlays?.dismiss()
                            if goal.id != selected { onPick(goal.id) }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 288)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GoalMenuRow: View {
    let goal: CalendarGoal
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                Text(goal.title).appText(.sm, .medium).foregroundStyle(Theme.foreground).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Icon.tick.image(size: 16).foregroundStyle(Theme.foreground)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A block's start and end, in quarter hours side by side, and, for a task's time, Clear time.
/// A new start keeps the block's length; a new end changes it.
private struct TimeMenu: View {
    let start: Int
    let end: Int
    let clock: Clock
    let canClear: Bool
    let onStart: (Int) -> Void
    let onEnd: (Int) -> Void
    let onClear: () -> Void

    @Environment(\.overlays) private var overlays

    private static let step = CalendarDayMath.step

    var body: some View {
        let length = end - start
        MenuPanel(width: 264) {
            HStack(alignment: .top, spacing: 4) {
                column("Start", Array(stride(from: 0, through: CalendarDayMath.dayMinutes - length, by: Self.step)), selected: start, onPick: onStart)
                column("End", Array(stride(from: start + Self.step, through: CalendarDayMath.dayMinutes, by: Self.step)), selected: end, onPick: onEnd)
            }
            if canClear {
                MenuSeparator()
                DayRow(title: "Clear time", isDestructive: true) {
                    overlays?.dismiss()
                    onClear()
                }
                .help("Keep the task planned for the day, without a time")
            }
        }
    }

    private func column(_ title: String, _ options: [Int], selected: Int, onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuLabel(title)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(options, id: \.self) { minutes in
                            DayRow(title: clock.format(minutes: minutes), isSelected: minutes == selected) {
                                overlays?.dismiss()
                                if minutes != selected { onPick(minutes) }
                            }
                            .id(minutes)
                        }
                    }
                }
                .frame(height: 216)
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Agenda

/// A session's plan, once there is one (or while it's being made), with the tasks it draws on.
private struct AgendaSection: View {
    let block: CalendarBlock
    /// The goal's colour, for the related tasks' circles.
    let color: String
    /// Once the session is over, an agenda is only kept for reference.
    let ended: Bool
    let now: Date
    let openTaskIds: Set<String>
    let preparing: Bool
    let actions: BlockPanelActions?
    let onPrepare: () -> Void

    @State private var error: String?
    /// Tasks checked off or reopened here, until the calendar catches up.
    @State private var toggled: [String: Bool] = [:]
    /// Once the session is over, the agenda is history: folded away until asked for.
    @State private var expanded = false

    var body: some View {
        let agenda = block.agenda
        let showsBody = !ended || expanded
        let stale = agenda.map { !ended && !preparing && $0.isStale(title: block.title, description: block.description) } ?? false

        if agenda != nil || (preparing && !ended) {
            VStack(alignment: .leading, spacing: 0) {
                if let agenda {
                    if ended {
                        Button { expanded.toggle() } label: {
                            HStack(spacing: 4) {
                                Text("Agenda").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                                Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Agenda").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                            if !preparing {
                                Text(Self.preparedLabel(agenda.preparedAt, now: now)).appText(.xs).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                } else {
                    Text("Agenda").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                }

                if preparing, agenda == nil {
                    Skeleton(widths: [1, 0.92, 1, 0.6]).padding(.top, 8)
                } else if let agenda, showsBody {
                    Text(agenda.text).appText(.sm).lineSpacing(4).foregroundStyle(Theme.foreground(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(preparing ? 0.5 : 1)
                        .padding(.top, 6)
                }

                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.vertical, 8)
                }

                if stale {
                    Text("You’ve changed what this session is for since this was prepared.")
                        .appText(.xs).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                if !ended, agenda != nil {
                    QuietButton(title: preparing ? "Preparing…" : stale ? "Update agenda" : "Plan again", spinning: preparing, action: onPrepare)
                        .inactive(preparing)
                        .padding(.top, 12)
                }
            }
            .padding(.top, 24)

            if let agenda, showsBody, !agenda.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Related tasks").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(agenda.tasks) { task in
                            RelatedTask(
                                task: task,
                                color: color,
                                done: toggled[task.id] ?? !openTaskIds.contains(task.id),
                                onToggle: { toggle(task.id, $0) }
                            )
                        }
                    }
                    .padding(.horizontal, -8)
                    .padding(.top, 6)
                }
                .padding(.top, 24)
            }
        }
    }

    private func toggle(_ taskId: String, _ done: Bool) {
        guard let actions else { return }
        toggled[taskId] = done
        Task {
            if let message = await actions.setTaskDone(taskId, done) {
                error = message
                toggled[taskId] = nil
            }
        }
    }

    /// "Prepared just now", "Prepared 5 min ago", "Prepared 3 hr ago", or the date.
    static func preparedLabel(_ date: Date, now: Date) -> String {
        let minutes = Int((now.timeIntervalSince(date) / 60).rounded())
        if minutes < 1 { return "Prepared just now" }
        if minutes < 60 { return "Prepared \(minutes) min ago" }
        if minutes < 24 * 60 { return "Prepared \(Int((Double(minutes) / 60).rounded())) hr ago" }
        return "Prepared \(date.webMonthDay)"
    }
}

/// A task the agenda draws on, with a circle to check it off or reopen it.
private struct RelatedTask: View {
    let task: BlockAgenda.Task
    let color: String
    let done: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { onToggle(!done) } label: {
                Group {
                    if done {
                        Icon.tickHeavy.image(size: 10).foregroundStyle(Theme.background)
                            .frame(width: 16, height: 16).background(Theme.foreground, in: .circle)
                    } else {
                        Icon.circle.image(size: 15).foregroundStyle(GoalPalette.color(color)).frame(width: 16, height: 16)
                    }
                }
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel("\(done ? "Reopen" : "Check off") “\(task.title)”")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.app(13, .medium))
                    .strikethrough(done, color: Theme.foreground(0.25))
                    .foregroundStyle(done ? Theme.muted : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TaskItem.minutesLabel(task.minutes)).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

// MARK: - Recap

/// "Recap session" once a block has ended: a draft of what happened from the goal's connected apps,
/// edited and posted to the goal's activity. Once posted, the recap itself shows here.
private struct RecapSection: View {
    let block: CalendarBlock
    let actions: BlockPanelActions?

    @State private var preparing = false
    @State private var error: String?

    var body: some View {
        if let posted = block.recapPost {
            PostedRecapView(recap: posted) { actions?.openGoal(block.goalId) }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if (preparing || block.recapDrafting), block.recap == nil {
                    Text(preparing ? "Looking through your connected apps…" : "Drafting a recap from your connected apps…")
                        .font(.app(13)).foregroundStyle(Theme.muted)
                    Skeleton(widths: [1, 0.9, 1, 0.66]).padding(.top, 6)
                } else if let recap = block.recap {
                    RecapDraftView(block: block, recap: recap, preparing: preparing, actions: actions, onRedraft: prepare)
                        .id(recap.preparedAt)
                } else {
                    FullPrimaryButton(title: "Recap session", action: prepare)
                        .help("Draft what happened in this session from the goal’s connected apps")
                }
                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 8)
                }
            }
        }
    }

    private func prepare() {
        guard let actions, !preparing else { return }
        error = nil
        preparing = true
        let blockId = block.id
        Task {
            error = await actions.prepareRecap(blockId)
            preparing = false
        }
    }
}

private struct RecapDraftView: View {
    let block: CalendarBlock
    let recap: RecapDraft
    let preparing: Bool
    let actions: BlockPanelActions?
    let onRedraft: () -> Void

    @State private var text: String
    @State private var removed: Set<URL> = []
    @State private var markDone: Bool
    @State private var error: String?
    @State private var saving = false

    init(block: CalendarBlock, recap: RecapDraft, preparing: Bool, actions: BlockPanelActions?, onRedraft: @escaping () -> Void) {
        self.block = block
        self.recap = recap
        self.preparing = preparing
        self.actions = actions
        self.onRedraft = onRedraft
        _text = State(initialValue: recap.happened)
        _markDone = State(initialValue: recap.taskLooksDone)
    }

    private var kept: [NoteItem.Breadcrumb] { recap.breadcrumbs.filter { !removed.contains($0.url) } }
    private var canMarkDone: Bool { block.taskId != nil && !block.taskDone }
    private var busy: Bool { saving || preparing }
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var hint: String {
        if recap.auto {
            return "Drafted on its own once the session ended. Edit anything before posting; it’s cleared in a couple of days if you don’t."
        }
        switch recap.found {
        case .clear: return "Drafted from your connected apps. Edit anything before posting."
        case .partial: return "Drafted from what your connected apps show. Fill in the rest."
        case .none: return "Nothing in your connected apps from this session. Write what happened."
        case .noSources: return "This goal has no connected apps. Write what happened."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recap").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                Spacer()
                if recap.found != .noSources {
                    QuietButton(title: preparing ? "Drafting…" : "Draft again", spinning: preparing, action: onRedraft)
                        .inactive(busy)
                        .padding(.trailing, -8)
                }
            }
            Text(hint).appText(.xs).lineSpacing(3).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if let planned = recap.planned {
                Text("\(Text("Planned:").font(.app(13, .medium)).foregroundStyle(Theme.foreground(0.7))) \(planned)")
                    .font(.app(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(14))
                .lineSpacing(4)
                .foregroundStyle(Theme.foreground)
                .lineLimit(4...14)
                .placeholder("What happened in this session?", when: text.isEmpty, font: .app(14), color: Theme.muted.opacity(0.8))
                .onChange(of: text) {
                    error = nil
                    if text.count > 2000 { text = String(text.prefix(2000)) }
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command), !isEmpty else { return .ignored }
                    post()
                    return .handled
                }
                .frame(minHeight: 96, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.background.opacity(0.6), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
                .padding(.top, 8)
                .accessibilityLabel("What happened")

            if !kept.isEmpty {
                BreadcrumbList(items: kept) { removed.insert($0.url) }.padding(.top, 8)
            }

            if canMarkDone {
                Toggle(isOn: $markDone) {
                    Text("Also mark the task done").font(.app(13)).foregroundStyle(Theme.foreground)
                }
                .toggleStyle(.checkbox)
                .tint(Theme.foreground)
                .padding(.top, 12)
            }

            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 8)
            }

            HStack(spacing: 8) {
                SmallGhostButton(title: "Discard", action: discard)
                    .inactive(busy)
                FullPrimaryButton(title: saving ? "Posting…" : "Post to activity", isDisabled: busy || isEmpty, action: post)
            }
            .padding(.top, 16)
        }
        .opacity(preparing ? 0.5 : 1)
    }

    private func post() {
        guard let actions, !busy, !isEmpty else { return }
        error = nil
        saving = true
        let blockId = block.id, body = text, keep = kept, mark = canMarkDone && markDone
        Task {
            error = await actions.postRecap(blockId, body, keep, mark)
            saving = false
        }
    }

    private func discard() {
        guard let actions, !busy else { return }
        error = nil
        saving = true
        let blockId = block.id
        Task {
            error = await actions.discardRecap(blockId)
            saving = false
        }
    }
}

/// A posted recap: what happened, clamped until asked for in full, and the links it kept.
private struct PostedRecapView: View {
    let recap: PostedRecap
    let onOpenGoal: () -> Void

    @State private var expanded = false
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var linkHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recap").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                Spacer()
                Button(action: onOpenGoal) {
                    HStack(spacing: 2) {
                        Text("View in goal").appText(.xs, .medium)
                        Icon.arrowRight.image(size: 13)
                    }
                    .foregroundStyle(linkHovered ? Theme.foreground : Theme.muted)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { linkHovered = $0 }
            }
            if !recap.body.isEmpty {
                Text(recap.body).appText(.sm).lineSpacing(4).foregroundStyle(Theme.foreground(0.9))
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clampedHeight = $0 }
                    .background(alignment: .topLeading) {
                        // The full text, unseen, to tell whether the clamp hides anything.
                        Text(recap.body).appText(.sm).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                    }
                    .padding(.top, 6)
                if expanded || fullHeight > clampedHeight + 1 {
                    Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.app(12, .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
            }
            if !recap.breadcrumbs.isEmpty {
                BreadcrumbList(items: recap.breadcrumbs).padding(.top, 8)
            }
        }
    }
}

// MARK: - Pieces

/// Grey bars standing in for text that's on its way.
private struct Skeleton: View {
    let widths: [CGFloat]
    @State private var dim = false
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                    RoundedRectangle(cornerRadius: 4).fill(Theme.foreground(0.07))
                        .frame(width: geometry.size.width * width, height: 12)
                }
            }
        }
        .frame(height: CGFloat(widths.count) * 20 - 8)
        .opacity(dim ? 0.5 : 1)
        .animation(.easeInOut(duration: 1).repeatForever(), value: dim)
        .onAppear { if !staticRendering { dim = true } }
        .accessibilityLabel("Loading")
    }
}

/// `h-7 w-7 rounded-lg text-muted hover:bg-wash`, an icon at 15.
struct PanelIconButton: View {
    let icon: Icon
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.image(size: 15)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 28, height: 28)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// `h-9 w-full rounded-lg bg-foreground text-sm font-semibold text-background`.
private struct FullPrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, .semibold)
                .foregroundStyle(Theme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Theme.foreground, in: .rect(cornerRadius: 8))
                .compositingGroup()
                .opacity(isDisabled ? 0.3 : isHovered ? 0.9 : 1)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(isDisabled)
        .onHover { isHovered = $0 }
    }
}

/// `h-7 rounded-lg px-2 text-xs font-medium text-muted hover:bg-wash`, with an icon (refresh by default).
private struct QuietButton: View {
    var icon: Icon = .refresh
    let title: String
    var spinning = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if spinning { SpinningIcon(size: 13) } else { icon.image(size: 13) }
                Text(title).appText(.xs, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.leading, -8)
    }
}

#Preview("Block panels") {
    let data = Fixtures.calendar
    let now = Fixtures.referenceNow
    HStack(alignment: .top, spacing: 16) {
        ForEach(Fixtures.panelBlocks) { block in
            BlockPanel(
                block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                openTaskIds: ["t5"], ended: block.endsAt <= now, now: now, actions: nil
            )
            .frame(width: 320, height: 640)
        }
    }
    .padding(16)
    .background(Theme.background)
}

#Preview("Fresh block panels") {
    let data = Fixtures.calendar
    let now = Fixtures.referenceNow
    HStack(alignment: .top, spacing: 16) {
        ForEach(Fixtures.freshPanelBlocks) { block in
            BlockPanel(
                block: block, goal: data.goal(block.goalId), goals: data.goals, description: data.description(of: block),
                day: 0, start: 15 * 60, end: 16 * 60 + 30, when: "Wednesday, November 18 (today), 3:00–4:30 PM",
                openTaskIds: [], ended: block.endsAt <= now, now: now, actions: nil
            )
            .frame(width: 320, height: 360)
        }
    }
    .padding(16)
    .background(Theme.background)
}
