import SwiftUI

/// What the Activity section asks of whoever owns the data.
struct NoteActions {
    var post: (String) -> Void = { _ in }
    var edit: (NoteItem, String) -> Void = { _, _ in }
    var delete: (NoteItem) -> Void = { _ in }
    /// Reopens the task an entry records, which also takes the entry back out.
    var reopenTask: (NoteItem) -> Void = { _ in }
}

/// A goal's activity, matching notes-section.tsx: a composer for notes (context no connected app
/// can show), then notes, session recaps and finished tasks and suggestions, newest first.
struct NotesSection: View {
    let notes: [NoteItem]
    let author: NoteAuthor
    let clock: Clock
    var error: String?
    /// For "2 hr ago"; fixed in snapshots.
    var now = Date()
    var actions = NoteActions()

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Activity").appText(.lg, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                Text("Your notes and finished tasks. All of it feeds the progress read.")
                    .appText(.sm).foregroundStyle(Theme.muted)
            }
            .padding(.bottom, 16)

            Composer(draft: $draft, error: error, onPost: post)

            if !notes.isEmpty {
                VStack(spacing: 12) {
                    ForEach(notes) { note in
                        if note.completedTask != nil {
                            TaskDoneCard(note: note, author: author, now: now, actions: actions)
                        } else {
                            NoteCard(note: note, author: author, clock: clock, now: now, actions: actions)
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.top, 48)
    }

    private func post() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        actions.post(String(body.prefix(NoteItem.maxBody)))
    }
}

/// `rounded-2xl border bg-card px-5 py-3.5`, with "⌘↵ to post" and Post under the field.
private struct Composer: View {
    @Binding var draft: String
    let error: String?
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(15.2))
                .foregroundStyle(Theme.foreground)
                .lineLimit(2...16)
                .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                .placeholder(
                    "Add context, like a decision, offline work, or something to ignore…",
                    when: draft.isEmpty, font: .app(15.2), color: Theme.muted.opacity(0.8)
                )
                .accessibilityLabel("New note")
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    onPost()
                    return .handled
                }
                .frame(minHeight: 52, alignment: .topLeading)
            HStack {
                Text(error ?? (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "⌘↵ to post"))
                    .appText(.xs)
                    .foregroundStyle(error == nil ? Theme.muted : Theme.danger)
                Spacer()
                SmallPrimaryButton(title: "Post", isDisabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: onPost)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

// MARK: - Cards

/// Who and when, with the entry's ⋯ menu on the same row.
private struct Byline<Menu: View>: View {
    let author: NoteAuthor
    let detail: String
    @ViewBuilder var menu: Menu

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: author.name, imageURL: author.imageURL, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(author.name).appText(.sm, .semibold).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(detail).appText(.xs).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            menu
        }
    }
}

/// Posted automatically when a task is checked off: who, when, and the task itself.
private struct TaskDoneCard: View {
    let note: NoteItem
    let author: NoteAuthor
    let now: Date
    let actions: NoteActions

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Byline(author: author, detail: "Completed a task · \(note.createdAt.shortAgo(now: now))") {
                RoundIconButton(icon: .more, action: openMenu)
                    .modifier(AnchorReader(frame: $anchor))
                    .accessibilityLabel("Options for this entry")
            }
            CompletedTitle(text: note.completedTask ?? "").padding(.top, 12)
            if let description = note.taskDescription, !description.isEmpty {
                Text(description).appText(.sm).foregroundStyle(Theme.muted).lineLimit(3).padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private func openMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: anchor) {
            MenuPanel {
                if note.taskId != nil {
                    MenuItem(icon: .reopen, title: "Reopen task") {
                        overlays.dismiss()
                        actions.reopenTask(note)
                    }
                }
                MenuItem(icon: .delete, title: "Delete", isDestructive: true) {
                    overlays.showDialog {
                        ConfirmDialog(
                            title: "Delete this entry?",
                            message: "The task stays done. Only this entry is removed from your activity.",
                            confirmTitle: "Delete",
                            onCancel: { overlays.dismiss() },
                            onConfirm: {
                                overlays.dismiss()
                                actions.delete(note)
                            }
                        )
                    }
                }
            }
        }
    }
}

/// A note, a recap, or a finished suggestion; edited in place.
private struct NoteCard: View {
    let note: NoteItem
    let author: NoteAuthor
    let clock: Clock
    let now: Date
    let actions: NoteActions

    @Environment(\.overlays) private var overlays
    @State private var anchor = CGRect.zero
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    /// Posted from "Done" on a suggestion: shown like a completed task, with the note as its detail.
    private var isCompletion: Bool { note.completedSuggestion != nil }

    private var detail: String {
        if note.isPending { return "Posting…" }
        var parts: [String] = []
        if isCompletion { parts.append("Completed a suggestion") }
        if note.session != nil { parts.append("Recapped a session") }
        parts.append(note.createdAt.shortAgo(now: now))
        if note.isEdited { parts.append("edited") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Byline(author: author, detail: detail) {
                if !isEditing, !note.isPending {
                    RoundIconButton(icon: .more, action: openMenu)
                        .modifier(AnchorReader(frame: $anchor))
                        .accessibilityLabel("Note options")
                }
            }

            if let suggestion = note.completedSuggestion {
                CompletedTitle(text: suggestion).padding(.top, 12)
            }
            if let session = note.session {
                SessionLine(session: session, clock: clock).padding(.top, 12)
                if let aim = session.aim, !aim.isEmpty {
                    Text("\(Text("Aim:").fontWeight(.medium).foregroundStyle(Theme.foreground(0.7))) \(aim)")
                        .font(.app(13)).foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                }
            }

            if isEditing {
                editor.padding(.top, isCompletion ? 4 : note.session != nil ? 8 : 12)
            } else {
                Text(note.body)
                    .font(.app(isCompletion ? 14 : 15.2))
                    .lineSpacing(isCompletion ? 14 * 0.625 - 14 * 0.2 : 15.2 * 0.625 - 15.2 * 0.2)
                    .foregroundStyle(isCompletion ? Theme.muted : Theme.foreground)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, isCompletion ? 4 : note.session != nil ? 8 : 12)
                if !note.breadcrumbs.isEmpty {
                    BreadcrumbList(items: note.breadcrumbs).padding(.top, 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isEditing ? Theme.lineStrong : Theme.cardBorder))
        .background {
            if isEditing {
                // `shadow-[0_0_0_4px_…foreground_6%]`: a soft ring while editing.
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.06), lineWidth: 4).padding(-4)
            }
        }
        .opacity(note.isPending ? 0.6 : 1)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(isCompletion ? 14 : 15.2))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1...30)
                .focused($editorFocused)
                .accessibilityLabel("Edit note")
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    save()
                    return .handled
                }
                .onExitCommand(perform: cancel)
            HStack {
                Text("⌘↵ to save · Esc to cancel").appText(.xs).foregroundStyle(Theme.muted)
                Spacer()
                SmallGhostButton(title: "Cancel", action: cancel)
                SmallPrimaryButton(title: "Save", isDisabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
            }
        }
    }

    private func openMenu() {
        guard let overlays else { return }
        overlays.showMenu(anchor: anchor) {
            MenuPanel {
                MenuItem(icon: .edit, title: "Edit") {
                    overlays.dismiss()
                    draft = note.body
                    isEditing = true
                    editorFocused = true
                }
                MenuItem(icon: .delete, title: "Delete", isDestructive: true) {
                    overlays.showDialog {
                        ConfirmDialog(
                            title: "Delete this note?",
                            message: "Future progress reads won’t take it into account.",
                            confirmTitle: "Delete",
                            onCancel: { overlays.dismiss() },
                            onConfirm: {
                                overlays.dismiss()
                                actions.delete(note)
                            }
                        )
                    }
                }
            }
        }
    }

    private func save() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isEditing = false
        if body != note.body { actions.edit(note, String(body.prefix(NoteItem.maxBody))) }
    }

    private func cancel() {
        draft = note.body
        isEditing = false
    }
}

// MARK: - Pieces

/// A finished task or suggestion: a small filled tick before its title.
private struct CompletedTitle: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Icon.tickHeavy.image(size: 9)
                .foregroundStyle(Theme.background)
                .frame(width: 14, height: 14)
                .background(Theme.foreground, in: .circle)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(text).font(.app(15.2, .medium)).foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Which session a recap covers, in this Mac's time zone: "Tue, Nov 17 · 10:00–11:20 PM · Title".
private struct SessionLine: View {
    let session: NoteItem.Session
    let clock: Clock

    var body: some View {
        let calendar = Calendar.current
        let minutes = { (d: Date) in calendar.component(.hour, from: d) * 60 + calendar.component(.minute, from: d) }
        let day = session.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(Locale(identifier: "en_US")))
        HStack(spacing: 6) {
            Icon.calendarSmall.image(size: 14)
            Text("\(day) · \(clock.formatRange(minutes(session.startsAt), minutes(session.endsAt)))").monospacedDigit()
            Text("·")
            Text(session.title).fontWeight(.medium).foregroundStyle(Theme.foreground(0.75)).lineLimit(1)
        }
        .font(.app(13))
        .foregroundStyle(Theme.muted)
    }
}

/// Things in connected apps a recap drew on: one line each, opening in the browser. With
/// `onRemove`, each can be taken out (while drafting).
struct BreadcrumbList: View {
    let items: [NoteItem.Breadcrumb]
    var onRemove: ((NoteItem.Breadcrumb) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items, id: \.url) { item in
                HStack(spacing: 4) {
                    BreadcrumbRow(item: item)
                    if let onRemove {
                        RemoveButton { onRemove(item) }
                            .accessibilityLabel("Remove “\(item.title)”")
                    }
                }
            }
        }
        .padding(.horizontal, -8)
    }

    private struct BreadcrumbRow: View {
        let item: NoteItem.Breadcrumb
        @Environment(\.openURL) private var openURL
        @State private var isHovered = false

        var body: some View {
            Button { openURL(item.url) } label: {
                HStack(spacing: 8) {
                    ProviderMark(provider: item.provider, size: 18)
                    Text(item.title).font(.app(13)).lineLimit(1)
                        .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.85))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Open in \(item.provider.rawValue.capitalized)")
        }
    }

    private struct RemoveButton: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Icon.close.image(size: 13)
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

/// `h-8 rounded-lg bg-foreground px-3 text-sm font-semibold text-background`, faint when disabled.
struct SmallPrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, .semibold)
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 12)
                .frame(height: 32)
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

/// `h-8 rounded-lg px-3 text-sm font-medium text-muted hover:bg-wash hover:text-foreground`
struct SmallGhostButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, .medium)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
