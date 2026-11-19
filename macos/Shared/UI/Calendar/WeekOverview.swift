import SwiftUI

/*
 * The week's overview, beside the week, as WeekOverview in week-view.tsx. First each goal's time as
 * a bar on one shared scale (light: planned, solid: happened); then the week's objectives, each
 * editable in place, and "Add weekly objective" for goals that don't have one yet.
 */

struct WeekOverview: View {
    let goals: [CalendarGoal]
    /// Each goal's time this week, in minutes.
    let totals: [String: (planned: Double, done: Double)]
    /// This week's objective for each goal that has one.
    let objectives: [String: String]
    /// The Monday this week starts on, "YYYY-MM-DD".
    let weekStart: String
    var setObjective: ((_ goalId: String, _ weekStart: String, _ text: String) async -> String?)?

    /// Goals picked from "Add weekly objective" that aren't saved yet, for this week.
    @State private var adding: (weekStart: String, ids: [String]) = ("", [])
    @State private var addFrame: CGRect = .zero
    @Environment(\.overlays) private var overlays

    private var added: [String] { adding.weekStart == weekStart ? adding.ids : [] }

    var body: some View {
        // Goals with time this week first, most time first; then the rest, in their order.
        let byTime = goals.enumerated().sorted { a, b in
            let pa = totals[a.element.id]?.planned ?? 0, pb = totals[b.element.id]?.planned ?? 0
            return pa != pb ? pa > pb : a.offset < b.offset
        }.map(\.element)
        let most = totals.values.map(\.planned).max() ?? 0
        let withObjective = goals.filter { objectives[$0.id] != nil || added.contains($0.id) }
        let without = goals.filter { objectives[$0.id] == nil && !added.contains($0.id) }
        let planned = totals.values.reduce(0) { $0 + $1.planned }
        let done = totals.values.reduce(0) { $0 + $1.done }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Icon.target.image(size: 16).foregroundStyle(Theme.foreground(0.75))
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.background)
                                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.06)), radius: 1, y: 1)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
                    Text("This week").font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 0)
                    Text(CalendarDay.formatWeek(weekStart)).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(durationLabel(done)).font(.app(22, .semibold)).tracking(-0.44).monospacedDigit().foregroundStyle(Theme.foreground)
                    Text(planned > 0 ? "done of \(durationLabel(planned)) planned" : "nothing planned yet")
                        .appText(.xs).foregroundStyle(Theme.muted)
                }
                .padding(.top, 16)
                GoalSplitBar(parts: byTime.map {
                    ($0.id, $0.color, Int((totals[$0.id]?.planned ?? 0).rounded()), Int((totals[$0.id]?.done ?? 0).rounded()))
                })
                .padding(.top, 12)
                .accessibilityLabel("\(durationLabel(done)) done of \(durationLabel(planned)) planned, across goals")
            }
            .padding(16)
            .background {
                RadialGradient(colors: [Theme.foreground(0.05), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if goals.isEmpty {
                        Text("No goals yet.").appText(.sm).foregroundStyle(Theme.muted)
                    } else {
                        SectionLabel(text: "By goal")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(byTime) { goal in
                                TimeRow(goal: goal, totals: totals[goal.id], most: most)
                            }
                        }
                        .padding(.top, 8)

                        SectionLabel(text: "Objectives").padding(.top, 24)
                        if !withObjective.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(withObjective) { goal in
                                    ObjectiveRow(
                                        goal: goal,
                                        weekStart: weekStart,
                                        objective: objectives[goal.id],
                                        // Just picked from the menu: start typing straight away.
                                        autoFocus: added.contains(goal.id) && objectives[goal.id] == nil,
                                        save: setObjective,
                                        onSettled: { drop(goal.id) }
                                    )
                                    .id("\(goal.id):\(weekStart)")
                                }
                            }
                            .padding(.top, 8)
                        }
                        if !without.isEmpty {
                            AddObjectiveButton(isOpen: overlays?.presented?.owner == "add-objective") { openMenu(without) }
                                .modifier(AnchorReader(frame: $addFrame))
                                .padding(.top, 8)
                                .padding(.horizontal, -8)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private func drop(_ id: String) {
        adding = (weekStart, added.filter { $0 != id })
    }

    private func openMenu(_ goals: [CalendarGoal]) {
        guard let overlays else { return }
        overlays.showMenu(anchor: addFrame, owner: "add-objective", alignLeading: true) {
            MenuPanel(width: 256) {
                Text("For which goal?").appText(.xs, .medium).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
                ForEach(goals) { goal in
                    GoalMenuRow(goal: goal) {
                        overlays.dismiss()
                        adding = (weekStart, added + [goal.id])
                    }
                }
            }
        }
    }
}

/// `text-[11px] font-medium uppercase tracking-[0.06em] text-muted`.
private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased()).font(.app(11, .medium)).tracking(0.66).foregroundStyle(Theme.muted)
    }
}

/// A goal's time this week: its title and figures, then a bar on the shared scale.
private struct TimeRow: View {
    let goal: CalendarGoal
    let totals: (planned: Double, done: Double)?
    /// The most time any goal has this week, in minutes: the bars' full width.
    let most: Double

    var body: some View {
        let planned = totals?.planned ?? 0
        let done = totals?.done ?? 0
        let light = Color(nsColor: NSColor(hex: GoalPalette.colorInfo(goal.color).light) ?? .gray)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(goal.title).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(goal.title)
                Text(planned > 0 ? "\(durationLabel(done)) / \(durationLabel(planned))" : "No time")
                    .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            GeometryReader { geometry in
                let share = { (minutes: Double) in most > 0 ? geometry.size.width * minutes / most : 0 }
                ZStack(alignment: .leading) {
                    if planned > 0 { Capsule().fill(light.opacity(0.3)).frame(width: share(planned)) }
                    if done >= 1 { Capsule().fill(light).frame(width: share(done)) }
                }
            }
            .frame(height: 4)
            .accessibilityLabel(planned > 0 ? "\(durationLabel(done)) done of \(durationLabel(planned)) planned" : "No time this week")
        }
    }
}

/// One goal's objective for the week, editable in place: saved when the field loses focus, cleared
/// by emptying it. A row just added from the menu goes again if left empty.
private struct ObjectiveRow: View {
    let goal: CalendarGoal
    let weekStart: String
    let objective: String?
    let autoFocus: Bool
    let save: ((String, String, String) async -> String?)?
    /// Once a new row is saved or abandoned, it's no longer "being added".
    let onSettled: () -> Void

    @State private var draft: String
    @State private var error: String?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    init(goal: CalendarGoal, weekStart: String, objective: String?, autoFocus: Bool,
         save: ((String, String, String) async -> String?)?, onSettled: @escaping () -> Void) {
        self.goal = goal
        self.weekStart = weekStart
        self.objective = objective
        self.autoFocus = autoFocus
        self.save = save
        self.onSettled = onSettled
        _draft = State(initialValue: objective ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(GoalPalette.color(goal.color)).frame(width: 6, height: 6)
                Text(goal.title).font(.app(11, .medium)).foregroundStyle(Theme.muted).lineLimit(1).help(goal.title)
            }
            TextField("", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.app(13))
                .foregroundStyle(Theme.foreground)
                .focused($isFocused)
                .placeholder("What should this week move?", when: draft.isEmpty, font: .app(13))
                .onSubmit { isFocused = false }
                .onKeyPress(.return, phases: .down) { press in
                    // Return saves; shift-return is a new line.
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    isFocused = false
                    return .handled
                }
                .onExitCommand {
                    draft = objective ?? ""
                    isFocused = false
                }
                .onChange(of: draft) { if draft.count > 500 { draft = String(draft.prefix(500)) } }
                .onChange(of: isFocused) { if !isFocused { commit() } }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isHovered || isFocused ? Theme.wash.opacity(0.6) : .clear, in: .rect(cornerRadius: 6))
                .onHover { isHovered = $0 }
                .padding(.horizontal, -6)
                .accessibilityLabel("What this week should move for \(goal.title)")
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).padding(.top, 2)
            }
        }
        .onAppear {
            if autoFocus { Task { @MainActor in isFocused = true } }
        }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (objective ?? "") else {
            if value.isEmpty { onSettled() }
            return
        }
        guard let save else { return }
        error = nil
        let goalId = goal.id, week = weekStart
        Task {
            error = await save(goalId, week, value)
            if error == nil { onSettled() }
        }
    }
}

/// "+ Add weekly objective".
private struct AddObjectiveButton: View {
    let isOpen: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.add.image(size: 14)
                Text("Add weekly objective").font(.app(13, .medium))
            }
            .foregroundStyle(isHovered || isOpen ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isHovered || isOpen ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A goal in the "For which goal?" menu.
private struct GoalMenuRow: View {
    let goal: CalendarGoal
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                GoalBadge(icon: goal.icon, color: goal.color, size: .xs)
                Text(goal.title).appText(.sm).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
