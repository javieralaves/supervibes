import SwiftUI

/// Before sorting (the design's "2 · Before sorting"): only where the plate is fuzzy, a few questions as a stack of
/// cards. Each quotes the line it's about as typed, offers the likely answers as a single choice, each with the icon of
/// how it would land, and has room to say more, typed or said. Skip or Next; the last card's button is Sort it. The
/// cards to come peek out under the top one; answered ones are set aside to the left with what they settled.
struct FirstRunClarify: View {
    let clarify: PlateClarify
    var isSorting = false
    var error: String?
    /// Say it instead, for the words added to a question.
    var dictation = DictationState()
    var actions = FirstRunActions()
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        FirstRunFlow(
            step: 1,
            eyebrow: "Before sorting",
            title: "A few things to check",
            subtitle: "So your plate is sorted right the first time. Answer what you can, and skip the rest.",
            centered: true,
            headerTop: 20
        ) {
            ZStack(alignment: .top) {
                SetAside(answered: clarify.answered)
                    .offset(x: -420, y: 40)
                if let question = clarify.question {
                    Stack(ahead: min(clarify.questions.count - clarify.current - 1, 2)) {
                        QuestionCard(
                            question: question, number: clarify.current + 1, of: clarify.questions.count,
                            picked: clarify.picked[question.quote], more: clarify.more[question.quote] ?? "",
                            isLast: clarify.isLast, isSorting: isSorting, dictation: dictation, actions: actions
                        )
                        .id(question.quote)
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .animation(staticRendering ? nil : .snappy(duration: 0.3), value: clarify.current)
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).lineLimit(2).padding(.trailing, 8)
            } else {
                Text("About a minute").font(.app(13)).foregroundStyle(Theme.muted).padding(.trailing, 8)
            }
            FlowButton(title: "Sort without them", isEnabled: !isSorting, action: actions.sortWithoutAnswers)
        }
    }
}

/// The card on top, with the ones to come peeking out under it, each a little smaller and fainter, scaled from its foot.
private struct Stack<Card: View>: View {
    let ahead: Int
    @ViewBuilder var card: Card

    var body: some View {
        card
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    ForEach((1...max(ahead, 1)).reversed(), id: \.self) { depth in
                        if depth <= ahead {
                            RoundedRectangle(cornerRadius: 20).fill(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
                                .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .bottom)
                                .offset(y: CGFloat(depth) * 12)
                                .opacity(1 - Double(depth) * 0.25)
                        }
                    }
                }
            }
    }
}

/// Questions answered, set aside to the left, tilted and faint, each with what it settled; the latest on top.
private struct SetAside: View {
    let answered: [(quote: String, answer: String)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(answered.suffix(3).enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("“\(item.quote)”").font(.app(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    HStack(spacing: 8) {
                        Icon.tickBold.image(size: 10).foregroundStyle(Theme.background)
                            .frame(width: 18, height: 18).background(Theme.foreground, in: .circle)
                        Text(item.answer).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    }
                }
                .padding(16)
                .frame(width: 260, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 16).fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 12, y: 10)
                }
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
                .rotationEffect(.degrees(index % 2 == 0 ? -6 : -3))
                .opacity(index == min(answered.count, 3) - 1 ? 0.85 : 0.55)
                .offset(y: CGFloat(index) * 76)
            }
        }
        .frame(width: 260, alignment: .topLeading)
    }
}

private struct QuestionCard: View {
    let question: PlateQuestion
    let number: Int
    let of: Int
    let picked: Int?
    let more: String
    let isLast: Bool
    let isSorting: Bool
    let dictation: DictationState
    let actions: FirstRunActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(number) of \(of)").font(.app(12, .medium)).monospacedDigit()
                Text("·").foregroundStyle(Theme.muted.opacity(0.5))
                Text("From your plate")
            }
            .font(.app(12))
            .foregroundStyle(Theme.muted)

            // The words it's about, as typed, so it's clear which line it means.
            Text("“\(question.quote)”")
                .font(.app(14)).foregroundStyle(Theme.foreground(0.7))
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.foreground(0.15)).frame(width: 2) }
                .padding(.top, 12)

            Text(question.question)
                .font(.app(20, .semibold)).tracking(-0.4)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 6) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionRow(option: option, isOn: picked == index) { actions.pick(index) }
                }
            }
            .padding(.top, 16)

            MoreField(text: more, dictation: dictation, onChange: actions.setMore, onDictate: actions.dictate)
                .padding(.top, 12)

            HStack(spacing: 8) {
                FlowLink(title: "Skip", action: actions.skipQuestion)
                Spacer()
                FlowButton(title: isLast ? "Sort it" : "Next", primary: true, isBusy: isSorting, action: actions.nextQuestion)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .padding(.bottom, -4)
        .frame(width: 560, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Theme.card).shadow(color: .black.opacity(0.12), radius: 24, y: 20)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
    }
}

/// One likely answer: the icon of how it would land, what it means, and a tick when chosen.
private struct OptionRow: View {
    let option: PlateQuestion.Option
    let isOn: Bool
    let onPick: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                KindMark(kind: option.kind, isOn: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).font(.app(13.5, .medium)).foregroundStyle(Theme.foreground)
                    Text(option.line).font(.app(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if isOn {
                    Icon.tickBold.image(size: 10).foregroundStyle(Theme.background)
                        .frame(width: 18, height: 18).background(Theme.foreground, in: .circle)
                } else {
                    Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5).frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                    .shadow(color: .black.opacity(isOn ? 0.1 : 0), radius: 8, y: 6)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isOn ? Theme.foreground : isHovered ? Theme.lineStrong : Theme.cardBorder, lineWidth: isOn ? 1.5 : 1)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// How something would land, as the icon its kind wears elsewhere: a project's flag, a practice's repeat, a task's
/// daily task.
struct KindMark: View {
    let kind: PlateKind
    var isOn = true

    var body: some View {
        icon.image(size: 15)
            .foregroundStyle(isOn ? Theme.foreground : Theme.muted)
            .frame(width: 28, height: 28)
            .background(Theme.foreground(isOn ? 0.07 : 0.04), in: .rect(cornerRadius: 8))
    }

    private var icon: Icon {
        switch kind {
        case .project: .flag
        case .practice: .repeats
        case .task: .plan
        }
    }
}

/// Room to add what the choices don't say, typed or said: while listening, the words as they come, muted until
/// they settle.
private struct MoreField: View {
    let text: String
    let dictation: DictationState
    let onChange: (String) -> Void
    let onDictate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if dictation.isActive {
                Text("\(text)\(Text((text.isEmpty || dictation.volatile.isEmpty ? "" : " ") + dictation.volatile).foregroundStyle(Theme.muted))")
                    .font(.app(13)).foregroundStyle(Theme.foreground)
                    .lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if text.isEmpty && dictation.volatile.isEmpty {
                            Text(dictation.phase == .preparing ? "Getting ready to listen…" : "Listening…")
                                .font(.app(13)).foregroundStyle(Theme.muted.opacity(0.7))
                        }
                    }
            } else {
                TextField("", text: Binding(get: { text }, set: onChange))
                    .textFieldStyle(.plain)
                    .font(.app(13))
                    .foregroundStyle(Theme.foreground)
                    .placeholder("Anything else worth knowing? Optional", when: text.isEmpty, font: .app(13))
            }
            Button(action: onDictate) {
                (dictation.isActive ? Icon.micBold : Icon.mic).image(size: 15)
                    .foregroundStyle(dictation.isActive ? GoalPalette.color("sky") : Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(dictation.isActive ? GoalPalette.tintBackground("sky") : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(dictation.isActive ? "Stop listening" : "Say it instead")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 40)
        .background(Theme.foreground(0.035), in: .rect(cornerRadius: 12))
    }
}
