import SwiftUI

/*
 * How an area looks wherever it shows. Areas carry no colour of their own, so goals keep theirs: an area is its icon
 * on a neutral tile, drawn in the text colour.
 */

/// An area's icon on a neutral tile, with a hairline border. 32 on cards, 48 on its page.
struct AreaTile: View {
    /// A Hugeicons name from GoalPalette.
    let icon: String
    var size: CGFloat = 32

    private var radius: CGFloat { (size * 0.3).rounded() }

    var body: some View {
        GoalIconImage(name: icon, size: (size * 0.5).rounded())
            .foregroundStyle(Theme.foreground)
            .frame(width: size, height: size)
            .background(Theme.foreground(0.06), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.cardBorder))
    }
}

/// An area's status as a dot and the word, as a goal's StatusText; "No status yet" without one.
struct AreaStatusText: View {
    let status: GoalStatus?

    var body: some View {
        if let status {
            HStack(spacing: 6) {
                Circle().fill(StatusTone.dot(status)).frame(width: 6, height: 6)
                Text(areaStatusLabel(status)).appText(.xs, .medium)
            }
            .foregroundStyle(StatusTone.text(status))
        } else {
            Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
        }
    }
}

/// An area's name with its icon, small and muted: where a goal sits, on its card and its page.
struct AreaLabel: View {
    let name: String
    let icon: String
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            GoalIconImage(name: icon, size: size)
            Text(name).lineLimit(1)
        }
    }
}
