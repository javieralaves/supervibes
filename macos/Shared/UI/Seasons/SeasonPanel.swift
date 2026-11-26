import SwiftUI

/// Life's season panel while one is running (the design's ActiveSeasonPanel): raised above the page, This season with
/// the compass, its name, days and week, its weeks, then a column per quest: its area, its name, where it starts, and
/// at the bottom the projects and practices that move it as one row of overlapping badges, so the columns end on one
/// line. The top opens the season's page; a column opens its quest's.
struct SeasonPanel: View {
    let season: Season
    let areas: [Area]
    let goals: [Goal]
    var onOpenSeason: () -> Void = {}
    var onOpenQuest: (Quest) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelButton(action: onOpenSeason) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Icon.season.image(size: 15)
                        Text("This season").font(.app(13, .medium))
                        Spacer()
                        Icon.arrowRight.image(size: 14)
                    }
                    .foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(season.name).font(.app(32, .semibold)).tracking(-0.03 * 32).foregroundStyle(Theme.foreground)
                        Text("\(season.range) · \(weekLine(season))").font(.app(15)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 4)
                    SeasonWeeks(season: season).padding(.top, 20)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            if !season.chosen.isEmpty {
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(season.chosen.enumerated()), id: \.element.id) { index, quest in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(width: 1) }
                        PanelButton { onOpenQuest(quest) } label: {
                            column(quest)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .raisedPanel()
    }

    private func column(_ quest: Quest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let area = areas.first(where: { $0.id == quest.areaId }) {
                HStack(spacing: 6) {
                    GoalIconImage(name: area.icon, size: 14)
                    Text(area.name)
                }
                .font(.app(13))
                .foregroundStyle(Theme.muted)
            }
            Text(quest.title)
                .font(.app(19, .semibold)).tracking(-0.02 * 19)
                .lineSpacing(19 * 0.3 - 19 * 0.2)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text(quest.fromLine).font(.app(13.5)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 6)
            Spacer(minLength: 24)
            OverlappingBadges(goals: quest.goalIds.compactMap { id in goals.first { $0.id == id } }, size: .card)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Week 1 of 9", "Starts Monday" before its first day, "Last week" in its last.
func weekLine(_ season: Season) -> String {
    if season.week < 1 { return "Starts \(CalendarDay.weekdayMonthDay(season.startsOn).split(separator: ",").first ?? "")" }
    return "Week \(min(season.week, season.weeks)) of \(season.weeks)"
}

/// A part of the panel that opens something: a wash on hover, nothing else.
private struct PanelButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .background(isHovered ? Theme.foreground(0.02) : .clear)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
