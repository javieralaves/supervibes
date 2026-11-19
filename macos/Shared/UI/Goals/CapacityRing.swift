import SwiftUI

/*
 * Time planned against time protected, as a chunky ring that fills clockwise from the top, like an
 * activity ring. Each lap is shaded along its length, so it reads as one stroke going round.
 *
 * - Under capacity: the goal's colour, 18% deeper where it starts, on a 20% tint of it.
 * - Over capacity: amber. The first lap runs from deep amber to amber and closes; the second
 *   carries on from amber to bright, ending at a round tip that casts a small shadow forward onto
 *   the lap beneath it. It stops just short of a second full lap.
 * - Nothing protected: a dashed empty ring.
 *
 * Matches CapacityRing in supervibes-design (components/supervibes/capacity-ring.tsx), which draws
 * segments only because SVG has no angular gradient.
 */
struct CapacityRing: View {
    let planned: Int
    let protected: Int
    /// The goal's colour key.
    let color: String
    var size: CGFloat = 16
    /// Ring thickness; about a fifth of the size by default.
    var stroke: CGFloat?

    private var width: CGFloat { stroke ?? max(3, (size * 0.2).rounded()) }
    private var radius: CGFloat { (size - width) / 2 }
    /// Turns of the ring: where planned time ends.
    private var end: Double { protected > 0 ? Double(planned) / Double(protected) : 0 }

    var body: some View {
        ZStack {
            if protected <= 0 {
                let dash = max(1.5, size / 10)
                Circle()
                    .inset(by: width / 2)
                    .stroke(Theme.foreground(0.25), style: StrokeStyle(lineWidth: max(1.5, width * 0.5), dash: [dash, dash]))
            } else if end <= 1 {
                under
            } else {
                over
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Under capacity

    @ViewBuilder private var under: some View {
        let goal = GoalPalette.color(color)
        let deep = goal.mix(with: .black, by: 0.18, in: .perceptual)
        Circle().inset(by: width / 2).stroke(goal.opacity(0.2), lineWidth: width)
        if end > 0 {
            cap(at: 0, deep)
            arc(from: 0, to: end, deep, goal)
            cap(at: end, goal)
        }
    }

    // MARK: Over capacity

    @ViewBuilder private var over: some View {
        // A second lap is as far as it goes.
        let lap = min(end - 1, 0.97)
        let angle = 2 * Double.pi * lap
        // The shadow falls ahead of the tip, the way it's heading.
        let push = width * 0.22
        // The first lap, closed: deep where it starts, amber by the time it's round.
        cap(at: 0, Theme.amberDeep)
        arc(from: 0, to: 1, Theme.amberDeep, Theme.amber)
        // The tip, casting its shadow onto the first lap, kept to the ring's own band.
        cap(at: lap, Theme.amberBright)
            .shadow(color: .black.opacity(0.55), radius: width * 0.35, x: cos(angle) * push, y: sin(angle) * push)
            .mask(Circle().inset(by: width / 2).stroke(lineWidth: width))
        // The second lap, from amber to bright, over the tip's back half so only its front casts a shadow.
        cap(at: 0, Theme.amber)
        arc(from: 0, to: lap, Theme.amber, Theme.amberBright)
        cap(at: lap, Theme.amberBright)
    }

    // MARK: Pieces

    /// An arc from `from` to `to` (turns, clockwise from the top), its colour moving from `start` to `end` along it.
    private func arc(from: Double, to: Double, _ start: Color, _ end: Color) -> some View {
        let r = radius
        let center = CGPoint(x: size / 2, y: size / 2)
        return Path { path in
            path.addArc(center: center, radius: r, startAngle: .degrees(-90 + 360 * from), endAngle: .degrees(-90 + 360 * to), clockwise: false)
        }
        .stroke(
            AngularGradient(
                stops: [.init(color: start, location: from), .init(color: end, location: to)],
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
            ),
            style: StrokeStyle(lineWidth: width, lineCap: .butt)
        )
    }

    /// A round end: a dot the ring's width, `turn` of the way round.
    private func cap(at turn: Double, _ color: Color) -> some View {
        let angle = 2 * Double.pi * turn
        return Circle()
            .fill(color)
            .frame(width: width, height: width)
            .position(x: size / 2 + radius * sin(angle), y: size / 2 - radius * cos(angle))
    }
}

#Preview("Capacity rings") {
    HStack(spacing: 16) {
        ForEach([(0, 120), (45, 120), (120, 120), (200, 120), (400, 120), (60, 0)], id: \.0) { planned, protected in
            VStack(spacing: 8) {
                CapacityRing(planned: planned, protected: protected, color: "sky")
                CapacityRing(planned: planned, protected: protected, color: "sky", size: 52, stroke: 9)
            }
        }
    }
    .padding(24)
    .background(Theme.background)
}
