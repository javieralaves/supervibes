import SwiftUI

/// Step 1: everything on someone's plate, in their own words, however messy, typed or said. A big writing card with
/// Say it instead along its bottom, and beside it a few prompts by part of life for anyone who stalls. Sort it sends
/// the words to be sorted into projects and practices.
struct FirstRunPlate: View {
    @Binding var text: String
    var isSorting = false
    var error: String?
    /// Say it instead: whether it's listening, and what it's hearing.
    var dictation = DictationState()
    var onDictate: () -> Void = {}
    let onBack: () -> Void
    let onSort: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dictation.volatile.isEmpty
    }

    var body: some View {
        FirstRunFlow(
            step: 0,
            eyebrow: "Your plate",
            title: "What’s on your plate?",
            subtitle: "Everything you’re working on, looking after or meaning to start, at work and outside it. Messy is fine: it gets sorted next."
        ) {
            HStack(alignment: .top, spacing: 16) {
                writing
                StuckCard().frame(width: 272)
            }
            .frame(maxHeight: 440)
        } footer: {
            FlowButton(title: "Back", action: onBack)
            Spacer()
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).lineLimit(2).padding(.trailing, 8)
            }
            FlowButton(title: isSorting ? "Sorting…" : "Sort it", primary: true, isBusy: isSorting, isEnabled: !isEmpty, action: onSort)
        }
    }

    private var writing: some View {
        VStack(spacing: 0) {
            Group {
                if dictation.isActive { live } else { editor }
            }
            .padding(.horizontal, 15)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            DictationBar(state: dictation, onToggle: onDictate)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .disabled(isSorting)
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.app(15))
            .lineSpacing(6)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Theme.foreground)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    // An example, where the first line goes; the editor's own text sits 5 in from its edge.
                    Text("pricing page launch, needs to ship before Q1 planning\nrunning again, 3x a week ideally\nplan that trip with marta…")
                        .font(.app(15)).lineSpacing(6)
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .disabled(isSorting)
    }

    /// While listening: the plate as written so far, then what's being said, muted, until it settles; kept
    /// scrolled to the end, where the words arrive.
    private var live: some View {
        ScrollView {
            Text("\(text)\(Text(joiner + dictation.volatile).foregroundStyle(Theme.muted)) ")
                .font(.app(15)).lineSpacing(6)
                .foregroundStyle(Theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 5)
                .textSelection(.disabled)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
        .overlay(alignment: .topLeading) {
            if text.isEmpty && dictation.volatile.isEmpty {
                Text(dictation.phase == .preparing ? "Getting ready to listen…" : "Listening. Say what’s on your plate, however it comes.")
                    .font(.app(15)).foregroundStyle(Theme.muted.opacity(0.6))
                    .padding(.leading, 5)
            }
        }
    }

    /// A space between what's written and what's being said, unless the text already ends in one.
    private var joiner: String {
        guard !text.isEmpty, !dictation.volatile.isEmpty, text.last?.isWhitespace == false else { return "" }
        return " "
    }
}

/// The writing card's bottom bar: Say it instead, which while listening becomes a lit mic beside a waveform of what it
/// hears, quiet moments as dots and speech as bars, moving left as it goes.
private struct DictationBar: View {
    let state: DictationState
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch state.phase {
            case .idle:
                SayButton(onToggle: onToggle)
                if let error = state.error {
                    Text(error).font(.app(12)).foregroundStyle(Theme.danger).lineLimit(2)
                }
            case .preparing:
                MicButton(isLit: true, onToggle: onToggle)
                HStack(spacing: 8) {
                    SpinningIcon(size: 12)
                    Text("Getting ready to listen").font(.app(12.5))
                }
                .foregroundStyle(Theme.muted)
            case .listening, .finishing:
                MicButton(isLit: true, onToggle: onToggle)
                Waveform(levels: state.levels)
                    .help("Listening")
            }
            Spacer(minLength: 0)
            if state.phase == .listening {
                Text("Click the mic when you’re done").font(.app(12)).foregroundStyle(Theme.muted.opacity(0.8))
            }
        }
        .frame(height: 32)
    }
}

/// Say it instead (the design's chip): the mic and the words, on a faint wash.
private struct SayButton: View {
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Icon.mic.image(size: 15)
                Text("Say it instead").font(.app(12.5, .medium))
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Theme.foreground(isHovered ? 0.08 : 0.05), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Talk instead of typing. Words show as you speak.")
    }
}

/// The mic while listening: lit in a soft blue, a click to stop.
private struct MicButton: View {
    let isLit: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            Icon.micBold.image(size: 16)
                .foregroundStyle(GoalPalette.color("sky"))
                .frame(width: 32, height: 32)
                .background(GoalPalette.tintBackground("sky").opacity(isHovered ? 1 : 0.85), in: .rect(cornerRadius: 9))
                .contentShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Stop listening")
    }
}

/// What the mic hears, newest on the right: each moment a thin bar as tall as it was loud, or a dot when quiet.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(padded.enumerated()), id: \.offset) { _, level in
                if level < 0.08 {
                    Circle().fill(Theme.foreground(0.3)).frame(width: 2.5, height: 2.5)
                } else {
                    Capsule().fill(Theme.foreground(0.55)).frame(width: 2.5, height: 3 + CGFloat(level) * 17)
                }
            }
        }
        .frame(height: 22)
    }

    /// Always the same number of moments, so it starts as a row of dots and speech arrives from the right.
    private var padded: [Float] {
        let recent = levels.suffix(DictationState.levelCount)
        return Array(repeating: 0, count: DictationState.levelCount - recent.count) + recent
    }
}

/// Prompts for anyone who stalls, by part of life, each in a colour of its own, like the areas they'll become.
private struct StuckCard: View {
    private let prompts: [(icon: String, color: String, title: String, line: String)] = [
        ("Briefcase01Icon", "violet", "Work", "What’s due, what’s stuck"),
        ("Home01Icon", "amber", "Home and money", "Moves, paperwork, bills, repairs"),
        ("FavouriteIcon", "green", "Health", "What you keep up, or want to"),
        ("Agreement01Icon", "pink", "People", "Plans, visits, favours owed"),
        ("Mortarboard01Icon", "sky", "Growth and fun", "What you keep meaning to start"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("If you’re stuck, think about").font(.app(12.5, .semibold)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(prompts, id: \.title) { prompt in
                    HStack(spacing: 10) {
                        GoalBadge(icon: prompt.icon, color: prompt.color, size: .xs)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(prompt.title).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground)
                            Text(prompt.line).font(.app(11.5)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [GoalPalette.tintBackground("amber").opacity(0.5), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}
