import SwiftUI

/// The way into Your week (the design's FsWeekIntro): quieter than the welcome, with the steps row still up top since
/// it's the same flow. It says what's next and why, then shows the next screen in miniature, playing the three things
/// the week asks in turn (what's already booked, time for projects, a rhythm for practices) while the three points
/// under it light up as each plays. Still, on its finished week, in snapshots and with Reduce Motion.
struct FirstRunWeekIntro: View {
    /// "Nov 30 – Dec 6".
    let weekLabel: String
    /// The week's days, from today: their short names, and whether each is a weekend.
    var days: [WeekIntroDay] = WeekIntroDay.sample
    /// The route's row of steps; the week is its last.
    var steps: [String] = FirstRunChoice.week.steps
    let onStart: () -> Void
    /// A moment of the show to hold on, in seconds into its loop (snapshots of it mid-way).
    var frozenAt: Double?
    @Environment(\.staticRendering) private var staticRendering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private var isStill: Bool { staticRendering || reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            FirstRunSteps(current: steps.count - 1, steps: steps)
            VStack(spacing: 0) {
                Text("Your week · \(weekLabel)").font(.app(13, .medium)).foregroundStyle(Theme.muted)
                Text("Now, make room for it")
                    .font(.app(32, .semibold)).tracking(-0.03 * 32)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 6)
                Text("What matters only moves once it has time. So next is your week: what’s already booked over the next seven days, starting today, and where what matters fits around it.")
                    .font(.app(15)).lineSpacing(3.5)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: isStill || frozenAt != nil)) { context in
                    let t = frozenAt ?? (isStill ? WeekShow.still : context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: WeekShow.cycle))
                    VStack(spacing: 0) {
                        WeekAheadArt(days: days, t: t)
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(WeekShow.Phase.allCases, id: \.self) { phase in
                                point(phase, emphasis: frozenAt == nil && isStill ? 1 : WeekShow.emphasis(of: phase, at: t))
                            }
                        }
                        .frame(width: WeekAheadArt.size.width - 8)
                        .padding(.top, 32)
                    }
                }
                .padding(.top, 40)

                VStack(spacing: 10) {
                    FlowButton(title: "Plan my week", primary: true, action: onStart)
                    HStack(spacing: 5) {
                        Icon.clock.image(size: 13)
                        Text("About 3 min").font(.app(12.5, .medium))
                    }
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 36)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 48)
        }
        .background(Theme.background)
        .onAppear { start = Date() }
    }

    /// One of the three things the week asks: its mark, its name and a line; bright while it plays, quieter otherwise.
    private func point(_ phase: WeekShow.Phase, emphasis: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(phase.color.map { GoalPalette.tintBackground($0) } ?? Theme.foreground(0.06))
                Group {
                    if let goalIcon = phase.goalIcon {
                        GoalIconImage(name: goalIcon, size: 15)
                    } else {
                        Icon.calendar.image(size: 15)
                    }
                }
                .foregroundStyle(phase.color.map { GoalPalette.color($0) } ?? Theme.foreground(0.8))
            }
            .frame(width: 28, height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(phase.color.map { GoalPalette.color($0).opacity(0.5) } ?? Theme.lineStrong, lineWidth: 1.5)
                    .opacity(emphasis > 0.99 && (frozenAt != nil || !isStill) ? 1 : 0)
            }
            Text(phase.title).font(.app(13.5, .semibold)).tracking(-0.13).foregroundStyle(Theme.foreground).padding(.top, 12)
            Text(phase.line).font(.app(12.5)).lineSpacing(2.5).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.45 + 0.55 * emphasis)
    }
}

/// A day in the intro's week: "Mon 30", and whether it's a weekend (drawn a little quieter).
struct WeekIntroDay: Hashable, Sendable {
    let label: String
    let isWeekend: Bool

    /// Nov 30 to Dec 6, 2026, for previews and snapshots.
    static let sample: [WeekIntroDay] = [
        .init(label: "Mon 30", isWeekend: false), .init(label: "Tue 1", isWeekend: false), .init(label: "Wed 2", isWeekend: false),
        .init(label: "Thu 3", isWeekend: false), .init(label: "Fri 4", isWeekend: false), .init(label: "Sat 5", isWeekend: true),
        .init(label: "Sun 6", isWeekend: true),
    ]

    /// The seven days from `start`, in US English like the rest of the app's dates.
    static func week(from start: Date, calendar: Calendar = .current) -> [WeekIntroDay] {
        let format = Date.FormatStyle(locale: Locale(identifier: "en_US")).weekday(.abbreviated)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return WeekIntroDay(label: "\(day.formatted(format)) \(calendar.component(.day, from: day))", isWeekend: calendar.isDateInWeekend(day))
        }
    }
}

// MARK: - The show

/// The miniature's script: one loop, in seconds. The calendar fills in and an event is claimed for what matters; two
/// projects are lifted from the plate and dropped into the week; a practice's runs land through the week, its rhythm
/// filling; a pause, then it clears and starts again.
private enum WeekShow {
    static let cycle: Double = 10
    /// The moment drawn when it's still: everything in place.
    static let still: Double = 8

    enum Phase: CaseIterable {
        case booked, projects, practices

        var title: String {
            switch self {
            case .booked: "What’s already booked"
            case .projects: "Time for your projects"
            case .practices: "A rhythm for practices"
            }
        }

        var line: String {
            switch self {
            case .booked: "Your Google Calendar as it is. Say which of it is already time for what matters."
            case .projects: "Drag them into your week, to work on or to set time aside."
            case .practices: "Each time you put one in counts toward how often you want it."
            }
        }

        var goalIcon: String? {
            switch self {
            case .booked: nil
            case .projects: "Rocket01Icon"
            case .practices: "RunningShoesIcon"
            }
        }

        var color: String? {
            switch self {
            case .booked: nil
            case .projects: "violet"
            case .practices: "green"
            }
        }

        /// When it plays in the loop.
        var span: ClosedRange<Double> {
            switch self {
            case .booked: 0.2...2.6
            case .projects: 2.6...6.0
            case .practices: 6.0...8.4
            }
        }
    }

    /// How lit a point is: full while its part plays, easing in and out; all lit while the week rests at the end.
    static func emphasis(of phase: Phase, at t: Double) -> Double {
        if t > 8.4 { return 1 }
        let fadeIn = progress(t, phase.span.lowerBound - 0.25, phase.span.lowerBound + 0.15)
        let fadeOut = 1 - progress(t, phase.span.upperBound - 0.15, phase.span.upperBound + 0.25)
        return min(fadeIn, fadeOut)
    }

    /// 0 before `from`, 1 after `to`, straight between.
    static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return t >= to ? 1 : 0 }
        return min(1, max(0, (t - from) / (to - from)))
    }

    static func easeInOut(_ p: Double) -> Double { p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2 }
    static func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }

    /// A small overshoot as something lands: 0 to 1, peaking a little past 1.
    static func land(_ p: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
    }

    /// Everything added during the loop fades away at its end, so it can start again.
    static func clearing(_ t: Double) -> Double { 1 - progress(t, cycle - 0.7, cycle - 0.1) }
}

// MARK: - The miniature

/// The next screen in miniature: the plate beside the week, with the calendar's events in grey, drawn on a fixed
/// canvas so what's dragged can travel from the plate to its day.
private struct WeekAheadArt: View {
    let days: [WeekIntroDay]
    let t: Double

    static let size = CGSize(width: 680, height: 256)
    private static let inset: CGFloat = 12
    private static let sidebar: CGFloat = 156
    private static let gridX: CGFloat = inset + sidebar + 10
    private static let gridWidth: CGFloat = size.width - gridX - inset
    private static let header: CGFloat = 30
    private static let bodyY: CGFloat = inset + header
    private static let bodyHeight: CGFloat = size.height - bodyY - inset - 4
    private static var dayWidth: CGFloat { gridWidth / 7 }

    /// The plate's projects and practices, as rows.
    private struct Row {
        let icon: String
        let color: String
        let width: CGFloat
        var isPractice = false
        /// A practice's times a week, as dots.
        var rhythm = 0
    }

    private static let projects = [
        Row(icon: "Rocket01Icon", color: "violet", width: 78), Row(icon: "UserGroupIcon", color: "sky", width: 92),
        Row(icon: "Sofa01Icon", color: "amber", width: 64),
    ]
    private static let practices = [
        Row(icon: "RunningShoesIcon", color: "green", width: 44, isPractice: true, rhythm: 3),
        Row(icon: "LanguageSkillIcon", color: "indigo", width: 54, isPractice: true, rhythm: 2),
    ]
    private static let rowHeight: CGFloat = 26
    private static let projectsY: CGFloat = inset + 34
    private static let practicesY: CGFloat = projectsY + CGFloat(projects.count) * rowHeight + 34

    /// The calendar's events: day, where it starts and how long, as parts of the day.
    private static let events: [(day: Int, top: CGFloat, height: CGFloat)] = [
        (0, 0.05, 0.13), (1, 0.05, 0.13), (2, 0.05, 0.13), (3, 0.05, 0.13), (4, 0.05, 0.13),
        (0, 0.42, 0.18), (1, 0.26, 0.2), (2, 0.56, 0.16), (3, 0.26, 0.26), (4, 0.44, 0.18), (5, 0.32, 0.3), (6, 0.66, 0.14),
    ]
    /// The event claimed as time for what matters: Thursday's long one, for Home.
    private static let claimed = 8
    private static let claimColor = "amber"

    /// What's dragged in: from which project row, to which day and part of it, and when.
    private struct Drop {
        let row: Int
        let day: Int
        let top: CGFloat
        let height: CGFloat
        let lift: Double
    }

    private static let drops = [
        Drop(row: 0, day: 1, top: 0.56, height: 0.24, lift: 2.9),
        Drop(row: 1, day: 4, top: 0.72, height: 0.2, lift: 4.4),
    ]
    /// A drop takes: lifting, travelling, landing.
    private static let liftTime = 0.25, travelTime = 0.75, landTime = 0.35

    /// The practice's runs: day, part of the day, when they land.
    private static let runs: [(day: Int, top: CGFloat, at: Double)] = [(0, 0.82, 6.3), (2, 0.84, 6.8), (5, 0.8, 7.3)]
    private static let runHeight: CGFloat = 0.11

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarView
            grid
            ForEach(Array(Self.drops.enumerated()), id: \.offset) { _, drop in dragged(drop) }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Theme.card)
                .shadow(color: .black.opacity(0.14), radius: 28, y: 18)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
        .clipShape(.rect(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    // MARK: Sidebar

    private var sidebarView: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Theme.background.opacity(0.55))
                .frame(width: Self.sidebar, height: Self.size.height - Self.inset * 2)
            sectionLabel("Projects").offset(x: 12, y: Self.projectsY - 22 - Self.inset)
            ForEach(Array(Self.projects.enumerated()), id: \.offset) { index, row in
                rowView(row, filled: 0).offset(x: 10, y: Self.projectsY + CGFloat(index) * Self.rowHeight - Self.inset)
            }
            sectionLabel("Practices").offset(x: 12, y: Self.practicesY - 22 - Self.inset)
            ForEach(Array(Self.practices.enumerated()), id: \.offset) { index, row in
                rowView(row, filled: index == 0 ? runsLanded : 0)
                    .offset(x: 10, y: Self.practicesY + CGFloat(index) * Self.rowHeight - Self.inset)
            }
        }
        .offset(x: Self.inset, y: Self.inset)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.app(10, .semibold)).tracking(0.2).foregroundStyle(Theme.muted)
    }

    private func rowView(_ row: Row, filled: Double) -> some View {
        HStack(spacing: 8) {
            GoalBadge(icon: row.icon, color: row.color, size: .mini, round: row.isPractice)
            Capsule().fill(Theme.foreground(0.14)).frame(width: row.width, height: 5)
            Spacer(minLength: 0)
            if row.isPractice {
                HStack(spacing: 3) {
                    ForEach(0..<row.rhythm, id: \.self) { dot in
                        let on = WeekShow.progress(filled, Double(dot), Double(dot) + 1)
                        Circle()
                            .fill(GoalPalette.color(row.color).opacity(on))
                            .overlay(Circle().strokeBorder(GoalPalette.color(row.color).opacity(0.5 * (1 - on)), lineWidth: 1))
                            .frame(width: 6, height: 6)
                            .scaleEffect(1 + 0.4 * sin(.pi * on))
                    }
                }
            }
        }
        .frame(width: Self.sidebar - 20, height: Self.rowHeight)
    }

    /// How many runs have landed, fractionally as each one pops, cleared at the loop's end.
    private var runsLanded: Double {
        Self.runs.map { WeekShow.progress(t, $0.at, $0.at + 0.3) }.reduce(0, +) * WeekShow.clearing(t)
    }

    // MARK: Week

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            // Weekends a touch quieter, the hour lines faint.
            ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { index, day in
                if day.isWeekend {
                    Rectangle().fill(Theme.foreground(0.02))
                        .frame(width: Self.dayWidth, height: Self.bodyHeight + Self.header)
                        .offset(x: CGFloat(index) * Self.dayWidth)
                }
            }
            ForEach(1..<4, id: \.self) { line in
                Rectangle().fill(Theme.foreground(0.04))
                    .frame(width: Self.gridWidth, height: 1)
                    .offset(y: Self.header + Self.bodyHeight * CGFloat(line) / 4)
            }
            ForEach(1..<7, id: \.self) { column in
                Rectangle().fill(Theme.cardBorder)
                    .frame(width: 1, height: Self.bodyHeight + Self.header)
                    .offset(x: CGFloat(column) * Self.dayWidth)
            }
            Rectangle().fill(Theme.cardBorder).frame(width: Self.gridWidth, height: 1).offset(y: Self.header)
            ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { index, day in
                HStack(spacing: 4) {
                    if index == 0 { Circle().fill(GoalPalette.color("coral")).frame(width: 5, height: 5) }
                    Text(day.label).font(.app(10, index == 0 ? .semibold : .medium))
                        .foregroundStyle(index == 0 ? Theme.foreground : Theme.muted)
                }
                .frame(width: Self.dayWidth - 12, height: Self.header, alignment: .leading)
                .offset(x: CGFloat(index) * Self.dayWidth + 8)
            }
            ForEach(Array(Self.events.enumerated()), id: \.offset) { index, event in
                eventView(index, event)
            }
            ForEach(Array(Self.drops.enumerated()), id: \.offset) { _, drop in placeholder(drop) }
            ForEach(Array(Self.runs.enumerated()), id: \.offset) { _, run in runView(run) }
        }
        .frame(width: Self.gridWidth, height: Self.bodyHeight + Self.header, alignment: .topLeading)
        .offset(x: Self.gridX, y: Self.inset)
    }

    private func slot(day: Int, top: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(day) * Self.dayWidth + 4, y: Self.header + top * Self.bodyHeight,
            width: Self.dayWidth - 8, height: height * Self.bodyHeight
        )
    }

    private func eventView(_ index: Int, _ event: (day: Int, top: CGFloat, height: CGFloat)) -> some View {
        let frame = slot(day: event.day, top: event.top, height: event.height)
        // The calendar comes in at the start of each loop, a column at a time.
        let appear = WeekShow.easeOut(WeekShow.progress(t, 0.05 + Double(event.day) * 0.07, 0.45 + Double(event.day) * 0.07))
        let claim = index == Self.claimed ? WeekShow.easeInOut(WeekShow.progress(t, 1.3, 1.9)) * WeekShow.clearing(t) : 0
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(Theme.foreground(0.075))
            RoundedRectangle(cornerRadius: 5).fill(GoalPalette.tintBackground(Self.claimColor)).opacity(claim)
            Capsule().fill(GoalPalette.color(Self.claimColor))
                .frame(width: 2.5, height: max(0, frame.height - 8) * claim)
                .padding(.leading, 3).padding(.top, 4)
            if frame.height > 20 {
                Capsule()
                    .fill(Theme.foreground(0.13).opacity(1 - claim))
                    .overlay(Capsule().fill(GoalPalette.color(Self.claimColor).opacity(0.55 * claim)))
                    .frame(width: frame.width * 0.55, height: 3.5)
                    .padding(.leading, 8).padding(.top, 7)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .scaleEffect(1 + 0.06 * sin(.pi * WeekShow.progress(t, 1.3, 1.9)) * (index == Self.claimed ? 1 : 0))
        .opacity(appear)
        .offset(x: frame.minX, y: frame.minY + 4 * (1 - appear))
    }

    /// Where a project will land, showing while it's carried there: hatched, ringed in its colour.
    private func placeholder(_ drop: Drop) -> some View {
        let frame = slot(day: drop.day, top: drop.top, height: drop.height)
        let color = Self.projects[drop.row].color
        let lands = drop.lift + Self.liftTime + Self.travelTime
        let shown = WeekShow.progress(t, drop.lift, drop.lift + 0.3) * (1 - WeekShow.progress(t, lands, lands + 0.15))
        return Hatch(color: GoalPalette.color(color).opacity(0.3), spacing: 4)
            .clipShape(.rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(GoalPalette.color(color).opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .frame(width: frame.width, height: frame.height)
            .opacity(shown)
            .offset(x: frame.minX, y: frame.minY)
    }

    private func runView(_ run: (day: Int, top: CGFloat, at: Double)) -> some View {
        let frame = slot(day: run.day, top: run.top, height: Self.runHeight)
        let p = WeekShow.progress(t, run.at, run.at + 0.45)
        return block(color: "green", width: frame.width, height: frame.height)
            .scaleEffect(p > 0 ? WeekShow.land(p) * 0.25 + 0.75 : 0.75, anchor: .center)
            .opacity(min(1, p * 3) * WeekShow.clearing(t))
            .offset(x: frame.minX, y: frame.minY)
    }

    /// A block of time for a goal: its colour's wash, a bar of it down the left, a line for its name.
    private func block(color: String, width: CGFloat, height: CGFloat, badge: String? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            // Solid underneath, so a block carried over the week doesn't show what it passes.
            RoundedRectangle(cornerRadius: 5).fill(Theme.card)
            RoundedRectangle(cornerRadius: 5).fill(GoalPalette.tintBackground(color))
            Capsule().fill(GoalPalette.color(color)).frame(width: 2.5, height: max(0, height - 8)).padding(.leading, 3).padding(.top, 4)
            if height > 20 {
                HStack(spacing: 4) {
                    if let badge { GoalIconImage(name: badge, size: 9).foregroundStyle(GoalPalette.color(color)) }
                    Capsule().fill(GoalPalette.color(color).opacity(0.5)).frame(width: width * 0.42, height: 3.5)
                }
                .padding(.leading, 9).padding(.top, 6)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: Dragged

    /// A project carried from its row on the plate to its day: lifted, carried along a gentle arc, set down with a
    /// small settle; then it stays until the loop clears.
    private func dragged(_ drop: Drop) -> some View {
        let row = Self.projects[drop.row]
        let target = slot(day: drop.day, top: drop.top, height: drop.height)
        let from = CGRect(
            x: Self.inset + 10, y: Self.projectsY + CGFloat(drop.row) * Self.rowHeight + 2,
            width: Self.sidebar - 20, height: Self.rowHeight - 4
        )
        let to = target.offsetBy(dx: Self.gridX, dy: Self.inset)
        let lifted = WeekShow.easeOut(WeekShow.progress(t, drop.lift, drop.lift + Self.liftTime))
        let travelStart = drop.lift + Self.liftTime
        let travel = WeekShow.easeInOut(WeekShow.progress(t, travelStart, travelStart + Self.travelTime))
        let landStart = travelStart + Self.travelTime
        let landing = WeekShow.progress(t, landStart, landStart + Self.landTime)
        let frame = CGRect(
            x: from.minX + (to.minX - from.minX) * travel,
            y: from.minY + (to.minY - from.minY) * travel - 26 * sin(.pi * travel),
            width: from.width + (to.width - from.width) * travel,
            height: from.height + (to.height - from.height) * travel
        )
        let carrying = lifted * (1 - landing)
        let settle = landing > 0 ? 1 + 0.06 * sin(.pi * landing) * (1 - landing) : 1
        return block(color: row.color, width: frame.width, height: frame.height, badge: travel > 0.6 ? row.icon : nil)
            .shadow(color: .black.opacity(0.22 * carrying), radius: 10 * carrying, y: 8 * carrying)
            .scaleEffect((1 + 0.05 * carrying) * settle)
            .rotationEffect(.degrees(-2.5 * carrying * (1 - travel)))
            .opacity(lifted * WeekShow.clearing(t))
            .offset(x: frame.minX, y: frame.minY)
    }
}

#Preview("Week intro") {
    FirstRunWeekIntro(weekLabel: "Nov 30 – Dec 6", onStart: {})
        .frame(width: 1280, height: 820)
}
