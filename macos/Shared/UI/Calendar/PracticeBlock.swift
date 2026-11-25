import SwiftUI

/// Goals as the calendar's menus list them: projects, then practices, each under its own heading. A heading with
/// nothing under it is left out.
struct GoalSections {
    struct Section {
        let title: String
        let goals: [CalendarGoal]
    }

    let sections: [Section]

    init(_ goals: [CalendarGoal]) {
        sections = [
            Section(title: "Projects", goals: goals.filter { !$0.isPractice }),
            Section(title: "Practices", goals: goals.filter(\.isPractice)),
        ].filter { !$0.goals.isEmpty }
    }
}

/// In a practice's block panel, where the session-only help would be: where the block stands in its practice's week,
/// and, once it's over, a way to say it didn't happen (or that it did after all). A block counts once its time has
/// passed, unless it's under the practice's minimum or marked as not having happened.
struct PracticeBlockBox: View {
    let block: CalendarBlock
    let goal: CalendarGoal
    let ended: Bool
    let now: Date
    /// Marks it as not having happened (true) or as having happened (false); nil can't change it.
    var onMissed: ((Bool) -> Void)?

    private var minutes: Int { Int(block.endsAt.timeIntervalSince(block.startsAt) / 60) }
    private var isShort: Bool { ended && minutes < (goal.minMinutes ?? 0) }

    /// The practice's week, if this block is in it.
    private var week: Practice.Week? {
        guard let week = goal.week, CalendarDay.weekStart(CalendarDay.today(block.startsAt)) == week.start else { return nil }
        return week
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let week, let perWeek = goal.perWeek, !goal.paused {
                    PracticePips(pips: Practice(perWeek: perWeek, week: week).pips, color: goal.color, size: 10, spacing: 4)
                }
                Text(headline).appText(.px(13), .medium).foregroundStyle(Theme.foreground)
            }
            Text(detail).appText(.xs).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if ended, !isShort, let onMissed {
                Button { onMissed(!block.missed) } label: {
                    HStack(spacing: 6) {
                        (block.missed ? Icon.reopen : Icon.close).image(size: 13)
                        Text(block.missed ? "It happened after all" : "Didn’t happen")
                    }
                    .appText(.xs, .medium)
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Theme.card, in: .rect(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder))
                    .contentShape(.rect(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .help(block.missed ? "Count it again" : "It won’t count toward \(goal.title)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.foreground(0.035), in: .rect(cornerRadius: 12))
    }

    private var headline: String {
        if goal.paused { return "Paused: these weeks don’t count" }
        if block.missed { return "Didn’t happen" }
        if isShort { return "Too short to count" }
        if !ended { return week.map { "\($0.done) of \(goal.perWeek ?? 0) done this week" } ?? "Counts once it’s happened" }
        return week.map { "Counted: \($0.done) of \(goal.perWeek ?? 0) this week" } ?? "Counted"
    }

    private var detail: String {
        let practice = goal.title
        if goal.paused { return "\(practice) is paused, so nothing counts until it picks up again." }
        if block.missed { return "It doesn’t count toward \(practice). If it did happen, say so and it counts again." }
        if isShort { return "\(practice) counts sessions of at least \(TaskItem.minutesLabel(goal.minMinutes ?? 0)); this one is \(TaskItem.minutesLabel(minutes))." }
        if !ended {
            let planned = week.map { $0.planned > 1 ? " \($0.planned - 1) more \($0.planned - 1 == 1 ? "is" : "are") planned this week." : "" } ?? ""
            return "It counts toward \(practice) once its time has passed.\(planned) If it doesn’t happen, say so here after."
        }
        return "It counted toward \(practice). If it didn’t happen, say so and it won’t."
    }
}
