import SwiftUI

/// Life's season panel when no season is running: an invitation in the place the season will take, so the page's
/// order doesn't change (the design's NoSeasonPanel in supervibes-design, seasons-quests.tsx). A question, one line,
/// the way in, and a drawing of what a season holds: a few quest tracks, from a hollow dot to a solid one.
///
/// With a season being set up, it says so and picks up where it was; with one just ended, it says that first.
struct NoSeasonPanel: View {
    /// A season being set up, to carry on with.
    var draft: Season?
    /// One that ended in the last few weeks.
    var ended: Season?
    var isBusy = false
    var error: String?
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Icon.season.image(size: 15)
                    Text(eyebrow).font(.app(13, .medium))
                }
                .foregroundStyle(Theme.muted)
                Text(draft == nil ? "What will you move next?" : "\(draft!.name) is waiting for you")
                    .font(.app(32, .semibold))
                    .tracking(-0.03 * 32)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 4)
                Text(draft == nil
                    ? "Pick a few gaps to close over the next 13 weeks."
                    : "Pick up where you left off: \(draft!.range).")
                    .font(.app(15))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                HStack(spacing: 12) {
                    StartButton(title: draft == nil ? "Start a season" : "Continue setting up", isBusy: isBusy, action: onStart)
                    if let error {
                        Text(error).appText(.xs).foregroundStyle(Theme.danger)
                    }
                }
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            QuestTracksArt()
        }
        .padding(.leading, 32)
        .padding(.trailing, 48)
        .padding(.vertical, 36)
        .background(alignment: .trailing) {
            // A soft wash behind the drawing, so it sits in light rather than on the card's edge.
            EllipticalGradient(colors: [Theme.foreground(0.04), .clear], center: UnitPoint(x: 0.6, y: 0.5), startRadiusFraction: 0, endRadiusFraction: 0.6)
                .frame(width: 520)
        }
        .raisedPanel()
    }

    private var eyebrow: String {
        if let draft { return "\(draft.name), being set up" }
        if let ended { return "\(ended.name) ended \(ended.endLabel)" }
        return "No season yet"
    }
}

/// Three quest tracks, staggered and faint, the middle one in ink: a few gaps to close, one of them first.
struct QuestTracksArt: View {
    private let tracks: [(y: CGFloat, from: CGFloat, to: CGFloat, ink: Bool)] = [
        (34, 64, 312, false),
        (84, 24, 268, true),
        (134, 104, 352, false),
    ]

    var body: some View {
        Canvas { context, _ in
            for track in tracks {
                var layer = context
                layer.opacity = track.ink ? 1 : 0.4
                var line = Path()
                line.move(to: CGPoint(x: track.from + 7, y: track.y))
                line.addLine(to: CGPoint(x: track.to - 7, y: track.y))
                layer.stroke(line, with: .color(Theme.foreground(0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                let hollow = Path(ellipseIn: CGRect(x: track.from - 6, y: track.y - 6, width: 12, height: 12))
                layer.fill(hollow, with: .color(Theme.card))
                layer.stroke(hollow, with: .color(Theme.foreground(0.5)), lineWidth: 1.5)
                layer.fill(Path(ellipseIn: CGRect(x: track.to - 6, y: track.y - 6, width: 12, height: 12)), with: .color(Theme.foreground))
            }
        }
        .frame(width: 376, height: 168)
        .accessibilityHidden(true)
    }
}

/// `h-9 rounded-xl bg-foreground px-4 text-sm font-medium text-background`.
private struct StartButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).appText(.sm, .medium).opacity(isBusy ? 0 : 1)
                if isBusy { Spinner(size: 14) }
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Theme.foreground, in: .rect(cornerRadius: 12))
            .opacity(isHovered && !isBusy ? 0.9 : 1)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .inactive(isBusy)
        .onHover { isHovered = $0 }
    }
}

extension View {
    /// The season's raised panel: `rounded-[20px] bg-card`, ringed, with a soft long shadow under it.
    func raisedPanel(radius: CGFloat = 20) -> some View {
        clipShape(.rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.cardBorder))
            .background {
                ZStack {
                    // The long shadow comes from a smaller shape tucked behind, so it shows only below the panel
                    // (`0 16px 40px -20px`), never as a haze above it.
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Theme.card)
                        .padding(.horizontal, 20)
                        .padding(.top, 40)
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 16)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Theme.card)
                        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                }
            }
    }
}

#Preview("No season") {
    NoSeasonPanel(onStart: {})
        .padding(32).frame(width: 1088).background(Theme.background)
}

#Preview("Being set up") {
    NoSeasonPanel(draft: Fixtures.draftSeason, onStart: {})
        .padding(32).frame(width: 1088).background(Theme.background)
}
