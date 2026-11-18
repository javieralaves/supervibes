import SwiftUI

/// The popover under the menu bar item: the current block, what's next, and a way into the app.
struct MenuBarContent: View {
    let current: Block?
    let upcoming: [Block]
    let now: Date
    var isSignedIn = true
    var onOpen: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isSignedIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not signed in")
                        .font(.headline)
                    Text("Sign in to see today's blocks here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                if let current {
                    CurrentBlockView(block: current, now: now)
                } else {
                    NoBlockView()
                }

                if !upcoming.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(upcoming) { block in
                            UpcomingRow(block: block)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(isSignedIn ? "Open Supervibes" : "Sign In…", action: onOpen)
                    .keyboardShortcut("o")
                Spacer()
                Button("Quit", action: onQuit)
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct UpcomingRow: View {
    let block: Block

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(block.start.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    GoalDot(tint: block.tint)
                    Text(block.goal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
