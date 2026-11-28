import SwiftUI

/// The frame every step of starting a season shares (the design's Flow): an eyebrow, a title and a line, the step's
/// content, and a bar along the bottom with its way back and forward. Full page, no steps row: the step is all there
/// is. "Finish later" at the top leaves it; the draft keeps where you were.
struct SeasonFlow<Content: View, Footer: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var onClose: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(eyebrow).font(.app(13, .medium)).foregroundStyle(Theme.muted)
                        Spacer()
                        if let onClose {
                            FlowLink(title: "Finish later", action: onClose)
                                .help("Leave this for now; the season keeps where you were")
                        }
                    }
                    Text(title)
                        .font(.app(30, .semibold))
                        .tracking(-0.03 * 30)
                        .foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    Text(subtitle)
                        .font(.app(15.2))
                        .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 680, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    content.padding(.top, 32)
                }
                .frame(maxWidth: 960, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 64)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)

            HStack(spacing: 8) { footer }
                .frame(maxWidth: 960)
                .padding(.horizontal, 32)
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(Theme.background.opacity(0.85))
                .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
        }
    }
}

// MARK: - Buttons

/// The bar's buttons. Primary: `h-9 rounded-xl bg-foreground px-4 text-sm font-medium text-background`; secondary:
/// the same, ringed on the card.
struct FlowButton: View {
    let title: String
    var primary = false
    var isBusy = false
    var isEnabled = true
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // While busy the spinner takes the label's place; the label stays in the layout,
            // hidden, so the button keeps its width.
            ZStack {
                Text(title).appText(.sm, .medium).opacity(isBusy ? 0 : 1)
                if isBusy { Spinner(size: 14) }
            }
            .foregroundStyle(primary ? Theme.background : Theme.foreground)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(primary ? Theme.foreground : Theme.card, in: .rect(cornerRadius: 12))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder)
                }
            }
            .compositingGroup()
            .opacity(!isEnabled ? 0.35 : (primary && isHovered && !isBusy ? 0.9 : 1))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .inactive(isBusy || !isEnabled)
        .onHover { isHovered = $0 }
    }
}

/// Muted words that darken on hover, an icon before them if given.
struct FlowLink: View {
    var icon: Icon?
    let title: String
    var size: CGFloat = 13
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { icon.image(size: size) }
                Text(title).font(.app(size, .medium))
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A small ringed button on a card: `h-7 rounded-lg bg-card px-2.5 text-xs font-medium`.
struct FlowSmallButton: View {
    var icon: Icon?
    let title: String
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy { Spinner(size: 12) } else if let icon { icon.image(size: 12) }
                Text(title).font(.app(12, .medium))
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.card, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .compositingGroup()
            .opacity(isBusy ? 0.7 : 1)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .inactive(isBusy)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Marks

/// A round tick in ink when picked, an empty ring when not; a number in place of the tick when given.
struct PickMark: View {
    let on: Bool
    var number: Int?

    var body: some View {
        ZStack {
            if on {
                Circle().fill(Theme.foreground)
                if let number {
                    Text("\(number)").font(.app(12, .semibold)).monospacedDigit().foregroundStyle(Theme.background)
                } else {
                    Icon.tick.image(size: 13).foregroundStyle(Theme.background)
                }
            } else {
                Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// "New": a quiet pill beside something made while starting the season.
struct NewPill: View {
    var body: some View {
        Text("New")
            .font(.app(10.5, .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.foreground(0.06), in: .capsule)
    }
}

/// An area's goals as a row of mini badges, projects square and practices round.
struct GoalBadgeRow: View {
    let goals: [Goal]
    var size: GoalBadge.Size = .mini

    var body: some View {
        HStack(spacing: 6) {
            ForEach(goals) { goal in
                GoalBadge(icon: goal.icon, color: goal.color, size: size, round: goal.isPractice).help(goal.title)
            }
        }
    }
}

// MARK: - The reach

/// A quest's timeline, labelled so it reads plainly (the design's ReachArt): now (a hollow dot), the season's end
/// (a ring, where it would leave you) and where you want to be (a solid dot), inked from now to the ring and dashed
/// beyond. Faint until chosen.
struct ReachArt: View {
    let reach: Int
    /// "Feb 28".
    let end: String
    var on = true

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let x = geometry.size.width * CGFloat(reach) / 100
                Text(end)
                    .font(.app(11, .semibold))
                    .monospacedDigit()
                    .fixedSize()
                    .position(x: x, y: 8)
            }
            .frame(height: 16)
            ReachTrack(reach: reach, dot: 10, ring: 18, ink: 3, ringHalo: false)
                .frame(height: 20)
                .padding(.top, 4)
            HStack {
                Text("Now")
                Spacer()
                Text("Where you want to be")
            }
            .font(.app(11))
            .foregroundStyle(Theme.muted)
            .padding(.top, 6)
        }
        .foregroundStyle(Theme.foreground)
        .opacity(on ? 1 : 0.45)
    }
}

/// The track itself: a dashed line between a hollow dot and a solid one, inked up to a ring at `reach` percent.
struct ReachTrack: View {
    let reach: Int
    var dot: CGFloat = 12
    var ring: CGFloat = 18
    var ink: CGFloat = 3
    var ringHalo = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let mid = geometry.size.height / 2
            let x = width * CGFloat(reach) / 100
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: dot / 2, y: mid))
                    path.addLine(to: CGPoint(x: width - dot / 2, y: mid))
                }
                .stroke(Theme.foreground(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Capsule()
                    .fill(Theme.foreground)
                    .frame(width: max(0, x - dot / 2), height: ink)
                    .position(x: dot / 2 + max(0, x - dot / 2) / 2, y: mid)
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().strokeBorder(Theme.foreground(0.55), lineWidth: 1.5))
                    .frame(width: dot, height: dot)
                    .position(x: dot / 2, y: mid)
                Circle()
                    .fill(Theme.foreground)
                    .frame(width: dot, height: dot)
                    .position(x: width - dot / 2, y: mid)
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().strokeBorder(Theme.foreground, lineWidth: 3))
                    .background {
                        if ringHalo { Circle().fill(Theme.foreground(0.08)).padding(-4) }
                    }
                    .frame(width: ring, height: ring)
                    .position(x: x, y: mid)
            }
        }
    }
}

/// The areas or quests to go through, as tiles: the current one in an ink ring with its name, the rest quiet.
struct StepTiles: View {
    struct Tile: Hashable {
        let id: String
        let name: String
        /// A goal icon, or nil for a number.
        let icon: String?
    }

    let tiles: [Tile]
    let current: Int
    var showsCount = true

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if index == current {
                    HStack(spacing: 8) {
                        mark(tile, index: index, current: true)
                        Text(tile.name).font(.app(13, .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 12)
                    .frame(height: 36)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground, lineWidth: 1.5))
                } else {
                    mark(tile, index: index, current: false)
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
                        .help(tile.name)
                }
            }
            if showsCount {
                Text("\(current + 1) of \(tiles.count)").appText(.xs).monospacedDigit().foregroundStyle(Theme.muted).padding(.leading, 4)
            }
        }
    }

    @ViewBuilder private func mark(_ tile: Tile, index: Int, current: Bool) -> some View {
        if let icon = tile.icon {
            if current {
                AreaTile(icon: icon, size: 26)
            } else {
                GoalIconImage(name: icon, size: 16).foregroundStyle(Theme.muted)
            }
        } else if current {
            Text("\(index + 1)")
                .font(.app(11, .semibold)).monospacedDigit()
                .foregroundStyle(Theme.background)
                .frame(width: 24, height: 24)
                .background(Theme.foreground, in: .rect(cornerRadius: 8))
        } else {
            Text("\(index + 1)").font(.app(12, .semibold)).monospacedDigit().foregroundStyle(Theme.muted)
        }
    }
}
