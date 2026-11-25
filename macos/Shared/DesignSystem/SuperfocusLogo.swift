import SwiftUI

/// The Superfocus mark: a rounded square with a square hole, drawn even-odd. Its path is Superfocus's own
/// (`SuperfocusLogo` in the Superfocus design system), on a 56 × 56 box, scaled to fit the rect it's given.
struct SuperfocusLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 56
        let origin = CGPoint(x: rect.midX - 28 * scale, y: rect.midY - 28 * scale)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }

        var path = Path()
        // The outer rounded square.
        path.move(to: p(32.9004, 3.5))
        path.addCurve(to: p(45.8115, 4.83496), control1: p(39.7608, 3.5), control2: p(43.1912, 3.49982))
        path.addCurve(to: p(51.165, 10.1885), control1: p(48.1165, 6.00941), control2: p(49.9906, 7.88351))
        path.addCurve(to: p(52.5, 23.0996), control1: p(52.5002, 12.8088), control2: p(52.5, 16.2392))
        path.addLine(to: p(52.5, 32.9004))
        path.addCurve(to: p(51.165, 45.8115), control1: p(52.5, 39.7608), control2: p(52.5002, 43.1912))
        path.addCurve(to: p(45.8115, 51.165), control1: p(49.9906, 48.1165), control2: p(48.1165, 49.9906))
        path.addCurve(to: p(32.9004, 52.5), control1: p(43.1912, 52.5002), control2: p(39.7608, 52.5))
        path.addLine(to: p(23.0996, 52.5))
        path.addCurve(to: p(10.1885, 51.165), control1: p(16.2392, 52.5), control2: p(12.8088, 52.5002))
        path.addCurve(to: p(4.83496, 45.8115), control1: p(7.88351, 49.9906), control2: p(6.00941, 48.1165))
        path.addCurve(to: p(3.5, 32.9004), control1: p(3.49982, 43.1912), control2: p(3.5, 39.7608))
        path.addLine(to: p(3.5, 23.0996))
        path.addCurve(to: p(4.83496, 10.1885), control1: p(3.5, 16.2392), control2: p(3.49982, 12.8088))
        path.addCurve(to: p(10.1885, 4.83496), control1: p(6.00941, 7.88351), control2: p(7.88351, 6.00941))
        path.addCurve(to: p(23.0996, 3.5), control1: p(12.8088, 3.49982), control2: p(16.2392, 3.5))
        path.closeSubpath()
        // The square hole.
        path.move(to: p(28, 18.8125))
        path.addCurve(to: p(22.5938, 19.2783), control1: p(25.1464, 18.8125), control2: p(23.7193, 18.8122))
        path.addCurve(to: p(19.2783, 22.5938), control1: p(21.093, 19.9), control2: p(19.9, 21.093))
        path.addCurve(to: p(18.8125, 28), control1: p(18.8122, 23.7193), control2: p(18.8125, 25.1464))
        path.addCurve(to: p(19.2783, 33.4063), control1: p(18.8125, 30.8536), control2: p(18.8122, 32.2807))
        path.addCurve(to: p(22.5938, 36.7217), control1: p(19.9, 34.907), control2: p(21.093, 36.1))
        path.addCurve(to: p(28, 37.1875), control1: p(23.7193, 37.1878), control2: p(25.1464, 37.1875))
        path.addCurve(to: p(33.4063, 36.7217), control1: p(30.8536, 37.1875), control2: p(32.2807, 37.1878))
        path.addCurve(to: p(36.7217, 33.4063), control1: p(34.907, 36.1), control2: p(36.1, 34.907))
        path.addCurve(to: p(37.1875, 28), control1: p(37.1878, 32.2807), control2: p(37.1875, 30.8536))
        path.addCurve(to: p(36.7217, 22.5938), control1: p(37.1875, 25.1464), control2: p(37.1878, 23.7193))
        path.addCurve(to: p(33.4063, 19.2783), control1: p(36.1, 21.093), control2: p(34.907, 19.9))
        path.addCurve(to: p(28, 18.8125), control1: p(32.2807, 18.8122), control2: p(30.8536, 18.8125))
        path.closeSubpath()
        return path
    }
}

/// The Superfocus mark in its soft gradient: the goal colours amber, coral, pink, violet and sky, top left to bottom
/// right, each with a quarter of the foreground ink mixed in, so it's a touch deeper in light and paler in dark.
struct SuperfocusLogo: View {
    var size: CGFloat = 22

    private static let stops = ["amber", "coral", "pink", "violet", "sky"]
    private static let inkShare = 0.25

    private var gradient: LinearGradient {
        LinearGradient(
            colors: Self.stops.map { GoalPalette.color($0).mix(with: Theme.foreground, by: Self.inkShare, in: .perceptual) },
            // The web's gradient runs from (4, 4) to (52, 52) on the mark's 56 box, just inside its corners.
            startPoint: UnitPoint(x: 4 / 56, y: 4 / 56),
            endPoint: UnitPoint(x: 52 / 56, y: 52 / 56)
        )
    }

    var body: some View {
        SuperfocusLogoShape()
            .fill(gradient, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel("Superfocus")
    }
}

#Preview("Superfocus mark") {
    HStack(spacing: 24) {
        SuperfocusLogo(size: 22)
        SuperfocusLogo(size: 56)
        SuperfocusLogo(size: 120)
    }
    .padding(32)
    .background(Theme.shell)
}
