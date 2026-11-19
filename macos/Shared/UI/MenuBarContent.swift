import SwiftUI

/// The popover under the menu bar item: the current block and what it's for, what's next, and a
/// way into the app.
struct MenuBarContent: View {
    let current: Block?
    let upcoming: [Block]
    let now: Date
    var isSignedIn = true
    /// "Supervibes", or "Supervibes Dev" for Debug builds.
    var appName = "Supervibes"
    /// Why checking off a task didn't save.
    var taskError: String?
    var onSetTaskDone: (_ taskId: String, _ done: Bool) -> Void = { _, _ in }
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
                    if SessionPlanView.hasPlan(current) {
                        Divider()
                        SessionPlanView(block: current, error: taskError, onSetTaskDone: onSetTaskDone)
                            .id(current.id)
                    }
                } else {
                    NoBlockView(next: upcoming.first, nextIsListed: true)
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
                Button(isSignedIn ? "Open \(appName)" : "Sign In…", action: onOpen)
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

// Previews use the snapshot fixtures, at Fixtures.referenceNow (Wednesday Nov 18, 10:18).
#Preview("During a block") {
    let now = Fixtures.referenceNow
    MenuBarContent(current: Fixtures.current(at: now), upcoming: Fixtures.upcoming(at: now), now: now)
        .frame(width: 300)
}

#Preview("During a block with a plan") {
    let now = Fixtures.referenceNow
    MenuBarContent(current: Fixtures.planned(at: now), upcoming: Fixtures.upcoming(at: now), now: now)
        .frame(width: 300)
}

#Preview("Nothing scheduled") {
    MenuBarContent(current: nil, upcoming: [], now: Fixtures.referenceNow).frame(width: 300)
}

#Preview("Signed out") {
    MenuBarContent(current: nil, upcoming: [], now: Fixtures.referenceNow, isSignedIn: false).frame(width: 300)
}
