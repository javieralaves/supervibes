import SwiftUI

/// What an event's time is for, asked on the event, once for its whole series: a project or practice (which one, and
/// for a project whether it's a session or reserved), time to fill, or just an event.
struct EventQuestion: View {
    enum Answer: Hashable { case goal(String, reserved: Bool), open, event }

    let title: String
    let when: String
    let answer: Answer
    let goals: [CalendarGoal]
    let onLink: (String) -> Void
    let onReserved: (Bool) -> Void
    let onOpen: () -> Void
    let onPlain: () -> Void
    let onClose: () -> Void

    /// Showing the projects and practices to pick from.
    @State private var picking = false

    private var linked: (goalId: String, reserved: Bool)? {
        if case .goal(let id, let reserved) = answer { return (id, reserved) }
        return nil
    }

    var body: some View {
        QuestionPanel(onClose: onClose) {
            HStack(spacing: 10) {
                Icon.calendar.image(size: 15).foregroundStyle(Theme.foreground)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(12.5, .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text(when).font(.app(11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
            Divider().padding(.horizontal, 4).padding(.bottom, 4)
            Text("What’s this time for?").font(.app(11, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)

            if linked != nil || picking {
                VStack(alignment: .leading, spacing: 8) {
                    OptionRow(on: true, title: "A project or practice", line: nil) { picking = true }
                    WeekGoalMenu(goals: goals, picked: goals.first { $0.id == linked?.goalId }, onPick: onLink)
                        .padding(.leading, 25)
                    if let linked, let goal = goals.first(where: { $0.id == linked.goalId }) {
                        if goal.isPractice {
                            Text("Each one counts toward \(goal.title)’s \(goal.perWeek ?? 1) a week.")
                                .font(.app(11)).foregroundStyle(Theme.muted).padding(.leading, 25)
                        } else {
                            KindChoice(reserved: linked.reserved, color: goal.color, onPick: onReserved).padding(.leading, 25)
                        }
                    }
                }
                .padding(8)
                .background(Theme.wash, in: .rect(cornerRadius: 10))
            } else {
                OptionRow(on: false, title: "A project or practice", line: "Counts as time for it") { picking = true }
            }
            OptionRow(on: answer == .open, title: "Time to fill", line: "Free time, faded back, ready for a project", action: onOpen)
            OptionRow(on: answer == .event, title: "Just an event", line: "Plan around it", action: onPlain)
        }
    }
}

/// Time drawn on the week, and what it's for, asked first: the projects and practices, those moving a quest first and
/// marked with its number, each with the time it has so far, so what has none stands out. One click gives it the
/// time; a project's first then asks session or reserved, as a drop does.
struct TimeForQuestion: View {
    /// "Mon 30 · 18:30–20:00".
    let when: String
    let plan: WeekPlan
    let onPick: (String) -> Void
    let onClose: () -> Void

    /// Those moving a quest first, by its number; the rest as the plate has them.
    private func ordered(_ goals: [CalendarGoal]) -> [CalendarGoal] {
        let numbered = goals.compactMap { goal in plan.quest(for: goal.id).map { (goal, $0.number) } }.sorted { $0.1 < $1.1 }.map(\.0)
        return numbered + goals.filter { plan.quest(for: $0.id) == nil }
    }

    var body: some View {
        QuestionPanel(onClose: onClose) {
            HStack(spacing: 10) {
                Icon.clock.image(size: 15).foregroundStyle(Theme.foreground)
                    .frame(width: 28, height: 28)
                    .background(Theme.wash, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("New time").font(.app(12.5, .semibold)).foregroundStyle(Theme.foreground)
                    Text(when).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
            Divider().padding(.horizontal, 4).padding(.bottom, 4)
            Text("What’s this time for?").font(.app(11, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Projects", ordered(plan.projects))
                    section("Practices", ordered(plan.practices))
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ goals: [CalendarGoal]) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.app(10, .semibold)).tracking(0.3).foregroundStyle(Theme.muted.opacity(0.8))
                    .padding(.horizontal, 8).padding(.bottom, 2)
                ForEach(goals) { goal in
                    GoalChoice(goal: goal, meta: plan.meta(goal), quest: plan.quest(for: goal.id)?.number) { onPick(goal.id) }
                }
            }
        }
    }
}

/// One project or practice to give the time to: its badge (with its quest's number), its name, and the time it has.
private struct GoalChoice: View {
    let goal: CalendarGoal
    let meta: String
    var quest: Int?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                    .scaleEffect(26.0 / 24.0)
                    .frame(width: 26, height: 26)
                    .overlay(alignment: .bottomTrailing) {
                        if let quest {
                            QuestMark(number: quest, size: 13)
                                .padding(1.5).background(Theme.card, in: .circle)
                                .offset(x: 5, y: 5)
                        }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text(meta).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon.add.image(size: 12).foregroundStyle(Theme.muted).opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A block of time for a project or practice dropped on the week: for a project, whether it's a session or reserved;
/// and a way to take it off.
struct BlockQuestion: View {
    let block: CalendarBlock
    let goal: CalendarGoal
    let onReserved: (Bool) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    var body: some View {
        QuestionPanel(onClose: onClose) {
            HStack(spacing: 10) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs, round: goal.isPractice)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title).font(.app(12.5, .semibold)).foregroundStyle(Theme.foreground).lineLimit(1)
                    Text("\(block.startsAt.formatted(.dateTime.weekday(.abbreviated).day().locale(WeekPlan.locale))), \(WeekPlan.clock(block.startsAt))–\(WeekPlan.clock(block.endsAt))")
                        .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
            Divider().padding(.horizontal, 4).padding(.bottom, 4)
            if !goal.isPractice {
                Text("What kind of time is it?").font(.app(11, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)
                KindChoice(reserved: block.reserved, color: goal.color, onPick: onReserved).padding(.horizontal, 8)
            }
            FlowLink(icon: .delete, title: "Take it off your week", size: 12, action: onRemove)
                .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
        }
    }
}

/// Session or reserved, one above the other, each with a preview of the block it makes; the picked one ringed in ink.
struct KindChoice: View {
    let reserved: Bool
    let color: String
    let onPick: (Bool) -> Void

    var body: some View {
        VStack(spacing: 6) {
            option(false, "Session", "Time to work on it, with tasks in it or not yet.")
            option(true, "Reserved", "Time set aside for it, with nothing planned inside.")
        }
    }

    private func option(_ isReserved: Bool, _ title: String, _ line: String) -> some View {
        let on = isReserved == reserved
        return Button { onPick(isReserved) } label: {
            HStack(spacing: 10) {
                preview(isReserved)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(12, .medium)).foregroundStyle(Theme.foreground)
                    Text(line).font(.app(11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if on { Icon.tickBold.image(size: 12).foregroundStyle(Theme.foreground) }
            }
            .padding(6).padding(.trailing, 4)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.foreground : Theme.cardBorder, lineWidth: on ? 1.5 : 1))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// A block in miniature, as it would look on the week.
    private func preview(_ isReserved: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if isReserved {
                RoundedRectangle(cornerRadius: 6).fill(Theme.card)
                Hatch(color: GoalPalette.color(color).opacity(0.25), spacing: 4).clipShape(.rect(cornerRadius: 6))
                RoundedRectangle(cornerRadius: 6).strokeBorder(GoalPalette.color(color).opacity(0.35))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(GoalPalette.tintBackground(color))
            }
            Capsule().fill(GoalPalette.color(color).opacity(0.7)).frame(width: 2, height: 24).offset(x: 3, y: 5)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Theme.foreground(0.45)).frame(width: 14, height: 3)
                Capsule().fill(Theme.foreground(0.2)).frame(width: 9, height: 3)
            }
            .offset(x: 8, y: 6)
        }
        .frame(width: 30, height: 34)
    }
}

/// The popovers' panel: a card above the week, closed with Escape or its own button.
private struct QuestionPanel<Content: View>: View {
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) { content }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 14).fill(Theme.card)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 14)
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardBorder))
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Icon.close.image(size: 12).foregroundStyle(Theme.muted).frame(width: 24, height: 24).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(6)
            }
    }
}

private struct OptionRow: View {
    let on: Bool
    let title: String
    let line: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    if on {
                        Circle().fill(Theme.foreground)
                        Circle().fill(Theme.background).frame(width: 5, height: 5)
                    } else {
                        Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5)
                    }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(12, .medium)).foregroundStyle(Theme.foreground)
                    if let line { Text(line).font(.app(11)).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, on && line == nil ? 0 : 8)
            .padding(.vertical, on && line == nil ? 0 : 8)
            .background(on && line != nil ? Theme.wash : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Which project or practice, as a field that opens a menu of them.
private struct WeekGoalMenu: View {
    let goals: [CalendarGoal]
    let picked: CalendarGoal?
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(goals) { goal in
                Button(goal.title) { onPick(goal.id) }
            }
        } label: {
            HStack(spacing: 8) {
                if let picked {
                    GoalBadge(icon: picked.icon, color: picked.color, size: .mini, round: picked.isPractice)
                    Text(picked.title).font(.app(12, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
                } else {
                    Text("Choose one").font(.app(12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Icon.chevronDown.image(size: 12).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(Theme.card, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// A guiding tip, in ink: which part of the guide it's in, then the one thing to know, with a nib at what it's about.
struct WeekTip<Content: View>: View {
    enum Nib { case left, right }

    let kicker: String
    var nib: Nib = .left
    let onNext: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased()).font(.app(10.5, .semibold)).tracking(0.3).foregroundStyle(Theme.background.opacity(0.55))
            content.font(.app(12)).lineSpacing(2).foregroundStyle(Theme.background).fixedSize(horizontal: false, vertical: true)
            Button(action: onNext) {
                Text("Got it").font(.app(11.5, .semibold)).foregroundStyle(Theme.background)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Theme.background.opacity(0.14), in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(width: 220, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Theme.foreground)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 10)
        }
        .overlay(alignment: nib == .left ? .topLeading : .topTrailing) {
            Rectangle().fill(Theme.foreground).frame(width: 10, height: 10).rotationEffect(.degrees(45))
                .offset(x: nib == .left ? -4 : 4, y: 14)
        }
    }
}

/// Before the calendar can be shown: what it's for, and a way to allow it, or to carry on without.
struct CalendarAccessCard: View {
    let state: WeekPlan.CalendarState
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Icon.calendar.image(size: 18).foregroundStyle(Theme.foreground)
                .frame(width: 36, height: 36).background(Theme.wash, in: .rect(cornerRadius: 10))
            Text("See what’s already booked").font(.app(15, .semibold)).foregroundStyle(Theme.foreground).padding(.top, 12)
            Text(line).font(.app(12.5)).lineSpacing(2).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            HStack(spacing: 12) {
                FlowButton(title: button, primary: true, action: onAllow)
                FlowLink(title: "Plan without it", action: onSkip)
            }
            .padding(.top, 16)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private var line: String {
        switch state {
        case .denied: "Supervibes reads your Google Calendar from this Mac’s Calendar app, and access is turned off. Turn it on in System Settings."
        case .off: "Reading your Google Calendar is turned off in Settings. Turn it on to plan around what’s booked. Nothing changes in it."
        default: "Supervibes reads your Google Calendar from this Mac’s Calendar app, so your week plans around what’s booked. Nothing changes in it."
        }
    }

    private var button: String {
        switch state {
        case .denied: "Open System Settings"
        case .off: "Turn it on"
        default: "Allow access"
        }
    }
}
