import SwiftUI

/*
 * How a practice draws, wherever it shows: its rhythm ("3 times a week", with the repeat icon), its week as pips
 * (filled once a session's happened, ringed while one's planned, empty for the rest), and its status, which is
 * counted rather than read. Matches the Projects & practices page in supervibes-design.
 */

/// "3 times a week · at least 30 min", after the repeat icon.
struct RhythmLabel: View {
    let perWeek: Int
    var minMinutes: Int?
    var iconSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Icon.repeats.image(size: iconSize)
            if let minMinutes {
                Text("\(Practice.rhythm(perWeek))\(Text(" · at least \(TaskItem.minutesLabel(minMinutes))").foregroundStyle(Theme.muted))")
            } else {
                Text(Practice.rhythm(perWeek))
            }
        }
        .lineLimit(1)
    }
}

/// A week's sessions as pips, in the practice's colour.
struct PracticePips: View {
    let pips: [Practice.Pip]
    let color: String
    var size: CGFloat = 8
    var spacing: CGFloat = 3

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                switch pip {
                case .done:
                    Circle().fill(GoalPalette.color(color)).frame(width: size, height: size)
                case .planned:
                    Circle().strokeBorder(GoalPalette.color(color), lineWidth: 1.5).frame(width: size, height: size)
                case .empty:
                    Circle().fill(Theme.foreground(0.1)).frame(width: size, height: size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

/// A practice's status as the cards say it: On track, At risk or Off track; Paused; or No status yet before its
/// first full week.
struct PracticeStatusText: View {
    let practice: Practice

    var body: some View {
        if practice.paused != nil {
            HStack(spacing: 5) {
                Icon.pause.image(size: 11)
                Text("Paused").appText(.xs, .medium)
            }
            .foregroundStyle(Theme.muted)
        } else if let status = practice.status {
            StatusText(status: status.status, basis: .week)
                .help(status.reason)
        } else {
            Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
        }
    }
}

/// A practice on Life, in a project card's shape: its badge (round) with its status at the top right, its name, its
/// rhythm where a project has this week's objective, and pinned to the bottom this week's pips and its area.
struct PracticeCard: View {
    let goal: Goal
    var area: Area?
    /// Whether it moves the running season: marked if so, a step dimmer if not.
    var season: InSeason = .none
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.overlays) private var overlays

    static func menuOwner(_ goal: Goal) -> String { "practice-card#\(goal.id)" }

    private var isEngaged: Bool { isHovered || overlays?.presented?.owner == Self.menuOwner(goal) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    GoalBadge(goal: goal, size: .card).seasonMark(season == .moving)
                    Spacer(minLength: 12)
                    if let practice = goal.practice {
                        PracticeStatusText(practice: practice)
                    }
                }

                Text(goal.title)
                    .font(.app(15.2, .semibold))
                    .tracking(-0.01 * 15.2)
                    .lineSpacing(15.2 * 0.375 - 15.2 * 0.2)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)
                if let practice = goal.practice {
                    RhythmLabel(perWeek: practice.perWeek)
                        .font(.app(13))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }

                Spacer(minLength: 20)

                HStack(spacing: 8) {
                    if let practice = goal.practice {
                        PracticePips(pips: practice.pips, color: goal.color)
                            .opacity(practice.paused == nil ? 1 : 0.5)
                        Text("\(practice.week.done) of \(practice.perWeek)").monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    if let area {
                        AreaLabel(name: area.name, icon: area.icon)
                    }
                }
                .appText(.xs)
                .foregroundStyle(Theme.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 148)
            .background(season.cardFill, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isEngaged ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .inactive(goal.isPending)
        .opacity(goal.isPending ? 0.6 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isEngaged)
    }
}
