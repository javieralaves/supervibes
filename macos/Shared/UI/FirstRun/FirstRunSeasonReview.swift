import SwiftUI

/// The season, made (the design's "Focus · Your season" for Route 2, "Quests · Review" for Route 3): the quests come
/// together as a stack of cards fanned like a hand, and starting the season is the one thing to do, right under it.
/// What else is on the plate is summed up quietly below. No season is named, and neither is the next one.
struct FirstRunSeasonReview: View {
    let cards: [SeasonCard]
    let season: SeasonSpan
    var subtitle: String
    var rest: SeasonRest = .keepsGoing([])
    /// The route's row of steps, and which this is.
    var steps: [String] = FirstRunChoice.season.steps
    var step = 3
    /// A card's quest name, as renamed.
    var name: (String) -> String = { _ in "" }
    var isStarting = false
    /// Already started, coming back from the week: nothing to change, only on to the week again.
    var isStarted = false
    var error: String?
    /// A quest renamed on its card, by the card's id.
    var onRename: (String, String) -> Void = { _, _ in }
    var onBack: () -> Void = {}
    var onStart: () -> Void = {}

    private var gaps: Bool { cards.contains { $0.reach != nil } }

    var body: some View {
        FirstRunFlow(
            step: step,
            steps: steps,
            eyebrow: season.label,
            title: "This is your season",
            subtitle: subtitle,
            centered: true,
            headerTop: gaps ? 72 : 84
        ) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        let at = Self.fan(count: cards.count)[index]
                        QuestCard(card: card, season: season, lifted: at.top, name: Binding(
                            get: { name(card.id) },
                            set: { onRename(card.id, $0) }
                        ))
                        .frame(width: gaps ? 300 : 296)
                        .rotationEffect(.degrees(at.tilt))
                        .offset(x: at.x, y: at.y + 12)
                        .zIndex(at.z)
                        .disabled(isStarted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: gaps ? 292 : 272)
                .padding(.top, 16)

                VStack(spacing: 20) {
                    FlowButton(title: isStarted ? "On to your week" : "Start your season", primary: true, isBusy: isStarting, action: onStart)
                    if let error {
                        Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack))
                    }
                    restView
                }
                .padding(.top, 32)
            }
        } footer: {
            if !isStarted { FlowButton(title: "Back", action: onBack) }
            Spacer()
        }
    }

    /// Route 2's line: "Three quests, each with your attention until the end of February."
    static func focusSubtitle(count: Int, season: SeasonSpan) -> String {
        let quests = count == 1 ? "One quest" : "\(["", "One", "Two", "Three"][min(count, 3)]) quests, each"
        return "\(quests) with your attention until the end of \(season.endMonth)."
    }

    /// Route 3's line: "Three gaps to close, each as far as Feb 28 gets you, and what moves them."
    static func gapSubtitle(count: Int, season: SeasonSpan) -> String {
        let end = SeasonSpan.day(season.endsOn)
        return count == 1
            ? "One gap to close, as far as \(end) gets you, and what moves it."
            : "\(["", "One", "Two", "Three"][min(count, 3)]) gaps to close, each as far as \(end) gets you, and what moves them."
    }

    /// What else is on the plate, as overlapping badges.
    @ViewBuilder private var restView: some View {
        switch rest {
        case .split(let keep, let waits):
            if !keep.isEmpty || !waits.isEmpty {
                HStack(spacing: 24) {
                    if !keep.isEmpty { badges(keep, label: "Still get\(keep.count == 1 ? "s" : "") time") }
                    if !keep.isEmpty && !waits.isEmpty { Rectangle().fill(Theme.cardBorder).frame(width: 1, height: 16) }
                    if !waits.isEmpty { badges(waits, label: "Wait\(waits.count == 1 ? "s" : "") for next season", waits: true) }
                }
                .font(.app(12.5))
                .foregroundStyle(Theme.muted)
            }
        case .keepsGoing(let all):
            if !all.isEmpty {
                badges(all, label: "The rest of your plate keeps going")
                    .font(.app(12.5))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func badges(_ items: [PlateBadge], label: String, waits: Bool = false) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    // Overlapping, ringed, on a solid base so one badge's tint doesn't show through another.
                    GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
                        .opacity(waits ? 0.55 : 1)
                        .background(Theme.card, in: .rect(cornerRadius: item.isPractice ? 12 : 7))
                        .padding(2)
                        .background(Theme.background, in: .rect(cornerRadius: item.isPractice ? 14 : 9))
                }
            }
            Text(label)
        }
    }

    /// Where each card sits: fanned like a hand, the middle one on top.
    struct Fan { var x: CGFloat; var y: CGFloat; var tilt: Double; var z: Double; var top: Bool { z == 3 } }

    static func fan(count: Int) -> [Fan] {
        switch count {
        case 1: [Fan(x: 0, y: 0, tilt: 0, z: 3)]
        case 2: [Fan(x: -150, y: 12, tilt: -3, z: 1), Fan(x: 150, y: 0, tilt: 3, z: 3)]
        default: [Fan(x: -280, y: 26, tilt: -5, z: 1), Fan(x: 0, y: 0, tilt: 0, z: 3), Fan(x: 280, y: 26, tilt: 5, z: 2)]
        }
    }
}

/// A quest's card: a wash in its colour with the season's track (all the way for a focus, or as far as a gap's quest
/// reaches), its number as a quest, a name to rename, and what moves it.
private struct QuestCard: View {
    let card: SeasonCard
    let season: SeasonSpan
    /// On top of the stack, with a deeper shadow.
    var lifted = false
    @Binding var name: String
    @State private var isHovered = false
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(GoalPalette.tintBackground(card.color))
                QuestPill(number: card.number).padding(12)
                HStack(spacing: 6) {
                    GoalIconImage(name: card.areaIcon, size: 13)
                    Text(card.areaName).font(.app(12))
                }
                .foregroundStyle(Theme.foreground(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 14).padding(.trailing, 14)
                if let reach = card.reach {
                    GapTrack(reach: reach, color: card.color, end: SeasonSpan.day(season.endsOn), from: card.mover)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                } else {
                    SeasonTrack(badge: card.mover, size: .field)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 34)
                    HStack {
                        Text(SeasonSpan.day(season.startsOn)).opacity(0.7)
                        Spacer()
                        Text(SeasonSpan.day(season.endsOn))
                    }
                    .font(.app(10.5, .semibold)).monospacedDigit()
                    .foregroundStyle(GoalPalette.color(card.color))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
            .frame(height: 128)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TextField("", text: $name, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(card.reach == nil ? 17 : 16, .semibold)).tracking(-0.25)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1...2)
                        .focused($isEditing)
                    Icon.edit.image(size: 14).foregroundStyle(Theme.muted)
                        .onTapGesture { isEditing = true }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isEditing ? Theme.foreground(0.3) : isHovered ? Theme.cardBorder : .clear)
                }
                .onHover { isHovered = $0 }
                .padding(.horizontal, -8)
                HStack(spacing: 8) {
                    Text("Moved by").foregroundStyle(Theme.muted.opacity(0.8))
                    GoalBadge(icon: card.mover.icon, color: card.mover.color, size: .micro, round: card.mover.isPractice)
                    Text(card.movedBy).font(.app(12, .medium)).foregroundStyle(Theme.foreground(0.8)).lineLimit(1)
                    if card.isNew { NewTag() }
                }
                .font(.app(12))
                .padding(.top, 8)
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                .shadow(color: .black.opacity(lifted ? 0.16 : 0.08), radius: lifted ? 15 : 14, y: lifted ? 26 : 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

/// "1 Quest": a quest's number in ink, then the word, on a light capsule.
struct QuestPill: View {
    let number: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.app(11, .semibold)).monospacedDigit()
                .foregroundStyle(Theme.background)
                .frame(width: 20, height: 20)
                .background(Theme.foreground, in: .circle)
            Text("Quest").font(.app(11.5, .semibold)).foregroundStyle(Theme.foreground)
        }
        .padding(.leading, 2).padding(.trailing, 10).frame(height: 24)
        .background(Theme.card.opacity(0.8), in: .capsule)
    }
}

/// "New": made while starting the season.
struct NewTag: View {
    var body: some View {
        Text("New").font(.app(10.5, .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Theme.foreground(0.06), in: .rect(cornerRadius: 6))
    }
}

/// A gap as a track, in its area's colour (or grey when `color` is nil): from now (a hollow dot, or the thing that
/// moves it) inked up to a ring at how far this season could get, then dashed on to where you want to be.
struct GapTrack: View {
    let reach: Int
    let color: String?
    /// "Feb 28", over the ring.
    let end: String
    var from: PlateBadge?
    /// "Now" and "Where you want to be" under the ends.
    var labels = false

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let start: CGFloat = from == nil ? 5 : 52
                let at = start + (width - start - 5) * CGFloat(min(max(reach, 0), 100)) / 100
                ZStack(alignment: .leading) {
                    Path { path in
                        path.move(to: CGPoint(x: start, y: 23))
                        path.addLine(to: CGPoint(x: width - 5, y: 23))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .opacity(0.4)
                    Capsule().frame(width: max(0, at - start), height: 3).offset(x: start)
                    if let from {
                        GoalBadge(icon: from.icon, color: from.color, size: .field, round: from.isPractice)
                            .padding(4)
                            .background {
                                RoundedRectangle(cornerRadius: 13).fill(Theme.card).shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                            }
                    } else {
                        Circle().fill(Theme.card).overlay(Circle().strokeBorder(lineWidth: 1.5)).frame(width: 10, height: 10)
                    }
                    Circle().fill(Theme.card).overlay(Circle().strokeBorder(lineWidth: 3)).frame(width: 18, height: 18)
                        .offset(x: at - 9)
                    Circle().frame(width: 10, height: 10).offset(x: width - 10)
                    Text(end).font(.app(10.5, .semibold)).monospacedDigit().fixedSize()
                        .frame(width: 60).offset(x: at - 30, y: -21)
                }
                .frame(height: 46)
            }
            .frame(height: 46)
            if labels {
                HStack {
                    Text("Now")
                    Spacer()
                    Text("Where you want to be")
                }
                .font(.app(11)).foregroundStyle(Theme.foreground(0.55))
            }
        }
        .foregroundStyle(color.map { GoalPalette.color($0) } ?? Theme.foreground(0.3))
    }
}

#Preview("Your season") {
    let board = Fixtures.focusBoard(focus: ["pricing", "move", "run"], waiting: ["spanish", "newsletter", "lisbon"])
    FirstRunSeasonReview(
        cards: board.seasonCards, season: Fixtures.firstRunSeason,
        subtitle: FirstRunSeasonReview.focusSubtitle(count: 3, season: Fixtures.firstRunSeason),
        rest: board.seasonRest, name: { board.name($0) }
    )
    .frame(width: 1280, height: 820)
}
