import SwiftUI

/// The first thing someone new sees: the mark, a welcome, what Supervibes does for them in a line, and the way through
/// as four illustrated tiles on a numbered track, every step drawn alike.
struct FirstRunWelcome: View {
    let firstName: String
    let onStart: () -> Void

    private struct Tile {
        let title: String
        let line: String
        let time: String
    }

    private let tiles = [
        Tile(title: "Empty your plate", line: "However messy. Type it all out.", time: "2 min"),
        Tile(title: "See it sorted", line: "Projects, practices, and the parts of life they sit in.", time: "2 min"),
        Tile(title: "Choose what matters", line: "This week, a few months, or a proper step back.", time: "2 min or more"),
        Tile(title: "Plan your week", line: "What matters, on your calendar, so it starts moving.", time: "2 min"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            SuperfocusLogo(size: 44)
            Text("Welcome, \(firstName)")
                .font(.app(13, .medium)).foregroundStyle(Theme.muted)
                .padding(.top, 28)
            Text("Let’s start with what’s going on")
                .font(.app(38, .semibold)).tracking(-0.035 * 38)
                .foregroundStyle(Theme.foreground)
                .padding(.top, 4)
            Text("Supervibes helps you put your time where it matters. In about ten minutes, everything’s in one place and your week is planned around it.")
                .font(.app(15.2)).lineSpacing(3.5)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 16) {
                track
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        card(tile, art: art(index))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 800)
            .padding(.top, 40)

            FlowButton(title: "Let’s go", primary: true, action: onStart)
                .padding(.top, 40)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    /// A dashed line through each step's number, each hollow.
    private var track: some View {
        HStack(spacing: 12) {
            ForEach(0..<tiles.count, id: \.self) { index in
                Text("\(index + 1)")
                    .font(.app(11.5, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24)
                    .background(Theme.background, in: .circle)
                    .overlay { Circle().strokeBorder(Theme.foreground(0.3), lineWidth: 1.5) }
                    .frame(maxWidth: .infinity)
            }
        }
        .background {
            GeometryReader { geometry in
                let inset = geometry.size.width / CGFloat(tiles.count * 2)
                Path { path in
                    path.move(to: CGPoint(x: inset, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width - inset, y: geometry.size.height / 2))
                }
                .stroke(Theme.foreground(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
        }
    }

    private func card(_ tile: Tile, art: some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack { art }
                .frame(maxWidth: .infinity)
                .frame(height: 108)
                .background(Theme.background, in: .rect(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(tile.title).font(.app(14, .semibold)).tracking(-0.14).foregroundStyle(Theme.foreground)
                Text(tile.line)
                    .font(.app(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Icon.clock.image(size: 13)
                    Text(tile.time).font(.app(11.5, .medium)).monospacedDigit()
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    @ViewBuilder private func art(_ index: Int) -> some View {
        switch index {
        case 0: PlateArt()
        case 1: SortedArt()
        case 2: MattersArt()
        default: SessionArt()
        }
    }
}

// MARK: - The tiles' art

/// Step 1 in miniature: a few lines typed in, the caret after the last.
private struct PlateArt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array([0.82, 0.58, 0.72, 0.4].enumerated()), id: \.offset) { index, share in
                HStack(spacing: 3) {
                    GeometryReader { geometry in
                        Capsule().fill(Theme.foreground(0.14)).frame(width: geometry.size.width * share, height: 5)
                    }
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        if index == 3 {
                            GeometryReader { geometry in
                                Rectangle().fill(Theme.foreground).frame(width: 1.5, height: 12)
                                    .offset(x: geometry.size.width * share + 3, y: -3.5)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).strokeBorder(Theme.cardBorder))
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

/// Step 2 in miniature: two areas, each holding what was sorted into it.
private struct SortedArt: View {
    private let columns = [[("Rocket01Icon", "violet"), ("UserAdd01Icon", "sky")], [("RunningShoesIcon", "green"), ("LanguageSkillIcon", "indigo")]]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(Theme.foreground(0.25)).frame(width: 28, height: 4)
                    ForEach(Array(column.enumerated()), id: \.offset) { _, badge in
                        HStack(spacing: 6) {
                            GoalBadge(icon: badge.0, color: badge.1, size: .micro)
                            Capsule().fill(Theme.foreground(0.12)).frame(height: 4)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
            }
        }
        .padding(16)
    }
}

/// Step 3 in miniature: three ways ahead, the middle one chosen.
private struct MattersArt: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let chosen = index == 1
                VStack(alignment: .leading, spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(Theme.background)
                        if chosen {
                            VStack(spacing: 6) {
                                track(width: 26)
                                track(width: 22)
                            }
                        }
                    }
                    .frame(height: 30)
                    Capsule().fill(Theme.foreground(0.25)).frame(width: 26, height: 3)
                    Capsule().fill(Theme.foreground(0.12)).frame(width: 20, height: 3)
                }
                .padding(4)
                .frame(width: 40, height: 64, alignment: .top)
                .background(Theme.card, in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Theme.foreground : Theme.cardBorder, lineWidth: chosen ? 1.5 : 1))
                .opacity(chosen ? 1 : 0.7)
                .offset(y: chosen ? -4 : 0)
                .shadow(color: .black.opacity(chosen ? 0.15 : 0), radius: 6, y: 5)
            }
        }
    }

    private func track(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: width - 5, y: 0.5))
            }
            .stroke(Theme.foreground(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            .frame(width: width - 5, height: 1)
            Circle().fill(Theme.foreground).frame(width: 5, height: 5)
        }
    }
}

/// Step 4 in miniature: a few days of calendar, one session on it in its project's colour.
private struct SessionArt: View {
    private let events: [[(top: CGFloat, height: CGFloat)]] = [
        [(10, 12), (52, 20)],
        [(8, 10)],
        [(22, 26), (66, 10)],
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, day in
                ZStack(alignment: .top) {
                    ForEach(Array(day.enumerated()), id: \.offset) { _, event in
                        RoundedRectangle(cornerRadius: 3).fill(Theme.foreground(0.07))
                            .frame(height: event.height)
                            .padding(.horizontal, 4)
                            .offset(y: event.top)
                    }
                    if index == 1 {
                        HStack(spacing: 3) {
                            Capsule().fill(GoalPalette.color("violet")).frame(width: 2)
                            Capsule().fill(GoalPalette.color("violet").opacity(0.6)).frame(width: 20, height: 3).frame(maxHeight: .infinity, alignment: .top).padding(.top, 2)
                            Spacer(minLength: 0)
                        }
                        .padding(3)
                        .frame(height: 34)
                        .background(GoalPalette.tintBackground("violet"), in: .rect(cornerRadius: 4))
                        .shadow(color: GoalPalette.color("violet").opacity(0.35), radius: 5, y: 4)
                        .padding(.horizontal, 4)
                        .offset(y: 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .leading) { if index > 0 { Rectangle().fill(Theme.cardBorder).frame(width: 1) } }
            }
        }
        .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).strokeBorder(Theme.cardBorder))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}
