import SwiftUI

/// Step 3: how far ahead to look. Three ways, as cards in the middle of the window, with what's on the plate floating
/// around them. With a lot on the plate, it's about what can wait, and the next few months is suggested; with a little,
/// it's about what to do with the room, and stepping back is.
struct FirstRunWhatMatters: View {
    let plate: SortedPlate
    /// The season's last day, for "until February".
    let seasonEnd: Date
    var hovered: FirstRunChoice?
    /// Why the way chosen couldn't open.
    var error: String?
    let onBack: () -> Void
    let onChoose: (FirstRunChoice) -> Void

    private var month: String {
        seasonEnd.formatted(.dateTime.month(.wide).locale(Locale(identifier: "en_US")))
    }

    private struct Choice {
        let id: FirstRunChoice
        let title: String
        let body: String
        let time: String
    }

    private var choices: [Choice] {
        if plate.isHeavy {
            return [
                Choice(id: .week, title: "Just this week", body: "Pick the few things that get time in the next seven days. The rest waits in Later: off your mind, not lost.", time: "2 min"),
                Choice(id: .season, title: "The next few months", body: "Pick up to three to focus on until \(month). The rest can wait for next season, so you carry less.", time: "5 min"),
                Choice(id: .stepBack, title: "Step back first", body: "Look at where each part of your life is and where you want it, so you know what’s worth carrying.", time: "30–60 min"),
            ]
        }
        return [
            Choice(id: .week, title: "Just this week", body: "Give these their time in the next seven days, and keep the rest of your week open.", time: "2 min"),
            Choice(id: .season, title: "The next few months", body: "Decide what these grow into by \(month), and what else deserves the room you have.", time: "5 min"),
            Choice(id: .stepBack, title: "Step back first", body: "With room to spare, look at each part of your life and see what’s worth taking on next.", time: "30–60 min"),
        ]
    }

    private var suggested: FirstRunChoice { plate.isHeavy ? .season : .stepBack }

    var body: some View {
        FirstRunFlow(
            step: 2,
            eyebrow: "What matters",
            title: plate.isHeavy ? "That’s a lot to carry at once" : "You’ve got room to move",
            subtitle: plate.isHeavy
                ? "Most of it doesn’t need your time right now. Choose how far ahead to look; you can always look further later."
                : "Just a few things on your plate, and time for them. Choose how far ahead to look, and what to do with the room.",
            centered: true,
            headerTop: 62
        ) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(choices, id: \.id) { choice in
                    ChoiceCard(
                        title: choice.title, text: choice.body, time: choice.time,
                        suggested: choice.id == suggested, hovered: hovered == choice.id,
                        art: art(choice.id)
                    ) { onChoose(choice.id) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 860)
            .padding(.top, 32)
        } footer: {
            FlowButton(title: "Back", action: onBack)
            Spacer()
            if let error {
                Text(error).appText(.sm).foregroundStyle(StatusTone.text(.offTrack))
            } else {
                Text("Whichever you choose, you’ll plan your week next").appText(.sm).foregroundStyle(Theme.muted)
            }
        } backdrop: {
            FloatingPlate(items: plate.items)
        }
    }

    @ViewBuilder private func art(_ choice: FirstRunChoice) -> some View {
        switch choice {
        case .week: WeekArt(fill: plate.isHeavy ? [3, 2, 3, 2, 3, 1, 0] : [1, 0, 1, 0, 1, 0, 0])
        case .season: TracksArt()
        case .stepBack: StepBackArt()
        }
    }
}

/// A way ahead: its art, its name, what it does for you, and how long it takes. Lifts and rings in ink on hover.
private struct ChoiceCard<Art: View>: View {
    let title: String
    let text: String
    let time: String
    let suggested: Bool
    var hovered = false
    let art: Art
    let action: () -> Void
    @State private var isHovered = false

    private var lifted: Bool { hovered || isHovered }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    art.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if suggested {
                        Text("Suggested")
                            .font(.app(11, .semibold))
                            .foregroundStyle(Theme.background)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Theme.foreground, in: .capsule)
                            .padding(10)
                    }
                }
                .frame(height: 148)
                .background(Theme.foreground(0.035), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.app(16, .semibold)).tracking(-0.16).foregroundStyle(Theme.foreground)
                    Text(text)
                        .font(.app(12.5)).lineSpacing(2)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    Spacer(minLength: 16)
                    HStack {
                        HStack(spacing: 4) {
                            Icon.clock.image(size: 13)
                            Text(time).font(.app(11.5, .medium)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.muted)
                        Spacer()
                        Icon.arrowRight.image(size: 14)
                            .foregroundStyle(lifted ? Theme.background : Theme.muted)
                            .frame(width: 28, height: 28)
                            .background(lifted ? Theme.foreground : Theme.card, in: .circle)
                            .overlay { if !lifted { Circle().strokeBorder(Theme.cardBorder) } }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.card.opacity(0.92))
                    .shadow(color: .black.opacity(lifted ? 0.18 : 0.06), radius: lifted ? 22 : 10, y: lifted ? 18 : 6)
            }
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(lifted ? Theme.foreground : Theme.cardBorder, lineWidth: lifted ? 1.5 : 1))
            .offset(y: lifted ? -4 : 0)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: lifted)
    }
}

/// What's on the plate, scattered around the choices: a lot to carry, at a glance. Each sits in the window's margins
/// beside the choices or in the strip under them, tilted a little, fainter the further back it is, so none covers a
/// choice whatever the window's size.
private struct FloatingPlate: View {
    let items: [PlateItem]

    private enum Spot {
        /// From the window's left edge, at a share of its height.
        case leading(CGFloat, CGFloat)
        /// From the window's right edge, at a share of its height.
        case trailing(CGFloat, CGFloat)
        /// From the middle, sideways, and up from the bottom.
        case below(CGFloat, CGFloat)
    }

    /// Beside the choices there's about 200 points either side, so chips there stay narrow and near the edge; in the
    /// top corners, beside the title, there's room for a whole name.
    private static let spots: [(spot: Spot, tilt: Double, depth: Int, width: CGFloat)] = [
        (.leading(36, 0.19), -4, 0, 280), (.trailing(48, 0.2), 3, 1, 280), (.leading(18, 0.5), 5, 0, 180), (.trailing(16, 0.42), -4, 2, 180),
        (.leading(28, 0.68), -3, 1, 170), (.trailing(30, 0.6), 2, 0, 170), (.below(-300, 34), -2, 1, 260), (.below(110, 26), 4, 2, 260),
        (.below(380, 44), -3, 1, 260), (.trailing(120, 0.3), 4, 2, 240),
    ]

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(items.prefix(Self.spots.count).enumerated()), id: \.element.id) { index, item in
                let spot = Self.spots[index]
                chip(item, maxWidth: spot.width)
                    .rotationEffect(.degrees(spot.tilt))
                    .scaleEffect([1, 0.92, 0.84][spot.depth])
                    .opacity([1, 0.75, 0.5][spot.depth])
                    .blur(radius: [0, 0.4, 1.2][spot.depth])
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment(spot.spot))
                    .offset(offset(spot.spot, in: geometry.size))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func chip(_ item: PlateItem, maxWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
            Text(item.title).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 36)
        .frame(maxWidth: maxWidth)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        .fixedSize()
    }

    private func alignment(_ spot: Spot) -> Alignment {
        switch spot {
        case .leading: .topLeading
        case .trailing: .topTrailing
        case .below: .bottom
        }
    }

    private func offset(_ spot: Spot, in size: CGSize) -> CGSize {
        switch spot {
        case .leading(let x, let y): CGSize(width: x, height: size.height * y)
        case .trailing(let x, let y): CGSize(width: -x, height: size.height * y)
        case .below(let x, let up): CGSize(width: x, height: -up)
        }
    }
}

// MARK: - The choices' art

/// A week as seven days, each holding a few blocks.
private struct WeekArt: View {
    let fill: [Int]
    private let colors = ["violet", "sky", "amber", "green"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(fill.enumerated()), id: \.offset) { day, count in
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    ForEach(0..<count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(GoalPalette.color(colors[(day + index) % colors.count]).opacity(0.7))
                            .frame(height: 12)
                    }
                }
                .padding(4)
                .frame(width: 24, height: 76)
                .background(Theme.card, in: .rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
            }
        }
    }
}

/// Three quest tracks, from a hollow dot to a solid one, the middle one in ink.
private struct TracksArt: View {
    private let tracks: [(from: CGFloat, to: CGFloat, ink: Bool)] = [(0.18, 0.92, false), (0.06, 0.8, true), (0.28, 1, false)]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 48
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                let y = geometry.size.height / 2 + CGFloat(index - 1) * 34
                let from = 24 + width * track.from
                let to = 24 + width * track.to
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: from + 6, y: y))
                        path.addLine(to: CGPoint(x: to - 6, y: y))
                    }
                    .stroke(Theme.foreground(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                    Circle().fill(Theme.card).overlay(Circle().strokeBorder(Theme.foreground(0.5), lineWidth: 1.5))
                        .frame(width: 11, height: 11).position(x: from, y: y)
                    Circle().fill(Theme.foreground).frame(width: 11, height: 11).position(x: to, y: y)
                }
                .opacity(track.ink ? 1 : 0.4)
            }
        }
    }
}

/// Stepping back: a few parts of life around a compass.
private struct StepBackArt: View {
    private let icons = ["FavouriteIcon", "Briefcase01Icon", "Home01Icon", "Wallet01Icon", "Agreement01Icon", "Mortarboard01Icon"]

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.foreground(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: 104, height: 104)
            Icon.compass.image(size: 20).foregroundStyle(Theme.foreground)
                .frame(width: 40, height: 40)
                .background(Theme.card, in: .circle)
                .overlay(Circle().strokeBorder(Theme.cardBorder))
            ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                GoalIconImage(name: icon, size: 13)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 26, height: 26)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.cardBorder))
                    .offset(offset(for: index))
            }
        }
    }

    /// Where icon `index` sits on the ring, starting at the top. Spelled out with types so the
    /// Release build's type checker doesn't time out on the body.
    private func offset(for index: Int) -> CGSize {
        let angle: Double = Double(index) / Double(icons.count) * 2 * Double.pi - Double.pi / 2
        return CGSize(width: cos(angle) * 52, height: sin(angle) * 52)
    }
}
