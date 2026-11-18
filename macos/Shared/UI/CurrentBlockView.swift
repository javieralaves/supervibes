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
                Text(block.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: block.progress(at: now))
                .progressViewStyle(.linear)
                .tint(.accentColor)

            Text(Block.timeRange(block))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown where the current block would be when nothing is scheduled right now.
struct NoBlockView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("Nothing scheduled")
                .font(.headline)
            Text("Free time until your next block.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
