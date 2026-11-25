import SwiftUI

/// An area's read, shaped like a goal's progress card: its status pill, a headline and a few lines, its last 4 weeks,
/// and what the read drew on (its goals and the calendar), with a way to update it. The status is the area's own,
/// its goals' worst: the read only writes words, and only when asked.
///
/// Before the first read it says what will fill it: with no goals, how to give it something to read; with goals, a
/// button for the first read.
struct AreaReadCard: View {
    let detail: AreaDetail
    var reading = false
    var error: String?
    let now: Date
    /// Writes the read; nil when it can't be asked for here.
    var onRead: (() -> Void)?

    private var area: Area { detail.area }
    private var canRead: Bool { !detail.goals.isEmpty && onRead != nil }

    var body: some View {
        Card {
            if let read = detail.read {
                withRead(read)
            } else if detail.goals.isEmpty {
                nothingToRead
            } else {
                firstRead
            }
        }
    }

    // MARK: States

    @ViewBuilder private func withRead(_ read: AreaRead) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pill.padding(.bottom, 12)
            Text(read.headline)
                .appText(.xl, .semibold, tracking: -0.02)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(read.summary)
                .font(.app(15.2))
                .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .compositingGroup()
        .opacity(reading ? 0.5 : 1)

        weeks.padding(.top, 20).zIndex(1)

        HStack(spacing: 12) {
            HStack(spacing: 8) {
                DrewOn(goals: detail.goals.filter { read.goalIds.contains($0.id) }, calendar: read.usedCalendar)
                Text(read.createdAt.shortAgo(now: now)).appText(.xs)
            }
            // The Update button turns while it reads; without one, the footer does.
            if reading, !canRead { SpinningIcon(size: 13) }
            note
            Spacer(minLength: 0)
            if canRead, let onRead {
                ReadButton(title: "Update", reading: reading, compact: true, action: onRead)
            }
        }
        .foregroundStyle(Theme.muted)
        .padding(.top, 20)
    }

    @ViewBuilder private var firstRead: some View {
        pill.padding(.bottom, 12)
        Text("Ready for a first read")
            .appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
        Text("Supervibes will read where its projects and practices stand and your time on the calendar, and tell you here, in a few lines, how \(area.name) is going.")
            .font(.app(15.2))
            .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        weeks.padding(.top, 20).zIndex(1)
        if let onRead {
            HStack(spacing: 12) {
                ReadButton(title: "Read this area", reading: reading, action: onRead)
                note
            }
            .padding(.top, 20)
        }
    }

    /// The design's empty read: each part in its empty form, saying what will fill it.
    @ViewBuilder private var nothingToRead: some View {
        NeutralPill(title: "No read yet").padding(.bottom, 12)
        Text("Nothing to read in this area yet")
            .appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
        Text("\(area.now == nil ? "Say where it stands and give it a project or a practice." : "Give it a project or a practice.") Supervibes will read them and your time on the calendar, and tell you here, in a few lines, how it’s going.")
            .font(.app(15.2))
            .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        weeks.padding(.top, 20)
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.foreground(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 18, height: 18)
                }
            }
            Text("Not read yet").appText(.xs)
        }
        .foregroundStyle(Theme.muted)
        .padding(.top, 20)
    }

    // MARK: Parts

    /// The area's status, its goals' worst; "No status yet" until one of them has one.
    @ViewBuilder private var pill: some View {
        if let status = area.status {
            StatusPill(status: status, basis: .target, help: "The most pressing of its projects’ and practices’ statuses")
        } else {
            NeutralPill(title: "No status yet")
        }
    }

    private var weeks: some View {
        let started = detail.trajectory.contains { $0.status != nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 4 weeks")
                Spacer()
                if !started { Text("Starts with its first statuses") }
            }
            .font(.app(11)).foregroundStyle(Theme.muted)
            TrajectoryDays(
                days: detail.trajectory.map {
                    TrajectoryDay(day: $0.day, status: $0.status, basis: $0.status == nil ? nil : .target, reason: nil, carried: $0.carried)
                },
                today: detail.today
            )
        }
    }

    @ViewBuilder private var note: some View {
        if reading {
            Text("Reading its projects and practices. This takes a few seconds.").appText(.xs).foregroundStyle(Theme.muted)
        } else if let error {
            Text(error).appText(.xs).foregroundStyle(Theme.danger)
        }
    }
}

/// A pill with no status: a ringed dot and a word, on a wash.
private struct NeutralPill: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(Theme.muted, lineWidth: 1).frame(width: 6, height: 6)
            Text(title).appText(.xs, .medium)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Theme.foreground(0.06), in: .capsule)
    }
}

/// What a read drew on: its goals' badges, then the calendar.
private struct DrewOn: View {
    let goals: [Goal]
    let calendar: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(goals) { goal in
                GoalBadge(icon: goal.icon, color: goal.color, size: .micro).help(goal.title)
            }
            if calendar {
                Icon.calendar.image(size: 11)
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 18, height: 18)
                    .background(Theme.wash, in: .rect(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
                    .help("Your time on the calendar")
            }
        }
    }
}

/// `h-9 rounded-xl border px-3 text-sm font-medium`, its icon turning while the read is written; smaller beside a read.
private struct ReadButton: View {
    let title: String
    let reading: Bool
    var compact = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if reading { SpinningIcon(size: compact ? 13 : 15) } else { Icon.refresh.image(size: compact ? 13 : 15) }
                Text(reading ? "Reading…" : title).appText(compact ? .xs : .sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 28 : 36)
            .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 12).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .compositingGroup()
            .opacity(reading ? 0.6 : 1)
            .contentShape(.rect(cornerRadius: compact ? 8 : 12))
        }
        .buttonStyle(.plain)
        .inactive(reading)
        .onHover { isHovered = $0 }
        .help("Read its projects, practices and your calendar again")
    }
}

#Preview("Read") {
    AreaReadCard(detail: Fixtures.areaDetail, now: Fixtures.referenceNow, onRead: {})
        .padding(32).frame(width: 704).background(Theme.background)
}

#Preview("First read") {
    AreaReadCard(detail: Fixtures.unreadAreaDetail, now: Fixtures.referenceNow, onRead: {})
        .padding(32).frame(width: 704).background(Theme.background)
}

#Preview("Nothing to read") {
    AreaReadCard(detail: Fixtures.newAreaDetail, now: Fixtures.referenceNow, onRead: {})
        .padding(32).frame(width: 704).background(Theme.background)
}
