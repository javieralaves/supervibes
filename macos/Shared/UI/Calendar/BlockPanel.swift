import SwiftUI

/*
 * The block you clicked, beside the calendar on the right, as block-panel.tsx and
 * recap-section.tsx. Protected time can say what the person wants out of it and get an agenda
 * steered by that, with the tasks it draws on below. An intention shows the task it schedules.
 * Once a block has ended it can be recapped; then it reads as a record: the aim, the posted recap,
 * and the agenda folded away.
 */

/// What the panel can do, each returning an error to show, or nil.
struct BlockPanelActions {
    var setDescription: (_ blockId: String, _ text: String) async -> String?
    var prepareAgenda: (_ blockId: String, _ when: String) async -> String?
    var prepareRecap: (_ blockId: String) async -> String?
    var postRecap: (_ blockId: String, _ body: String, _ keep: [NoteItem.Breadcrumb], _ markTaskDone: Bool) async -> String?
    var discardRecap: (_ blockId: String) async -> String?
    var setTaskDone: (_ taskId: String, _ done: Bool) async -> String?
    var toggleDone: (_ blockId: String) -> Void
    var openGoal: (_ goalId: String) -> Void
}

struct BlockPanel: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    /// Under the title, e.g. "Today · 9:00–11:00 AM".
    let timeLabel: String
    /// How the block reads in this time zone, for the agenda.
    let when: String
    /// Open tasks across goals; a related task that isn't open anymore shows as done.
    let openTaskIds: Set<String>
    /// Whether the session is over; it can then be recapped.
    let ended: Bool
    let now: Date
    let actions: BlockPanelActions?
    var onEdit: () -> Void = {}
    var onClose: () -> Void = {}

    private var title: String { block.title ?? goal?.title ?? "Protected time" }
    private var recapped: Bool { block.recapPost != nil }
    private var kind: String {
        (block.isIntention ? (block.taskDone ? "Done" : "Intention") : "Protected time") + (recapped ? " · Recapped" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if let goal {
                        GoalBadge(icon: goal.icon, color: goal.color, size: .xs).help(goal.title)
                    }
                    Text(kind).font(.app(13, .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PanelIconButton(icon: .edit, label: "Edit block", action: onEdit)
                    PanelIconButton(icon: .close, label: "Close", action: onClose)
                }

                Text(title).font(.app(17, .semibold)).tracking(-0.17).foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(timeLabel).appText(.sm).monospacedDigit().foregroundStyle(Theme.muted).padding(.top, 4)

                if !block.isIntention, !recapped || block.description != nil {
                    SessionAim(block: block, readOnly: recapped, actions: actions)
                        .padding(.top, 24)
                }

                if ended {
                    RecapSection(block: block, actions: actions).padding(.top, 24)
                }

                if block.isIntention {
                    if block.taskId != nil {
                        OutlineButton(icon: block.taskDone ? .refresh : .tick, title: block.taskDone ? "Reopen task" : "Mark done") {
                            actions?.toggleDone(block.id)
                        }
                        .padding(.top, 24)
                    }
                } else {
                    AgendaSection(block: block, color: goal?.color ?? "slate", when: when, ended: ended, now: now, openTaskIds: openTaskIds, actions: actions)
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
        .accessibilityLabel("\(kind): \(title)")
    }
}

// MARK: - Aim

/// What the person wants out of a session, in their own words. Saved when the field loses focus;
/// the agenda is steered by it and the recap judges the session against it.
private struct SessionAim: View {
    let block: CalendarBlock
    /// Once the session is recapped, it's kept for reference.
    let readOnly: Bool
    let actions: BlockPanelActions?

    @State private var draft: String
    @State private var error: String?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(block: CalendarBlock, readOnly: Bool, actions: BlockPanelActions?) {
        self.block = block
        self.readOnly = readOnly
        self.actions = actions
        _draft = State(initialValue: block.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Aim").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
            if readOnly {
                // The person's own words, set back a little so the recap below carries the weight.
                Text(block.description ?? "").appText(.sm).lineSpacing(4).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.foreground(0.1)).frame(width: 2) }
                    .padding(.top, 6)
            } else {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.app(14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.foreground(0.9))
                    .focused($isFocused)
                    .placeholder("What do you want out of this session?", when: draft.isEmpty, font: .app(14))
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        isFocused = false
                        return .handled
                    }
                    .onExitCommand {
                        draft = block.description ?? ""
                        isFocused = false
                    }
                    .onChange(of: draft) { if draft.count > 1000 { draft = String(draft.prefix(1000)) } }
                    .onChange(of: isFocused) { if !isFocused { save() } }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isHovered || isFocused ? Theme.wash.opacity(0.6) : .clear, in: .rect(cornerRadius: 8))
                    .onHover { isHovered = $0 }
                    .padding(.horizontal, -8)
                    .padding(.top, 4)
                    .help("Steers the agenda, and the recap checks the session against it")
                    .accessibilityLabel("What you want out of this session")
            }
            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 4)
            }
        }
    }

    private func save() {
        guard let actions else { return }
        error = nil
        let blockId = block.id
        let text = draft
        Task { error = await actions.setDescription(blockId, text) }
    }
}

// MARK: - Agenda

private struct AgendaSection: View {
    let block: CalendarBlock
    /// The goal's colour, for the related tasks' circles.
    let color: String
    let when: String
    /// Once the session is over, an agenda is only kept for reference.
    let ended: Bool
    let now: Date
    let openTaskIds: Set<String>
    let actions: BlockPanelActions?

    @State private var preparing = false
    @State private var error: String?
    /// Tasks checked off or reopened here, until the calendar catches up.
    @State private var toggled: [String: Bool] = [:]
    /// Once the session is over, the agenda is history: folded away until asked for.
    @State private var expanded = false

    var body: some View {
        let agenda = block.agenda
        let showsBody = !ended || expanded
        let stale = agenda.map { !ended && !preparing && $0.isStale(title: block.title, description: block.description) } ?? false

        if !(ended && agenda == nil) {
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
                }

                if preparing, agenda == nil {
                    Skeleton(widths: [1, 0.92, 1, 0.6])
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

                if !ended {
                    if agenda != nil {
                        QuietButton(title: preparing ? "Preparing…" : stale ? "Update agenda" : "Prepare again", spinning: preparing, action: prepare)
                            .inactive(preparing)
                            .padding(.top, 12)
                    } else {
                        FullPrimaryButton(title: preparing ? "Preparing…" : "Prepare agenda", isDisabled: preparing, action: prepare)
                            .padding(.top, preparing ? 16 : 0)
                            .help("A short plan for this session, from the goal’s tasks, notes and latest read")
                    }
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

    private func prepare() {
        guard let actions, !preparing else { return }
        error = nil
        preparing = true
        let blockId = block.id
        Task {
            error = await actions.prepareAgenda(blockId, when)
            preparing = false
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
private struct PanelIconButton: View {
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

/// `h-9 w-full rounded-lg border bg-card shadow`, an icon and a label.
private struct OutlineButton: View {
    let icon: Icon
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.image(size: 15)
                Text(title).appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// `h-7 rounded-lg px-2 text-xs font-medium text-muted hover:bg-wash`, with the refresh icon.
private struct QuietButton: View {
    let title: String
    var spinning = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if spinning { SpinningIcon(size: 13) } else { Icon.refresh.image(size: 13) }
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
                block: block, goal: data.goal(block.goalId), timeLabel: "Today · 3:00–4:30 PM",
                when: "Wednesday, November 18 (today), 3:00–4:30 PM", openTaskIds: ["t5"],
                ended: block.endsAt <= now, now: now, actions: nil
            )
            .frame(width: 320, height: 640)
        }
    }
    .padding(16)
    .background(Theme.background)
}
