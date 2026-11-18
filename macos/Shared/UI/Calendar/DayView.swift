import SwiftUI

/*
 * One day, hour by hour, matching src/app/(app)/calendar/day-calendar.tsx: the top bar, the
 * "Anytime" strip of tasks planned or due without a time, then the timeline with sleep shaded,
 * past time washed, blocks filling in as their time passes, and the now line.
 */

/// The timeline's geometry (geometry.ts).
enum DayGrid {
    /// Height of one hour.
    static let hour: CGFloat = 176
    /// Room above midnight and below the last hour so their labels aren't clipped.
    static let pad: CGFloat = 12
    /// Width of the hour-label column.
    static let gutter: CGFloat = 64
    static let height = y(CalendarDayMath.dayMinutes) + pad

    /// Top of a time (minutes after midnight).
    static func y(_ minutes: Int) -> CGFloat { pad + CGFloat(minutes) / 60 * hour }
}

struct DayView: View {
    let data: CalendarData
    /// Days from today.
    let offset: Int
    /// The calendar's clock, to the minute.
    let now: Date
    var error: String?
    var onStep: (Int) -> Void = { _ in }
    var onToday: () -> Void = {}

    private var clock: Clock { data.clock ?? .device }
    private var isToday: Bool { offset == 0 }
    private var shownDay: Date { CalendarDayMath.midnight(offset, from: now) }

    var body: some View {
        VStack(spacing: 0) {
            CalendarTopBar(
                title: shownDay.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_US"))),
                relative: Self.dayLabel(offset),
                showsToday: !isToday,
                onToday: onToday,
                onPrevious: { onStep(-1) },
                onNext: { onStep(1) }
            )

            VStack(spacing: 0) {
                if let error {
                    Text(error).appText(.sm).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Theme.cardBorder).frame(height: 1)
                }
                let strip = data.strip(day: offset, today: now)
                if !strip.isEmpty {
                    DayStrip(items: strip, goals: data.goals, today: CalendarDay.today(now))
                }
                TimelineScroll(data: data, offset: offset, now: now, clock: clock)
            }
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .frame(maxWidth: 768)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }

    /// "Today", "Tomorrow" or "Yesterday"; nil further away.
    static func dayLabel(_ offset: Int) -> String? {
        switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: nil
        }
    }
}

// MARK: - Top bar

/// `h-14 bg-background shadow-[inset_0_-1px_0_var(--card-border)]`: the date, then Today and the arrows.
struct CalendarTopBar: View {
    let title: String
    var relative: String?
    var showsToday: Bool
    var onToday: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.app(15, .semibold)).tracking(-0.15).foregroundStyle(Theme.foreground).lineLimit(1)
                if let relative {
                    Text(relative).appText(.sm).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if showsToday {
                BarButton(action: onToday) { Text("Today").appText(.sm, .medium).padding(.horizontal, 12) }
            }
            HStack(spacing: 4) {
                BarButton(action: onPrevious) { Icon.arrowLeft.image(size: 16).frame(width: 32) }
                    .help("Previous day")
                    .accessibilityLabel("Previous day")
                BarButton(action: onNext) { Icon.arrowRight.image(size: 16).frame(width: 32) }
                    .help("Next day")
                    .accessibilityLabel("Next day")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }

    /// `h-8 rounded-lg border bg-card shadow`, muted until hovered.
    private struct BarButton<Label: View>: View {
        let action: () -> Void
        @ViewBuilder var label: Label
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                label
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                            .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1, y: 1)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? Theme.lineStrong : Theme.cardBorder))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Anytime strip

/// The top of a day: tasks meant for it without a time, and tasks due then.
struct DayStrip: View {
    let items: [StripItem]
    let goals: [CalendarGoal]
    /// Today, "YYYY-MM-DD", for "from Mon" and "Overdue since Mon".
    let today: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("Anytime").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                .frame(width: DayGrid.gutter, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, 12)
            FlowLayout(spacing: 6) {
                ForEach(items) { item in
                    StripChip(item: item, color: goals.first { $0.id == item.task.goalId }?.color ?? "slate", today: today)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
    }
}

/// A task on the strip, tinted with its goal: why it's here (a calendar or a flag), the title, its estimate.
private struct StripChip: View {
    let item: StripItem
    let color: String
    let today: String

    var body: some View {
        let carried = item.carriedFrom.map { "from \(CalendarDay.relativeLabel($0, today: today))" }
        HStack(spacing: 6) {
            (item.due != nil ? Icon.flag : Icon.calendarSmall).image(size: 13)
                .foregroundStyle(item.due == .overdue ? Theme.danger : GoalPalette.color(color))
            Text(item.task.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).lineLimit(1)
            Text(TaskItem.minutesLabel(item.task.minutes)).font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
            if let carried {
                Text(carried).font(.app(11, .medium)).foregroundStyle(Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: 272, alignment: .leading)
        .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: 8))
        .background(Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
        .help(helpText)
    }

    private var helpText: String {
        var lines = [item.task.title]
        if let from = item.carriedFrom { lines.append("Planned from \(CalendarDay.relativeLabel(from, today: today))") }
        else if item.planned { lines.append("Planned for this day") }
        if item.due == .overdue, let due = item.task.dueOn { lines.append("Overdue since \(CalendarDay.relativeLabel(due, today: today))") }
        else if item.due == .due { lines.append("Due this day") }
        return lines.joined(separator: "\n")
    }
}

/// Lays children out in rows, wrapping when the next doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in zip(row.indices, row.xs) {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if x > 0, x + w > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
                x = 0
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].xs.append(x)
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += w + spacing
            rows[rows.count - 1].width = x - spacing
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Timeline

/// The day's hours, scrolled to about an hour before now when it opens on today.
private struct TimelineScroll: View {
    let data: CalendarData
    let offset: Int
    let now: Date
    let clock: Clock

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DayTimeline(data: data, offset: offset, now: now, clock: clock)
            }
            .onAppear { scrollToNow(proxy) }
            .onChange(of: offset) { scrollToNow(proxy) }
        }
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        // Open on the current time, with about an hour of the past above it.
        let target = max(0, CalendarDayMath.minutes(now) / 60 - 1)
        proxy.scrollTo("hour-\(offset == 0 ? target : 7)", anchor: .top)
    }
}

/// The timeline itself: hour lines, sleep, past time, blocks and the now line.
struct DayTimeline: View {
    let data: CalendarData
    let offset: Int
    let now: Date
    let clock: Clock

    var body: some View {
        let nowMinutes = CalendarDayMath.minutes(now)
        let isToday = offset == 0
        // Earlier days are all behind you; later days haven't started.
        let pastUntil: Int? = offset < 0 ? CalendarDayMath.dayMinutes : isToday ? nowMinutes : nil
        let segments = data.blocks.flatMap { DaySegment.of($0, today: now) }.filter { $0.day == offset }

        ZStack(alignment: .topLeading) {
            // Hour lines and labels
            ForEach(0...24, id: \.self) { hour in
                let nearNow = isToday && abs(hour * 60 - nowMinutes) < 14
                ZStack(alignment: .topLeading) {
                    Text(hour < 24 ? clock.formatHour(hour) : "")
                        .font(.app(11)).monospacedDigit().foregroundStyle(Theme.muted)
                        .frame(width: DayGrid.gutter - 8, height: 14, alignment: .trailing)
                        .offset(y: -7)
                        .opacity(nearNow ? 0 : 1)
                    Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.leading, DayGrid.gutter)
                }
                .offset(y: DayGrid.y(hour * 60))
                .id("hour-\(hour)")
            }

            // Sleep
            ForEach(CalendarDayMath.sleepSpans(sleepStart: data.sleepStart, wakeTime: data.wakeTime), id: \.lowerBound) { span in
                SleepShade(showsLabel: span.upperBound - span.lowerBound >= 45)
                    .frame(height: DayGrid.y(span.upperBound) - DayGrid.y(span.lowerBound))
                    .padding(.leading, DayGrid.gutter)
                    .offset(y: DayGrid.y(span.lowerBound))
            }

            // Time that's already gone
            if let pastUntil {
                Rectangle().fill(Theme.foreground(0.03))
                    .frame(height: DayGrid.y(pastUntil) - DayGrid.pad)
                    .padding(.leading, DayGrid.gutter)
                    .offset(y: DayGrid.pad)
            }

            // Intentions and protected time
            ForEach(segments) { segment in
                if let block = data.blocks.first(where: { $0.id == segment.blockId }) {
                    let from = CalendarDayMath.midnight(segment.day, from: now).addingTimeInterval(Double(segment.start) * 60)
                    let to = CalendarDayMath.midnight(segment.day, from: now).addingTimeInterval(Double(segment.end) * 60)
                    let elapsed = to > from ? now.timeIntervalSince(from) / to.timeIntervalSince(from) : 0
                    BlockCardView(
                        block: block,
                        goal: data.goal(block.goalId),
                        start: segment.start,
                        end: segment.end,
                        clock: clock,
                        elapsed: min(max(elapsed, 0), 1)
                    )
                    .frame(height: max(DayGrid.y(segment.end) - DayGrid.y(segment.start) - 2, 14))
                    .padding(.leading, DayGrid.gutter + 4)
                    .padding(.trailing, 8)
                    .offset(y: DayGrid.y(segment.start) + 1)
                }
            }

            // Now
            if isToday {
                NowLine(label: clock.format(minutes: nowMinutes)).offset(y: DayGrid.y(nowMinutes))
            }
        }
        .frame(height: DayGrid.height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Sleep: a fine diagonal hatch, with "Sleep" in the corner when there's room.
private struct SleepShade: View {
    let showsLabel: Bool

    var body: some View {
        Hatch(color: Theme.foreground(0.06), spacing: 7)
            .overlay(alignment: .topLeading) {
                if showsLabel {
                    HStack(spacing: 4) {
                        Icon.moon.image(size: 12)
                        Text("Sleep").font(.app(11, .medium))
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 12)
                    .padding(.top, 8)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Diagonal lines ("/"), 1pt wide, like the web's `repeating-linear-gradient(135deg, …)`.
struct Hatch: View {
    let color: Color
    var spacing: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step = spacing * 2.squareRoot()
            var c: CGFloat = 0
            while c < size.width + size.height {
                path.move(to: CGPoint(x: c, y: 0))
                path.addLine(to: CGPoint(x: c - size.height, y: size.height))
                c += step
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
    }
}

/// The current time: a red line across the day, a dot at its start, and the time in the gutter.
private struct NowLine: View {
    let label: String

    var body: some View {
        ZStack(alignment: .leading) {
            Text(label).font(.app(11, .semibold)).monospacedDigit()
                .foregroundStyle(Color(nsColor: .rgb(0xef4444)))
                .frame(width: DayGrid.gutter - 8, alignment: .trailing)
            Rectangle().fill(Color(nsColor: .rgb(0xef4444))).frame(height: 2)
                .padding(.leading, DayGrid.gutter)
            Circle().fill(Color(nsColor: .rgb(0xef4444))).frame(width: 10, height: 10)
                .offset(x: DayGrid.gutter - 5)
        }
        .frame(height: 14)
        .offset(y: -7)
        .allowsHitTesting(false)
    }
}

// MARK: - A block

/// An intention or protected time on the timeline: filled in up to now, an outline after.
struct BlockCardView: View {
    let block: CalendarBlock
    let goal: CalendarGoal?
    let start: Int
    let end: Int
    let clock: Clock
    /// How much of it has happened, 0 to 1.
    let elapsed: Double

    /// Height a block needs for its title and time on two lines; shorter ones get a single line.
    private static let twoLines: CGFloat = 48

    private var color: String { goal?.color ?? "slate" }
    private var title: String { block.title ?? goal?.title ?? "Protected time" }
    private var time: String { clock.formatRange(start, end) }
    private var isShort: Bool { CGFloat(end - start) / 60 * DayGrid.hour < Self.twoLines }

    var body: some View {
        GeometryReader { geometry in
            let filled = geometry.size.height * elapsed
            ZStack(alignment: .topLeading) {
                // The block, drawn filled: solid for an intention, hatched for protected time.
                Rectangle().fill(block.isIntention
                    ? GoalPalette.mix(color, light: 0.18, dark: 0.24)
                    : GoalPalette.mix(color, light: 0.10, dark: 0.13))
                if !block.isIntention {
                    Hatch(color: GoalPalette.color(color).opacity(0.26))
                }
                // A veil in the card colour over the part that hasn't happened yet.
                Rectangle().fill(Theme.card.opacity(0.72))
                    .frame(height: max(geometry.size.height - filled, 0))
                    .offset(y: filled)
                // The bar down the left edge: solid where time has passed, a soft tint ahead.
                VStack(spacing: 0) {
                    Rectangle().fill(GoalPalette.color(color)).frame(height: filled)
                    Rectangle().fill(GoalPalette.mix(color, light: 0.40, dark: 0.40))
                }
                .frame(width: 3)

                label

                if block.recapWaiting {
                    Circle().fill(GoalPalette.color(color)).frame(width: 6, height: 6)
                        .opacity(block.hasRecapDraft ? 1 : 0.6)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .help(block.hasRecapDraft ? "Recap to review" : "Drafting recap")
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(GoalPalette.color(color).opacity(0.22)))
        }
        .opacity(block.isPending ? 0.6 : 1)
        .help("\(title) · \(time)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(block.isIntention ? (block.taskDone ? "Done" : "Intention") : "Protected time"): \(title), \(time)")
    }

    @ViewBuilder private var label: some View {
        let titleText = Text(title)
            .strikethrough(block.taskDone, color: Theme.foreground(0.25))
            .foregroundStyle(block.taskDone ? Theme.muted : Theme.foreground)
        let tick = Icon.tickHeavy.image(size: 9).foregroundStyle(Theme.background)
            .frame(width: 14, height: 14).background(Theme.foreground, in: .circle)

        if isShort {
            HStack(spacing: 8) {
                if block.taskDone { tick }
                titleText.font(.app(13, .medium)).lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 32)
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    if block.taskDone { tick.padding(.top, 3) }
                    titleText.font(.app(14, .medium)).lineLimit(2)
                }
                Text(time).font(.app(12)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 32)
        }
    }
}

extension GoalPalette {
    /// `color-mix(in oklab, var(--goal) N%, var(--card))`: the goal's colour mixed into the card's,
    /// at its own share in light and dark mode.
    static func mix(_ key: String, light: Double, dark: Double) -> Color {
        let info = colorInfo(key)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let goal = NSColor(hex: isDark ? info.dark : info.light) ?? .gray
            let card: NSColor = isDark ? .rgb(0x131417) : .rgb(0xffffff)
            return card.blended(withFraction: isDark ? dark : light, of: goal) ?? goal
        })
    }
}
