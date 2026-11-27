import SwiftUI

/// Route 2's season, made (the design's "Focus · Your season"): the focuses, now quests, come together as a stack of
/// cards fanned like a hand, and starting the season is the one thing to do, right under it. What else is on the plate
/// is summed up quietly below, as what still gets time and what waits for next season. No season is named, and
/// neither is the next one.
struct FirstRunSeasonReview: View {
    let board: FocusBoard
    let season: SeasonSpan
    var isStarting = false
    /// Already started, coming back from the week: nothing to change, only on to the week again.
    var isStarted = false
    var error: String?
    /// A quest renamed on its card, by its goal's id.
    var onRename: (String, String) -> Void = { _, _ in }
    var onBack: () -> Void = {}
    var onStart: () -> Void = {}

    var body: some View {
        FirstRunFlow(
            step: 3,
            steps: FirstRunChoice.season.steps,
            eyebrow: season.label,
            title: "This is your season",
            subtitle: subtitle,
            centered: true,
            headerTop: 84
        ) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    ForEach(Array(board.focused.enumerated()), id: \.element.id) { index, item in
                        let at = Self.fan(count: board.focused.count)[index]
                        QuestCard(item: item, number: index + 1, season: season, lifted: at.top, name: Binding(
                            get: { board.name(item.id) },
                            set: { onRename(item.id, $0) }
                        ))
                        .frame(width: 296)
                        .rotationEffect(.degrees(at.tilt))
                        .offset(x: at.x, y: at.y + 12)
                        .zIndex(at.z)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 272)
                .padding(.top, 16)

                VStack(spacing: 20) {
                    FlowButton(title: isStarted ? "On to your week" : "Start your season", primary: true, isBusy: isStarting, action: onStart)
                    if let error {
                        Text(error).font(.app(12.5)).foregroundStyle(StatusTone.text(.offTrack))
                    }
                    rest
                }
                .padding(.top, 32)
            }
        } footer: {
            if !isStarted { FlowButton(title: "Back", action: onBack) }
            Spacer()
        }
    }

    private var subtitle: String {
        let count = board.focus.count
        let quests = count == 1 ? "One quest" : "\(["", "One", "Two", "Three"][min(count, 3)]) quests, each"
        return "\(quests) with your attention until the end of \(season.endMonth)."
    }

    /// What else is on the plate, as overlapping badges: what still gets time, then what waits.
    @ViewBuilder private var rest: some View {
        let keep = board.keepGoing, waits = board.waits
        if !keep.isEmpty || !waits.isEmpty {
            HStack(spacing: 24) {
                if !keep.isEmpty { badges(keep, label: "Still get\(keep.count == 1 ? "s" : "") time") }
                if !keep.isEmpty && !waits.isEmpty { Rectangle().fill(Theme.cardBorder).frame(width: 1, height: 16) }
                if !waits.isEmpty { badges(waits, label: "Wait\(waits.count == 1 ? "s" : "") for next season", waits: true) }
            }
            .font(.app(12.5))
            .foregroundStyle(Theme.muted)
        }
    }

    private func badges(_ items: [FocusItem], label: String, waits: Bool = false) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                ForEach(items) { item in
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

/// A focus turned quest: the Focus step's slot, grown up. A wash in its colour with the season's track, now dated at
/// both ends; its number as a quest; a name to rename, which starts as the thing's own; and what moves it.
private struct QuestCard: View {
    let item: FocusItem
    let number: Int
    let season: SeasonSpan
    /// On top of the stack, with a deeper shadow.
    var lifted = false
    @Binding var name: String
    @State private var isHovered = false
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(GoalPalette.tintBackground(item.color))
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
                .padding(12)
                HStack(spacing: 6) {
                    GoalIconImage(name: item.areaIcon, size: 13)
                    Text(item.areaName).font(.app(12))
                }
                .foregroundStyle(Theme.foreground(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 14).padding(.trailing, 14)
                SeasonTrack(item: item, badge: .field)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 34)
                HStack {
                    Text(SeasonSpan.day(season.startsOn)).opacity(0.7)
                    Spacer()
                    Text(SeasonSpan.day(season.endsOn))
                }
                .font(.app(10.5, .semibold)).monospacedDigit()
                .foregroundStyle(GoalPalette.color(item.color))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .frame(height: 128)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TextField("", text: $name)
                        .textFieldStyle(.plain)
                        .font(.app(17, .semibold)).tracking(-0.25)
                        .foregroundStyle(Theme.foreground)
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
                    GoalBadge(icon: item.icon, color: item.color, size: .micro, round: item.isPractice)
                    Text(item.isPractice ? "\(item.title), \((item.rhythm ?? "").lowercased())" : item.title)
                        .font(.app(12, .medium)).foregroundStyle(Theme.foreground(0.8)).lineLimit(1)
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

#Preview("Your season") {
    FirstRunSeasonReview(
        board: Fixtures.focusBoard(focus: ["pricing", "move", "run"], waiting: ["spanish", "newsletter", "lisbon"]),
        season: Fixtures.firstRunSeason
    )
    .frame(width: 1280, height: 820)
}
