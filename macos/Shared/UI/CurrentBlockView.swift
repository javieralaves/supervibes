import SwiftUI

/// The block happening right now: what it's for, when it ends, and how far through it you are.
/// Shared by the menu bar popover and the widget.
struct CurrentBlockView: View {
    let block: Block
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Block.remaining(minutes: block.minutesLeft(at: now))) left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    GoalDot(tint: block.tint)
                    Text(block.goal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ProgressView(value: block.progress(at: now))
                .progressViewStyle(.linear)
                .tint(block.tint?.color ?? .accentColor)

            Text(Block.timeRange(block))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A small dot in the goal's colour.
struct GoalDot: View {
    let tint: Tint?

    var body: some View {
        Circle()
            .fill(tint?.color ?? Color.secondary)
            .frame(width: 7, height: 7)
    }
}

/// Shown where the current block would be when nothing is scheduled right now: what's next, if
/// anything is, or a nudge to sign in.
struct NoBlockView: View {
    var next: Block?
    var signedIn = true
    /// The menu bar lists what's next right below, so it only says until when you're free.
    var nextIsListed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if !signedIn {
                Text("Not signed in")
                    .font(.headline)
                Text("Open Supervibes to see your blocks here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let next {
                Text("Free until \(next.start.formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
                if !nextIsListed {
                    HStack(spacing: 6) {
                        GoalDot(tint: next.tint)
                        Text("Next: \(next.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("Nothing scheduled")
                    .font(.headline)
                Text("No more blocks today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
