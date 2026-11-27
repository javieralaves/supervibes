import SwiftUI

/// Step 1: everything on someone's plate, in their own words, however messy. A big writing card, and beside it a few
/// prompts by part of life for anyone who stalls. Sort it sends the words to be sorted into projects and practices.
struct FirstRunPlate: View {
    @Binding var text: String
    var isSorting = false
    var error: String?
    let onBack: () -> Void
    let onSort: () -> Void

    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
            .padding(.horizontal, 15)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .disabled(isSorting)
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
