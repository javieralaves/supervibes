import SwiftUI

/// An area's own page, from its card on Life or a goal's page: one column, top to bottom. The way back to Life, the
/// area's tile and name, where you are and where you're going in your own words (a quiet prompt for each until
/// said), then the goals moving it, each opening its own page.
struct AreaPage: View {
    let detail: AreaDetail
    var onBack: () -> Void = {}
    var onOpenGoal: (Goal) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackToLife(action: onBack)

                AreaTile(icon: detail.area.icon, size: 48).padding(.top, 32)
                Text(detail.area.name)
                    .font(.app(32, .semibold))
                    .tracking(-0.03 * 32)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 16)

                Words(label: "Where you are", text: detail.area.now, prompt: "Where does this area stand today?")
                    .padding(.top, 40)
                Words(label: "Where you’re going", text: detail.area.want, prompt: "Where do you want it to go?", muted: true)
                    .padding(.top, 28)

                SectionLabel("Goals").padding(.top, 40)
                if detail.goals.isEmpty {
                    Text("No goals in this area yet.")
                        .appText(.sm)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(detail.goals.enumerated()), id: \.element.id) { index, goal in
                            if index > 0 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                            GoalRow(goal: goal, week: detail.weeks[goal.id]) { onOpenGoal(goal) }
                        }
                    }
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
                    .clipShape(.rect(cornerRadius: 16))
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 56)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// "← Life": `text-sm font-medium text-muted hover:text-foreground`, as on a goal's page.
private struct BackToLife: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.arrowLeft.image(size: 16)
                Text("Life").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// `text-[11px] font-medium uppercase tracking-[0.02em] text-muted`
private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.app(11, .medium))
            .tracking(0.02 * 11)
            .foregroundStyle(Theme.muted)
    }
}

/// One of the area's two answers in the person's words, large; or, until said, a dashed prompt asking for it.
private struct Words: View {
    let label: String
    let text: String?
    let prompt: String
    var muted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            if let text, !text.isEmpty {
                Text(text)
                    .font(.app(17, .medium))
                    .tracking(-0.01 * 17)
                    .lineSpacing(17 * 0.5 - 17 * 0.2)
                    .foregroundStyle(muted ? Theme.foreground(0.8) : Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Icon.edit.image(size: 15)
                    Text(prompt).font(.app(15))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.foreground(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
        }
    }
}

/// A goal in the area: its badge, title and this week's objective, its status, and a way into its page.
private struct GoalRow: View {
    let goal: Goal
    let week: GoalWeek?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.app(14, .semibold))
                        .tracking(-0.01 * 14)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                    if let objective = week?.objective, !objective.isEmpty {
                        HStack(spacing: 6) {
                            Icon.flag.image(size: 11)
                            Text(objective).font(.app(12.5)).lineLimit(1)
                        }
                        .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 12)
                if let latest = goal.latest, let status = latest.status, let basis = latest.basis {
                    StatusText(status: status, basis: basis)
                } else {
                    Text("No status yet").appText(.xs).foregroundStyle(Theme.muted)
                }
                Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isHovered ? Theme.wash : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview("Madrid") {
    AreaPage(detail: Fixtures.areaDetail)
        .background(Theme.background)
        .frame(width: 900, height: 820)
}

#Preview("A new area") {
    AreaPage(detail: Fixtures.newAreaDetail)
        .background(Theme.background)
        .frame(width: 900, height: 720)
}
