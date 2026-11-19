import SwiftUI

/// The popover under the menu bar item: the current block and what it's for, what's next, and a
/// way into the app. Right before a session is when its aim is clearest, so a block starting soon
/// gets the same place to set it as the one under way.
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
    /// Setting a session's aim and planning it; nil where nothing can be saved (previews, snapshots).
    var sessionActions: SessionPlanActions?
    var onOpen: () -> Void = {}

    /// How soon a session counts as about to start.
    static let soonLead: TimeInterval = 15 * 60

    /// With nothing under way, the next session if it starts within `soonLead`.
    private var soon: Block? {
        guard current == nil, let next = upcoming.first, next.start.timeIntervalSince(now) <= Self.soonLead else { return nil }
        return next
    }
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
                    Divider()
                    SessionPlanView(block: current, error: taskError, actions: sessionActions, onSetTaskDone: onSetTaskDone)
                        .id(current.id)
                } else if let soon {
                    StartingSoonView(block: soon, now: now)
                    Divider()
                    SessionPlanView(block: soon, error: taskError, actions: sessionActions, onSetTaskDone: onSetTaskDone)
                        .id(soon.id)
                } else {
                    NoBlockView(next: upcoming.first, nextIsListed: true)
                }

                let later = upcoming.filter { $0.id != soon?.id }
                if !later.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(later) { block in
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

/// A session about to start, laid out like the current one: how soon, what, for which goal, and when.
private struct StartingSoonView: View {
    let block: Block
    let now: Date

    private var lead: String {
        let minutes = max(Int((block.start.timeIntervalSince(now) / 60).rounded(.up)), 0)
        return minutes == 0 ? "starting now" : "in \(Block.remaining(minutes: minutes))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(lead)
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
            Text(Block.timeRange(block))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
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

#Preview("A session starting soon") {
    let now = Fixtures.referenceNow.addingTimeInterval(52 * 60)
    MenuBarContent(current: nil, upcoming: Fixtures.blocks(around: Fixtures.referenceNow).filter { $0.start > now }, now: now)
        .frame(width: 300)
}

#Preview("Nothing scheduled") {
    MenuBarContent(current: nil, upcoming: [], now: Fixtures.referenceNow).frame(width: 300)
}

#Preview("Signed out") {
    MenuBarContent(current: nil, upcoming: [], now: Fixtures.referenceNow, isSignedIn: false).frame(width: 300)
}
