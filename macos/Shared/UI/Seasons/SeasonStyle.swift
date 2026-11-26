import SwiftUI

/// Where a card stands in a running season: no season running, moving one of its quests, or not part of it.
enum InSeason: Hashable, Sendable {
    case none, moving, outside

    /// A card's background: a step toward the page's for one outside the season, so the season's own stand a little
    /// forward while everything stays as readable (the design's OUT_OF_SEASON).
    var cardFill: Color { self == .outside ? Theme.card.opacity(0.55) : Theme.card }
}

extension View {
    /// The season's compass on a badge's bottom-right corner, in a small disc, when it moves one of the quests.
    func seasonMark(_ on: Bool) -> some View {
        overlay(alignment: .bottomTrailing) {
            if on {
                Icon.season.image(size: 11)
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 18, height: 18)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.cardBorder))
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                    .offset(x: 6, y: 6)
                    .help("In this season")
            }
        }
    }
}

extension Goal {
    /// Its status today: a practice's from its weeks, a project's from its latest read. Nil with none yet.
    var currentStatus: GoalStatus? {
        if let practice { return practice.status?.status }
        return latest?.status
    }
}

/// A season's weeks as a row of segments: gone by in a soft ink, this week in full, the rest faint. With `labels`,
/// its first day and its close under it.
struct SeasonWeeks: View {
    let season: Season
    var labels = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(1...max(1, season.weeks), id: \.self) { week in
                    Capsule()
                        .fill(week < season.week ? Theme.foreground(0.35) : week == season.week ? Theme.foreground : Theme.foreground(0.1))
                        .frame(height: 6)
                }
            }
            if labels {
                HStack {
                    Text(CalendarDay.shortWeekdayMonthDay(season.startsOn))
                    Spacer()
                    Text("Close · \(season.endLabel)")
                }
                .font(.app(11))
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// A quest's projects and practices as one row of overlapping badges, each ringed in the card's colour.
struct OverlappingBadges: View {
    let goals: [Goal]
    var size: GoalBadge.Size = .mini

    var body: some View {
        HStack(spacing: size == .card ? -8 : -6) {
            ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                GoalBadge(icon: goal.icon, color: goal.color, size: size, round: goal.isPractice)
                    .padding(size == .card ? 2.5 : 2)
                    .background(Theme.card, in: goal.isPractice ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: size.radius + 2)))
                    .zIndex(Double(goals.count - index))
                    .help(goal.title)
            }
        }
    }
}

/// "At risk through Build Supervibes": the effort and the goal it comes from; "All moving" when it's on track.
func effortLine(_ effort: GoalStatus?, goals: [Goal]) -> String {
    guard let effort else { return goals.isEmpty ? "Nothing linked yet" : "No status yet" }
    if effort == .onTrack { return "All moving" }
    guard let worst = goals.first(where: { $0.currentStatus == effort }) else { return statusLabel(effort, .target) }
    return "\(statusLabel(effort, .target)) through \(worst.title)"
}

/// A season's or a quest's read (the design's SeasonReadCard): its status, a headline and a few lines, what it drew on
/// and when, and Update. Before the first, a button for it.
struct SeasonReadCard: View {
    /// What's read: "this season" or "this quest".
    let subject: String
    let status: GoalStatus?
    let read: AreaRead?
    /// What it can draw on: the projects and practices that move it.
    let goals: [Goal]
    var reading = false
    var error: String?
    let now: Date
    var onRead: (() -> Void)?

    var body: some View {
        Card {
            Group {
                if let status {
                    StatusPill(status: status, basis: .target, help: "The most pressing of its projects’ and practices’ statuses")
                } else {
                    Text("No status yet").appText(.xs, .medium).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 12)

            Group {
                if let read {
                    Text(read.headline)
                        .appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(read.summary)
                        .font(.app(15.2))
                        .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 760, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } else {
                    Text("Ready for a first read")
                        .appText(.xl, .semibold, tracking: -0.02).foregroundStyle(Theme.foreground)
                    Text("Supervibes will read where its projects and practices stand and your time on the calendar, and tell you here, in a few lines, how \(subject) is going.")
                        .font(.app(15.2))
                        .lineSpacing(15.2 * 0.625 - 15.2 * 0.2)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 760, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
            }
            .compositingGroup()
            .opacity(reading && read != nil ? 0.5 : 1)

            HStack(spacing: 8) {
                if let read {
                    HStack(spacing: 4) {
                        ForEach(goals.filter { read.goalIds.contains($0.id) }) { goal in
                            GoalBadge(icon: goal.icon, color: goal.color, size: .micro, round: goal.isPractice).help(goal.title)
                        }
                        if read.usedCalendar {
                            Icon.calendar.image(size: 11)
                                .foregroundStyle(Theme.foreground)
                                .frame(width: 18, height: 18)
                                .background(Theme.wash, in: .rect(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.cardBorder))
                                .help("Your time on the calendar")
                        }
                    }
                    Text(read.createdAt.shortAgo(now: now)).appText(.xs)
                }
                if reading {
                    Text("Reading its projects and practices. This takes a few seconds.").appText(.xs)
                } else if let error {
                    Text(error).appText(.xs).foregroundStyle(Theme.danger)
                } else if goals.isEmpty {
                    Text("Link a project or practice to read it.").appText(.xs)
                }
                Spacer(minLength: 0)
                if let onRead, !goals.isEmpty {
                    FlowSmallButton(icon: .refresh, title: reading ? "Reading…" : (read == nil ? "Read \(subject)" : "Update"), isBusy: reading, action: onRead)
                }
            }
            .foregroundStyle(Theme.muted)
            .padding(.top, 20)
        }
    }
}

extension CalendarDay {
    /// "Mon, Nov 30".
    static func shortWeekdayMonthDay(_ day: String) -> String {
        guard let date = date(day) else { return day }
        return date.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!).weekday(.abbreviated).month(.abbreviated).day())
    }
}
