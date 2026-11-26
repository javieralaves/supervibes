import SwiftUI

/// Where an area is going, as one card: where you are and where you want to be side by side, joined by a dashed
/// track from the first to the second, and the gap between them in the card's footer. The design's DirectionCard
/// (supervibes-design, seasons-quests.tsx): `rounded-2xl bg-card`, two columns at `px-6 pt-5 pb-6 gap-8`, the footer a
/// wash under a hairline.
struct AreaDirectionCard<Now: View, Want: View, Gap: View>: View {
    @ViewBuilder var now: Now
    @ViewBuilder var want: Want
    @ViewBuilder var gap: Gap

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle().strokeBorder(Theme.foreground(0.55), lineWidth: 1.5).frame(width: 11, height: 11)
                        CardLabel("Where you are")
                        // The track runs on across the space between the columns, to the dot of where you want to be.
                        DashedTrack().padding(.leading, 4).padding(.trailing, -22)
                    }
                    .frame(height: 16)
                    now
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle().fill(Theme.foreground).frame(width: 11, height: 11)
                        CardLabel("Where you want to be")
                    }
                    .frame(height: 16)
                    want
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            Rectangle().fill(Theme.cardBorder).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                CardLabel("The gap")
                gap
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(Theme.foreground(0.025))
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card).shadow(color: .black.opacity(0.04), radius: 1, y: 1))
    }
}

/// `text-[11px] font-medium uppercase tracking-[0.02em] text-muted`: the small caps naming the parts of a card.
struct CardLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.app(11, .medium))
            .tracking(0.02 * 11)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A 1-point line of 4-point dashes in a soft ink, filling the width it's given.
private struct DashedTrack: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
            }
            .stroke(Theme.foreground(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }
}

// MARK: - The gap

/// The gap between where an area is and where the person wants it, in the direction card's footer.
///
/// Named, it shows its headline and a line or two, who named it and when, Edit and Name it again. Not yet, it says
/// what it will be, with Name the gap and Write it yourself; Supervibes names it only once both sides are said, and
/// only when asked. Write it yourself and Edit turn it into two fields in place.
struct AreaGapView: View {
    let area: Area
    /// The area has projects or practices for Supervibes to read too.
    let hasGoals: Bool
    var naming = false
    var error: String?
    let now: Date
    /// Names the gap; nil when it can't be asked for here.
    var onName: (() -> Void)?
    /// Saves the gap as written; true once saved. Nil leaves it as it is.
    var onWrite: ((GapInput) async -> Bool)?
    /// Opens being written (snapshots).
    var startsWriting = false

    enum Field: Hashable { case title, body }

    /// Writing; nil until Write it yourself, Edit or Save is pressed, then it follows them.
    @State private var writing: Bool?
    @State private var draft: GapInput?
    @State private var isSaving = false
    @FocusState private var focus: Field?

    private var isWriting: Bool { (writing ?? startsWriting) && onWrite != nil }
    private var input: GapInput { draft ?? GapInput(editing: area.gap) }
    /// Both sides are said, so there's something to name it from.
    private var canName: Bool { !(area.now ?? "").isEmpty && !(area.want ?? "").isEmpty && onName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isWriting {
                fields
            } else if let gap = area.gap {
                named(gap)
            } else {
                unnamed
            }
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).padding(.top, 10)
            }
        }
    }

    // MARK: States

    @ViewBuilder private func named(_ gap: AreaGap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(gap.title)
                .font(.app(17, .semibold))
                .tracking(-0.015 * 17)
                .lineSpacing(17 * 0.45 - 17 * 0.2)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if !gap.body.isEmpty {
                Text(gap.body)
                    .font(.app(15))
                    .lineSpacing(15 * 0.6 - 15 * 0.2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .compositingGroup()
        .opacity(naming ? 0.5 : 1)

        HStack(spacing: 8) {
            Text(naming
                ? "Reading your words and its projects and practices. This takes a few seconds."
                : "\(gap.by == .you ? "Written by you" : "Named by Supervibes") · \(gap.at.shortAgo(now: now))")
                .appText(.xs)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            if onWrite != nil {
                GapButton(icon: .edit, title: "Edit", style: .outline) { startWriting() }
                    .inactive(naming)
            }
            if canName, let onName {
                GapButton(icon: .refresh, title: naming ? "Naming…" : "Name it again", style: .outline, busy: naming, action: onName)
                    .help("Name it again from your words and its projects and practices")
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var unnamed: some View {
        let bothSaid = !(area.now ?? "").isEmpty && !(area.want ?? "").isEmpty
        Text(canName
            ? "What stands between the two? Supervibes can name it from your words\(hasGoals ? " and \(area.name)’s projects and practices" : "")."
            : bothSaid
                ? "What stands between the two? Not named yet."
                : "Once you’ve said where \(area.name) is and where you want it to be, Supervibes can name what stands between them.")
            .font(.app(15))
            .lineSpacing(15 * 0.55 - 15 * 0.2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .compositingGroup()
            .opacity(naming ? 0.5 : 1)

        if onName != nil || onWrite != nil {
            HStack(spacing: 12) {
                if canName, let onName {
                    GapButton(icon: .route, title: naming ? "Naming…" : "Name the gap", style: .primary, busy: naming, action: onName)
                }
                if onWrite != nil {
                    GapButton(icon: .edit, title: "Write it yourself", style: .plain) { startWriting() }
                        .inactive(naming)
                }
                if naming {
                    Text("This takes a few seconds.").appText(.xs).foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            field(.title, text: binding(\.title, max: GapInput.maxTitle), prompt: "From where it is to where you want it, in a few words",
                  size: 17, weight: .semibold, tracking: -0.015, lines: 1...3)
            field(.body, text: binding(\.body, max: GapInput.maxBody), prompt: "What closing it takes, in a line or two (optional)",
                  size: 15, weight: .regular, tracking: 0, lines: 2...6)
        }
        HStack(spacing: 8) {
            GapButton(icon: .tick, title: isSaving ? "Saving…" : "Save", style: .primary, busy: isSaving) { save() }
            GapButton(title: "Cancel", style: .plain) { cancel() }
                .inactive(isSaving)
        }
        .padding(.top, 12)
    }

    private func field(_ field: Field, text: Binding<String>, prompt: String, size: CGFloat, weight: Font.Weight,
                       tracking: CGFloat, lines: ClosedRange<Int>) -> some View {
        let font = Font.app(size, weight)
        return TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .tracking(tracking * size)
            .foregroundStyle(field == .title ? Theme.foreground : Theme.muted)
            .lineLimit(lines)
            .placeholder(prompt, when: text.wrappedValue.isEmpty, font: font)
            .focused($focus, equals: field)
            .onSubmit { if field == .title { save() } }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focus == field ? Theme.foreground(0.6) : Theme.cardBorder, lineWidth: focus == field ? 1.5 : 1))
            .onEscape { cancel() }
    }

    // MARK: Writing

    private func binding(_ key: WritableKeyPath<GapInput, String>, max: Int) -> Binding<String> {
        Binding(
            get: { input[keyPath: key] },
            set: { value in
                var next = input
                next[keyPath: key] = String(value.prefix(max))
                draft = next
            }
        )
    }

    private func startWriting() {
        draft = GapInput(editing: area.gap)
        writing = true
        DispatchQueue.main.async { focus = .title }
    }

    private func save() {
        guard let onWrite, !isSaving else { return }
        isSaving = true
        Task {
            if await onWrite(input) {
                writing = false
                draft = nil
            }
            isSaving = false
        }
    }

    private func cancel() {
        draft = nil
        writing = false
    }
}

/// The gap's small buttons. Primary: `h-8 rounded-lg bg-foreground px-3 text-[13px] font-medium text-background`;
/// outline: `h-7 rounded-lg bg-card px-2.5 text-xs font-medium`, ringed; plain: just its icon and words, muted.
private struct GapButton: View {
    enum Style { case primary, outline, plain }

    var icon: Icon?
    let title: String
    let style: Style
    var busy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    SpinningIcon(size: style == .primary ? 14 : 13)
                } else if let icon {
                    icon.image(size: style == .primary ? 14 : 13)
                }
                Text(title).font(.app(style == .outline ? 12 : 13, .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, style == .plain ? 0 : (style == .primary ? 12 : 10))
            .frame(height: style == .outline ? 28 : 32)
            .background(background, in: .rect(cornerRadius: 8))
            .overlay {
                if style == .outline {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder)
                }
            }
            .compositingGroup()
            .opacity(busy ? 0.7 : (style == .primary && isHovered ? 0.9 : 1))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(busy)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch style {
        case .primary: Theme.background
        case .outline: Theme.foreground
        case .plain: isHovered ? Theme.foreground : Theme.muted
        }
    }

    private var background: Color {
        switch style {
        case .primary: Theme.foreground
        case .outline: Theme.card
        case .plain: .clear
        }
    }
}
