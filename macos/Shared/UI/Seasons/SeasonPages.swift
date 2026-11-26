import SwiftUI

/// What the season's page shows (GET /seasons/{id}, with the person's goals and areas).
struct SeasonPageData: Hashable, Sendable {
    var season: Season
    var read: AreaRead?
    var goals: [Goal]
    var weeks: [String: GoalWeek]
    var areas: [Area]
    var today: String

    func goals(of quest: Quest) -> [Goal] {
        let ids = quest.goalIds
        // Projects first, then practices, each in their usual order.
        let linked = goals.filter { ids.contains($0.id) }
        return linked.filter { !$0.isPractice } + linked.filter(\.isPractice)
    }

    /// Every project and practice the season's quests move.
    var seasonGoals: [Goal] {
        let ids = Set(season.chosen.flatMap(\.goalIds))
        let linked = goals.filter { ids.contains($0.id) }
        return linked.filter { !$0.isPractice } + linked.filter(\.isPractice)
    }

    func area(_ id: String) -> Area? { areas.first { $0.id == id } }
}

/// What a quest's page shows (GET /quests/{id}, with the person's goals and areas).
struct QuestPageData: Hashable, Sendable {
    var quest: Quest
    var season: Season
    var gap: AreaGap?
    var read: AreaRead?
    var goals: [Goal]
    var weeks: [String: GoalWeek]
    var areas: [Area]
    var today: String

    var area: Area? { areas.first { $0.id == quest.areaId } }

    /// Projects first, then practices, each in their usual order.
    var questGoals: [Goal] {
        let linked = goals.filter { quest.goalIds.contains($0.id) }
        return linked.filter { !$0.isPractice } + linked.filter(\.isPractice)
    }
}

/// What the season's and a quest's pages can do.
struct SeasonPageActions {
    var back: () -> Void = {}
    var openQuest: (Quest) -> Void = { _ in }
    var openGoal: (Goal) -> Void = { _ in }
    var openArea: (String) -> Void = { _ in }
    var read: (() -> Void)?
    /// Renames the season or moves its end.
    var editSeason: (() -> Void)?
    /// Links a goal to the quest, or unlinks it.
    var toggleGoal: ((Goal) -> Void)?
}

// MARK: - The season's page

/// The season's own page, from its panel on Life (the design's SeasonPage): back to Life; the compass tile, its name,
/// days and week, and its weeks; its read; its quests, each with its effort and how far the season takes it; then the
/// projects and practices that move them.
struct SeasonPage: View {
    let data: SeasonPageData
    var reading = false
    var readError: String?
    var now = Date()
    var actions = SeasonPageActions()

    private var season: Season { data.season }
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    PageBackLink(title: "Life", action: actions.back)
                    Spacer()
                    if let edit = actions.editSeason {
                        FlowSmallButton(icon: .edit, title: "Rename or change end", action: edit)
                    }
                }
                .frame(height: 32)

                PageTile(icon: .season).padding(.top, 32)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(season.name).font(.app(32, .semibold)).tracking(-0.03 * 32).foregroundStyle(Theme.foreground)
                    Text("\(season.range) · \(weekLine(season))").font(.app(15)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                .padding(.top, 16)
                SeasonWeeks(season: season, labels: true).padding(.top, 24)

                SeasonReadCard(subject: "this season", status: season.status, read: data.read, goals: data.seasonGoals,
                               reading: reading, error: readError, now: now, onRead: actions.read)
                    .padding(.top, 32)

                PageSectionTitle("Quests").padding(.top, 48)
                LazyVGrid(columns: grid, spacing: 12) {
                    ForEach(season.chosen) { quest in
                        SeasonQuestCard(quest: quest, area: data.area(quest.areaId), goals: data.goals(of: quest), end: season.endLabel) {
                            actions.openQuest(quest)
                        }
                    }
                }

                PageSectionTitle("Projects & practices").padding(.top, 48)
                GoalCards(goals: data.seasonGoals, weeks: data.weeks, areas: data.areas, open: actions.openGoal)
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// A quest on the season's page: its area and effort, its name, where it starts, how far the season goes, and its
/// goals with the effort's reason.
private struct SeasonQuestCard: View {
    let quest: Quest
    let area: Area?
    let goals: [Goal]
    let end: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if let area {
                        GoalIconImage(name: area.icon, size: 14)
                        Text(area.name)
                    }
                    Spacer()
                    if let effort = quest.effort {
                        StatusText(status: effort, basis: .target)
                    } else {
                        Text("No status yet").appText(.xs)
                    }
                }
                .font(.app(13))
                .foregroundStyle(Theme.muted)
                Text(quest.title)
                    .font(.app(19, .semibold)).tracking(-0.02 * 19)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Text(quest.fromLine).font(.app(13.5)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                Spacer(minLength: 24)
                ReachArt(reach: quest.reach, end: end)
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.top, 20)
                HStack(spacing: 8) {
                    OverlappingBadges(goals: goals)
                    Spacer(minLength: 8)
                    Text(effortLine(quest.effort, goals: goals)).appText(.xs).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - A quest's page

/// A quest's own page, from its column on Life or its card on the season's page (the design's QuestPage): back to the
/// season; the route tile, its name, its area and the season's week, where it starts; its read; the projects and
/// practices that move it; and the area it comes from, with where it stands, where it's going and the gap.
struct QuestPage: View {
    let data: QuestPageData
    var reading = false
    var readError: String?
    var now = Date()
    var actions = SeasonPageActions()
    @State private var linkAnchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    private var quest: Quest { data.quest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    PageBackLink(title: data.season.name, action: actions.back)
                    Spacer()
                }
                .frame(height: 32)

                PageTile(icon: .route).padding(.top, 32)
                Text(quest.title)
                    .font(.app(32, .semibold)).tracking(-0.03 * 32)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                HStack(spacing: 12) {
                    if let area = data.area {
                        HStack(spacing: 6) {
                            GoalIconImage(name: area.icon, size: 14)
                            Text(area.name)
                        }
                        .font(.app(14, .medium))
                        .foregroundStyle(Theme.foreground(0.8))
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .background(Theme.foreground(0.05), in: .rect(cornerRadius: 6))
                    }
                    HStack(spacing: 6) {
                        Icon.season.image(size: 14)
                        Text("\(data.season.name) · \(weekLine(data.season))").monospacedDigit()
                    }
                    .font(.app(14))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 10)
                Text("\(quest.fromLine).").font(.app(15.2)).foregroundStyle(Theme.foreground(0.75)).padding(.top, 12)

                SeasonReadCard(subject: "this quest", status: quest.effort, read: data.read, goals: data.questGoals,
                               reading: reading, error: readError, now: now, onRead: actions.read)
                    .padding(.top, 32)

                HStack {
                    PageSectionTitle("Projects & practices")
                    Spacer()
                    if actions.toggleGoal != nil {
                        FlowSmallButton(icon: .edit, title: "Change") { showLinkMenu() }
                            .modifier(AnchorReader(frame: $linkAnchor))
                    }
                }
                .padding(.top, 48)
                if data.questGoals.isEmpty {
                    Text("Nothing moves it yet. Link a project or practice from \(data.area?.name ?? "its area").")
                        .appText(.sm).foregroundStyle(Theme.muted)
                } else {
                    GoalCards(goals: data.questGoals, weeks: data.weeks, areas: data.areas, open: actions.openGoal)
                }

                PageSectionTitle("Area").padding(.top, 48)
                if let area = data.area {
                    QuestAreaCard(area: area, gap: data.gap) { actions.openArea(area.id) }
                }
            }
            .frame(maxWidth: 1024, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    /// Every project and practice, the quest's ticked: picking one links or unlinks it.
    private func showLinkMenu() {
        guard let toggle = actions.toggleGoal else { return }
        let ordered = data.goals.filter { $0.areaId == quest.areaId } + data.goals.filter { $0.areaId != quest.areaId }
        overlays?.showMenu(anchor: linkAnchor, alignLeading: false) {
            MenuPanel(width: 320) {
                ForEach(ordered) { goal in
                    MenuItem(icon: goal.isPractice ? .repeats : .flag, title: goal.title, isChecked: quest.goalIds.contains(goal.id)) {
                        overlays?.dismiss()
                        toggle(goal)
                    }
                }
            }
        }
    }
}

/// The area a quest comes from: its tile, name, status and a way in; where it stands and where it's going side by
/// side; and the gap under them, the reason the quest exists.
private struct QuestAreaCard: View {
    let area: Area
    let gap: AreaGap?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    AreaTile(icon: area.icon, size: 32)
                    Text(area.name).font(.app(15.2, .semibold)).tracking(-0.01 * 15.2).foregroundStyle(Theme.foreground)
                    Spacer()
                    if let status = area.status {
                        StatusText(status: status, basis: .target)
                    } else {
                        Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 4) {
                        Text("Open area")
                        Icon.arrowRight.image(size: 13)
                    }
                    .font(.app(13, .medium))
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.8))
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            HStack(alignment: .top, spacing: 32) {
                side(hollow: true, label: "Where you are", text: area.now)
                side(hollow: false, label: "Where you want to be", text: area.want)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            if let gap {
                Rectangle().fill(Theme.cardBorder).frame(height: 1)
                VStack(alignment: .leading, spacing: 6) {
                    CardLabel("The gap")
                    Text(gap.title).font(.app(15, .semibold)).tracking(-0.01 * 15).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Theme.foreground(0.025))
            }
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private func side(hollow: Bool, label: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if hollow {
                    Circle().strokeBorder(Theme.foreground(0.55), lineWidth: 1.5).frame(width: 11, height: 11)
                } else {
                    Circle().fill(Theme.foreground).frame(width: 11, height: 11)
                }
                CardLabel(label)
            }
            .frame(height: 16)
            Text(text ?? "Not said yet")
                .font(.app(15, .medium)).tracking(-0.01 * 15)
                .lineSpacing(15 * 0.55 - 15 * 0.2)
                .foregroundStyle(text == nil ? Theme.muted : hollow ? Theme.foreground : Theme.foreground(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared

/// Life's cards for a set of goals, three to a row: projects with their week, practices with theirs.
struct GoalCards: View {
    let goals: [Goal]
    let weeks: [String: GoalWeek]
    let areas: [Area]
    let open: (Goal) -> Void

    private let grid = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        LazyVGrid(columns: grid, spacing: 12) {
            ForEach(goals) { goal in
                let area = areas.first { $0.id == goal.areaId }
                Group {
                    if goal.isPractice {
                        PracticeCard(goal: goal, area: area) { open(goal) }
                    } else {
                        GoalCard(goal: goal, week: weeks[goal.id], area: area) { open(goal) }
                    }
                }
                .frame(minHeight: 160)
            }
        }
    }
}

/// "← Life": `text-sm font-medium text-muted hover:text-foreground`, as on an area's page.
struct PageBackLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text(title).appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A page's tile: 48, rounded 15, a wash ringed, its icon at 24.
struct PageTile: View {
    let icon: Icon

    var body: some View {
        icon.image(size: 24)
            .foregroundStyle(Theme.foreground)
            .frame(width: 48, height: 48)
            .background(Theme.foreground(0.06), in: .rect(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.cardBorder))
    }
}

/// A section's title, as Life's: `text-lg font-semibold tracking-[-0.02em]`, 36 tall over 12.
struct PageSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .appText(.lg, .semibold, tracking: -0.02)
            .foregroundStyle(Theme.foreground)
            .frame(height: 36)
            .padding(.bottom, 12)
    }
}
