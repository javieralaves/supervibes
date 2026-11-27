import SwiftUI

/// What the Focus board can do, wired to FirstRunModel in the app and to nothing in previews and tests.
struct FocusActions {
    /// Into the next free slot.
    var choose: (String) -> Void = { _ in }
    /// Dropped onto a slot (0 first).
    var place: (String, Int) -> Void = { _, _ in }
    /// Out of focus, back to keep going.
    var remove: (String) -> Void = { _ in }
    /// To wait for next season.
    var wait: (String) -> Void = { _ in }
    /// Back to keep going.
    var keep: (String) -> Void = { _ in }
}

/// Route 2's Focus step (the design's "Focus · Nothing chosen yet" and "Three chosen"): up to three things to focus on,
/// drawn as a board rather than a form. Three numbered slots up top, each with the season's track; before anything's
/// chosen, the whole plate below, a click from focus; after, the rest in two lanes, what keeps going and what waits
/// for next season. Things move between them by dragging.
struct FirstRunFocus: View {
    let board: FocusBoard
    let season: SeasonSpan
    var actions = FocusActions()
    var onBack: () -> Void = {}
    var onContinue: () -> Void = {}

    var body: some View {
        FirstRunFlow(
            step: 3,
            steps: FirstRunChoice.season.steps,
            eyebrow: "The next few months · \(season.label)",
            title: "Choose up to three to focus on",
            subtitle: "Focus gets the first claim on your time until \(season.endMonth). The rest keeps going, or waits."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<FocusBoard.slots, id: \.self) { slot in
                            FocusSlotDrop(board: board, slot: slot, end: SeasonSpan.day(season.endsOn), actions: actions)
                        }
                    }
                    if board.focus.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Your plate").font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                            Text("Click one to focus on it, or drag it into a slot").font(.app(12)).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 24)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(board.items) { item in
                                PlateTile(item: item, taken: board.areaFocus(for: item.id), canFocus: board.canFocus(item.id)) {
                                    actions.choose(item.id)
                                }
                            }
                        }
                        .padding(.top, 10)
                    } else {
                        VStack(spacing: 12) {
                            Lane(title: "Keep going", line: "Still gets time", items: board.keepGoing, board: board, actions: actions)
                            Lane(title: "Next season", line: "Waits until this one ends", items: board.waits, board: board, waits: true, actions: actions)
                        }
                        .padding(.top, 24)
                        Text("To swap a focus, remove it or drag something onto it. Nothing is deleted.")
                            .font(.app(12)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: onBack)
            Spacer()
            Text("\(board.focus.count) of \(FocusBoard.slots) chosen")
                .font(.app(13, .medium)).monospacedDigit()
                .foregroundStyle(board.focus.isEmpty ? Theme.muted : Theme.foreground)
                .padding(.trailing, 8)
            FlowButton(title: "Continue", primary: true, isEnabled: !board.focus.isEmpty, action: onContinue)
        }
    }
}

// MARK: - Slots

/// A slot, filled or not, that takes a drop: something from the plate to fill or swap it, or another focus to trade
/// places with.
private struct FocusSlotDrop: View {
    let board: FocusBoard
    let slot: Int
    let end: String
    let actions: FocusActions
    @State private var isTargeted = false

    var body: some View {
        Group {
            if slot < board.focus.count, let item = board.item(board.focus[slot]) {
                FocusSlot(item: item, number: slot + 1, end: end) { actions.remove(item.id) }
                    .draggable(item.id) { FocusDragChip(item: item) }
            } else {
                EmptySlot(number: slot + 1, end: end)
            }
        }
        .overlay { if isTargeted { RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground, lineWidth: 1.5) } }
        .frame(maxWidth: .infinity)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, board.canPlace(id, at: slot) else { return false }
            actions.place(id, slot)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// One of the focuses: a wash in its colour with its badge setting off along the season's dashed track, then its
/// area, name and kind. Hovered, a way to take it out of focus.
private struct FocusSlot: View {
    let item: FocusItem
    let number: Int
    let end: String
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12).fill(GoalPalette.tintBackground(item.color))
                Text("\(number)")
                    .font(.app(12, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.background)
                    .frame(width: 24, height: 24)
                    .background(Theme.foreground, in: .circle)
                    .padding(12)
                SeasonTrack(badge: item.badge, size: .sm)
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 38)
                Text(end)
                    .font(.app(10.5, .semibold)).monospacedDigit()
                    .foregroundStyle(GoalPalette.color(item.color))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14).padding(.bottom, 14)
            }
            .frame(height: 136)
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button(action: onRemove) {
                        HStack(spacing: 4) {
                            Icon.close.image(size: 11)
                            Text("Remove").font(.app(12, .medium))
                        }
                        .foregroundStyle(Theme.foreground)
                        .padding(.horizontal, 8).frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 8).fill(Theme.card).shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    GoalIconImage(name: item.areaIcon, size: 13)
                    Text(item.areaName).font(.app(12))
                }
                .foregroundStyle(Theme.muted)
                Text(item.title)
                    .font(.app(15, .semibold)).tracking(-0.15)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Text(item.isPractice ? "Practice · \(item.rhythm ?? "")" : "Project")
                    .font(.app(12)).foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .padding(8)
        .frame(minHeight: 236, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 14, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .contentShape(.rect(cornerRadius: 16))
        .onHover { isHovered = $0 }
    }
}

/// A slot not filled yet: dashed, its number faint, the season's track waiting for something to set off on it.
private struct EmptySlot: View {
    let number: Int
    let end: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12).fill(Theme.foreground(0.025))
                Text("\(number)")
                    .font(.app(12, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Theme.foreground(0.2), lineWidth: 1.5))
                    .padding(12)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 48, height: 48)
                    DashedLine()
                    Circle().frame(width: 10, height: 10)
                }
                .foregroundStyle(Theme.foreground(0.25))
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 38)
                Text(end)
                    .font(.app(10.5, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 14).padding(.bottom, 14)
            }
            .frame(height: 136)
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus \(number)").font(.app(13.5, .semibold)).foregroundStyle(Theme.muted)
                Text(number == 1 ? "Pick something below" : "Optional").font(.app(12)).foregroundStyle(Theme.muted.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
        }
        .padding(8)
        .frame(height: 236, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(.rect(cornerRadius: 16))
    }
}

// MARK: - The plate

/// One thing on the plate before anything's chosen, all at the same level. Hovered, it offers to become a focus; one
/// from an area that already has a focus says so instead.
private struct PlateTile: View {
    let item: FocusItem
    /// The focus already in its area.
    let taken: FocusItem?
    let canFocus: Bool
    let onFocus: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            GoalBadge(icon: item.icon, color: item.color, size: .card, round: item.isPractice)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text(taken.map { "\($0.areaName) has a focus" } ?? item.plateLine)
                    .font(.app(11.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered && canFocus {
                HStack(spacing: 4) {
                    Icon.add.image(size: 11)
                    Text("Focus").font(.app(12, .medium))
                }
                .foregroundStyle(Theme.background)
                .padding(.horizontal, 8).frame(height: 28)
                .background(Theme.foreground, in: .rect(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 60)
        .opacity(taken == nil ? 1 : 0.55)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .shadow(color: .black.opacity(isHovered && canFocus ? 0.12 : 0), radius: 10, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered && canFocus ? Theme.foreground : Theme.cardBorder, lineWidth: isHovered && canFocus ? 1.5 : 1)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .onTapGesture { if canFocus { onFocus() } }
        .draggable(item.id) { FocusDragChip(item: item) }
    }
}

/// The rest of the plate, by where it goes: the lane's name and what it means, then its things as tiles. Something
/// dropped on it goes there.
private struct Lane: View {
    let title: String
    let line: String
    let items: [FocusItem]
    let board: FocusBoard
    var waits = false
    let actions: FocusActions
    @State private var isTargeted = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(13, .semibold)).foregroundStyle(Theme.foreground)
                Text(line).font(.app(12)).foregroundStyle(Theme.muted)
            }
            .frame(width: 150, alignment: .leading)
            if items.isEmpty {
                Text(waits ? "Drag anything that can wait here" : "Everything else is in focus or waiting")
                    .font(.app(12)).foregroundStyle(Theme.muted.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(items) { item in
                        LaneTile(item: item, waits: waits, canFocus: board.canFocus(item.id)) { actions.choose(item.id) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .padding(.leading, 4)
        .background(Theme.foreground(isTargeted ? 0.05 : 0.025), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isTargeted ? Theme.foreground(0.4) : Theme.foreground(0.04), lineWidth: isTargeted ? 1.5 : 1)
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, board.item(id) != nil else { return false }
            if waits {
                actions.wait(id)
            } else {
                actions.remove(id)
                actions.keep(id)
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// One thing in a lane; a click focuses it while there's room for it.
private struct LaneTile: View {
    let item: FocusItem
    let waits: Bool
    let canFocus: Bool
    let onFocus: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
                .scaleEffect(28.0 / 24.0)
                .frame(width: 28, height: 28)
                .opacity(waits ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                Text("\(item.areaName) · \(item.kindName)").font(.app(11.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .opacity(waits ? 0.6 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: 236, height: 52)
        .background(Theme.card, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(isHovered && canFocus ? Theme.lineStrong : Theme.cardBorder)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { isHovered = $0 }
        .onTapGesture { if canFocus { onFocus() } }
        .draggable(item.id) { FocusDragChip(item: item) }
    }
}

/// What's under the pointer while something on the board is dragged.
private struct FocusDragChip: View {
    let item: FocusItem

    var body: some View {
        HStack(spacing: 8) {
            GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
            Text(item.title).font(.app(12, .medium)).foregroundStyle(Theme.foreground)
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 34)
        .background(Theme.card, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }
}

// MARK: - Shared with the season

/// The season's track in a thing's colour: its badge on a white mat setting off along a dashed line to a dot.
struct SeasonTrack: View {
    let badge: PlateBadge
    var size: GoalBadge.Size = .sm

    var body: some View {
        HStack(spacing: 8) {
            GoalBadge(icon: badge.icon, color: badge.color, size: size, round: badge.isPractice)
                .padding(4)
                .background {
                    RoundedRectangle(cornerRadius: size == .sm ? 13 : 12).fill(Theme.card)
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                }
            DashedLine().opacity(0.45)
            Circle().frame(width: 10, height: 10)
        }
        .foregroundStyle(GoalPalette.color(badge.color))
    }
}

/// A horizontal dashed line, 1.5 thick, as wide as it's given.
struct DashedLine: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.75))
                path.addLine(to: CGPoint(x: geometry.size.width, y: 0.75))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(height: 1.5)
    }
}

#Preview("Nothing chosen yet") {
    FirstRunFocus(board: Fixtures.focusBoard(), season: Fixtures.firstRunSeason)
        .frame(width: 1280, height: 820)
}

#Preview("Three chosen") {
    @Previewable @State var board = Fixtures.focusBoard(focus: ["pricing", "move", "run"], waiting: ["spanish", "newsletter", "lisbon"])
    FirstRunFocus(board: board, season: Fixtures.firstRunSeason, actions: FocusActions(
        choose: { board.choose($0) }, place: { board.place($0, at: $1) }, remove: { board.remove($0) },
        wait: { board.wait($0) }, keep: { board.keep($0) }
    ))
    .frame(width: 1280, height: 820)
}
