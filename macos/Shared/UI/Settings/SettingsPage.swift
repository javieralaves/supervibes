import SwiftUI

/// The Settings page, matching the web app's src/app/(app)/settings: sleep schedule, clock, usage;
/// plus what the Calendar opens on, session notices and what happens during sessions, which the
/// Mac app added.
struct SettingsPage: View {
    enum Section: Hashable { case sleep, clock }

    @Binding var settings: SleepSettings
    /// The status shown on the card that was changed last.
    var status: (section: Section, state: SaveStatusView.State)?
    var usage: UsageSummary?
    /// What the Calendar opens on; kept on this Mac, so it saves itself rather than through `onChange`.
    var calendar: CalendarViewCard?
    /// Calendar import: which Google calendars, and where imports go; kept on this Mac too.
    var events: CalendarEventsCard?
    /// Notices before sessions; kept on this Mac, so it saves itself rather than through `onChange`.
    var notices: NoticesCard?
    /// What happens as sessions start and end; kept on this Mac too.
    var routine: SessionRoutineCard?
    /// Called with the card a change came from, after `settings` is updated.
    var onChange: (Section) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Settings", lead: "Make Supervibes fit how your days work.")

                VStack(spacing: 12) {
                    sleepCard
                    clockCard
                    if let calendar { calendar }
                    if let events { events }
                    if let notices { notices }
                    if let routine { routine }
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Usage").appText(.lg, .semibold, tracking: -0.02)
                        .foregroundStyle(Theme.foreground)
                    Text("What Supervibes’ calls to Claude cost over the last 30 days. Costs are estimates from token counts.")
                        .appText(.sm)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: 512, alignment: .leading)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    if let usage {
                        UsageSection(summary: usage)
                    } else {
                        RoundedRectangle(cornerRadius: 16).fill(Theme.wash).frame(height: 320)
                    }
                }
                .padding(.top, 56)
            }
            .frame(maxWidth: 768, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 80)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        // The page runs up under the hidden title bar, where macOS 26 otherwise draws its hard scroll edge:
        // a frosted strip with a line under it, across the top of the app's window. Soft just fades.
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func statusView(_ section: Section) -> some View {
        Group {
            if let status, status.section == section {
                SaveStatusView(state: status.state)
            }
        }
    }

    private var sleepCard: some View {
        Card {
            CardHeader(title: "Sleep schedule", description: "Shaded on your calendar, so your awake hours stand out.") {
                statusView(.sleep)
            }
            let clock = settings.effectiveClock
            HStack(alignment: .top, spacing: 12) {
                SelectField(
                    label: "Bedtime", icon: .moon,
                    selection: binding(\.sleepStart, .sleep),
                    options: SleepSettings.times,
                    title: { clock.format(minutes: $0) }
                )
                SelectField(
                    label: "Wake up", icon: .sun,
                    selection: binding(\.wakeTime, .sleep),
                    options: SleepSettings.times,
                    title: { clock.format(minutes: $0) }
                )
            }
            if settings.awakeMinutes > 0 {
                Text("You’re awake \(SleepSettings.hoursLabel(settings.awakeMinutes)) a day, from \(clock.format(minutes: settings.wakeTime)) to \(clock.format(minutes: settings.sleepStart)).")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
        }
    }

    private var clockCard: some View {
        Card {
            CardHeader(title: "Clock", description: "How times show across Supervibes.") {
                statusView(.clock)
            }
            ToggleGroup(
                selection: Binding(
                    get: { settings.effectiveClock },
                    set: { settings.clock = $0; onChange(.clock) }
                ),
                options: [
                    .init(value: .twelveHour, label: "12-hour", detail: Clock.twelveHour.format(minutes: 14 * 60 + 30)),
                    .init(value: .twentyFourHour, label: "24-hour", detail: Clock.twentyFourHour.format(minutes: 14 * 60 + 30)),
                ]
            )
            if settings.clock == nil {
                Text("Following your device for now.")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 12)
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SleepSettings, T>, _ section: Section) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; onChange(section) }
        )
    }
}

// MARK: - Usage

private struct UsageSection: View {
    let summary: UsageSummary

    static let colors: [UsageCall.Feature: Color] = [.progressRead: Theme.viz1, .recap: Theme.viz2, .agenda: Theme.viz3, .areaRead: Theme.viz4]

    var body: some View {
        if summary.calls.isEmpty {
            Card {
                Text("No Claude calls recorded yet. They appear here after the next progress read, session recap or agenda.")
                    .appText(.sm)
                    .foregroundStyle(Theme.muted)
            }
        } else {
            VStack(spacing: 12) {
                Card {
                    HStack(alignment: .top, spacing: 16) {
                        Stat(label: "Spent", value: UsageSummary.money(summary.total), hint: "last \(summary.days) days")
                        Stat(label: "Calls", value: "\(summary.calls.count)")
                        Stat(label: "Average call", value: UsageSummary.money(summary.averageCost))
                        Stat(
                            label: "Tokens",
                            value: "\(UsageSummary.tokens(Double(summary.inputTokens))) in",
                            hint: "\(UsageSummary.tokens(Double(summary.outputTokens))) out"
                        )
                    }
                    if summary.unpriced > 0 {
                        Text("\(summary.unpriced) call\(summary.unpriced == 1 ? "" : "s") used a model without a known price and aren’t in the totals.")
                            .appText(.xs)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 16)
                    }
                    DailyChart(days: summary.daily)
                        .padding(.top, 24)
                }
                byFeature
                byGoal
                recent
            }
        }
    }

    private var byFeature: some View {
        TableCard(title: "By feature", columns: [
            .init("Feature", leading: true), .init("Calls"), .init("Avg in"), .init("Avg out"),
            .init("Avg tools"), .init("Avg time"), .init("Avg cost"), .init("Total"),
        ]) {
            ForEach(summary.byFeature) { row in
                GridRow {
                    HStack(spacing: 8) {
                        Swatch(color: Self.colors[row.feature] ?? Theme.muted)
                        Text("\(row.feature.label)\(Text(" · \(row.trigger)").foregroundStyle(Theme.muted))")
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.calls)")
                    Text(UsageSummary.tokens(row.avgInput))
                    Text(UsageSummary.tokens(row.avgOutput))
                    Text(String(format: "%.1f", row.avgTools))
                    Text(UsageSummary.seconds(milliseconds: row.avgSeconds * 1000))
                    Text(UsageSummary.money(row.avgCost))
                    Text(UsageSummary.money(row.total)).fontWeight(.medium)
                }
                .padding(.vertical, 8)
                TableDivider(row: row.id, last: summary.byFeature.last?.id)
            }
        }
    }

    private var byGoal: some View {
        TableCard(title: "By project or practice", columns: [.init("Project or practice", leading: true), .init("Calls"), .init("Total")]) {
            ForEach(summary.byGoal) { row in
                GridRow {
                    Text(row.title).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.calls)").frame(minWidth: 48, alignment: .trailing)
                    Text(UsageSummary.money(row.total)).fontWeight(.medium).frame(minWidth: 64, alignment: .trailing)
                }
                .padding(.vertical, 8)
                TableDivider(row: row.id, last: summary.byGoal.last?.id)
            }
        }
    }

    private var recent: some View {
        let calls = Array(summary.calls.prefix(25))
        return TableCard(title: "Recent calls", columns: [
            .init("When", leading: true), .init("What", leading: true), .init("For", leading: true),
            .init("In"), .init("Out"), .init("Tools"), .init("Time"), .init("Cost"),
        ]) {
            ForEach(calls) { call in
                GridRow {
                    Text(call.createdAt.webMonthDayTime)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(call.feature.label)\(Text(" · \(call.triggerLabel)").foregroundStyle(Theme.muted))")
                        if call.outcome != "end_turn" {
                            Text("(\(call.outcome.replacingOccurrences(of: "_", with: " ")))")
                                .appText(.xs).foregroundStyle(Theme.muted)
                        }
                    }
                    .lineLimit(1)
                    Text(call.goalTitle ?? "–").foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(UsageSummary.tokens(Double(call.inputTokens)))
                    Text(UsageSummary.tokens(Double(call.outputTokens)))
                    Text("\(call.toolCalls)")
                    Text(UsageSummary.seconds(milliseconds: Double(call.durationMs)))
                    Text(UsageSummary.money(call.cost)).fontWeight(.medium)
                }
                .padding(.vertical, 8)
                TableDivider(row: call.id, last: calls.last?.id)
            }
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).appText(.xs).foregroundStyle(Theme.muted)
            Text(value).appText(.xl, .semibold, tracking: -0.02).monospacedDigit()
                .foregroundStyle(Theme.foreground)
                .padding(.top, 4)
            if let hint {
                Text(hint).appText(.xs).monospacedDigit().foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `h-2.5 w-2.5 rounded-[3px]` in a series colour.
private struct Swatch: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3).fill(color).frame(width: size, height: size)
    }
}

// MARK: Tables

private struct TableColumn {
    let title: String
    let leading: Bool
    init(_ title: String, leading: Bool = false) {
        self.title = title
        self.leading = leading
    }
}

/// A card with a small title and a table: header `text-xs text-muted`, cells `text-[13px]`,
/// rows split by `border-card-border`.
private struct TableCard<Rows: View>: View {
    let title: String
    let columns: [TableColumn]
    @ViewBuilder var rows: Rows

    var body: some View {
        Card {
            Text(title).appText(.sm, .semibold).foregroundStyle(Theme.foreground)
                .padding(.bottom, 12)
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        Text(column.title)
                            .appText(.xs, .medium)
                            .foregroundStyle(Theme.muted)
                            .gridColumnAlignment(column.leading ? .leading : .trailing)
                    }
                }
                .padding(.vertical, 8)
                Rectangle().fill(Theme.cardBorder).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                rows
                    .font(.app(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.foreground)
            }
        }
    }
}

/// The line under a row, except the last.
private struct TableDivider: View {
    let row: String
    let last: String?

    var body: some View {
        if row != last {
            Rectangle().fill(Theme.cardBorder).frame(height: 1).gridCellUnsizedAxes(.horizontal)
        }
    }
}

// MARK: Chart

/// Spend per day, stacked by feature in fixed order, as the web app draws it: a 160pt plot with
/// three round gridlines, 3pt between days, 2pt between segments, and the top end rounded.
private struct DailyChart: View {
    let days: [UsageSummary.Day]
    @State private var hovered: Int?

    private static let height: CGFloat = 160

    /// The features in the key: the ones every account has, and the rest (area reads, the season's reads) once there are some.
    private var legend: [UsageCall.Feature] {
        // Every day lists every feature, so only the ones with calls count as used.
        let used = Set(days.flatMap { $0.parts.filter { $0.calls > 0 }.map(\.feature) })
        let always: Set<UsageCall.Feature> = [.progressRead, .recap, .agenda]
        return UsageCall.Feature.allCases.filter { always.contains($0) || used.contains($0) }
    }

    var body: some View {
        let totals = days.map(\.total)
        let max = Swift.max(totals.max() ?? 0, 0.0001)
        let step = UsageSummary.niceStep(max / 3)
        let top = Swift.max(step * (max / step).rounded(.up), step)
        let lines = (0...3).map { top / 3 * Double($0) }

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("Spend per day").appText(.xs, .medium).foregroundStyle(Theme.foreground)
                ForEach(legend, id: \.self) { feature in
                    HStack(spacing: 6) {
                        Swatch(color: UsageSection.colors[feature] ?? Theme.muted)
                        Text(feature.label).appText(.xs).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 8) {
                // Y axis labels.
                ZStack(alignment: .topTrailing) {
                    ForEach(lines, id: \.self) { value in
                        Text(UsageSummary.money(value))
                            .font(.app(10)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                            .frame(height: 12)
                            .offset(y: Self.height - value / top * Self.height - 6)
                    }
                }
                .frame(width: 48, height: Self.height, alignment: .topTrailing)

                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(lines, id: \.self) { value in
                            Rectangle()
                                .fill(value == 0 ? Theme.lineStrong : Theme.cardBorder)
                                .frame(height: 1)
                                .offset(y: Self.height - value / top * Self.height)
                        }
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                column(day, top: top)
                                    .background(hovered == index ? Theme.wash : .clear, in: .rect(cornerRadius: 3))
                                    .onHover { inside in
                                        if inside { hovered = index } else if hovered == index { hovered = nil }
                                    }
                            }
                        }
                        if let hovered {
                            let columnWidth = geometry.size.width / CGFloat(days.count)
                            let x = (CGFloat(hovered) + 0.5) * columnWidth
                            let flip = Double(hovered) > Double(days.count) * 0.6
                            ChartTooltip(day: days[hovered])
                                .offset(x: flip ? x - 192 - 8 : x + 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .frame(height: Self.height)
            }

            HStack {
                Text(Self.label(days.first?.day))
                Spacer()
                Text(Self.label(days.count > 0 ? days[days.count / 2].day : nil))
                Spacer()
                Text("Today")
            }
            .font(.app(10)).monospacedDigit()
            .foregroundStyle(Theme.muted)
            .padding(.leading, 56)
            .padding(.top, 6)
        }
    }

    private func column(_ day: UsageSummary.Day, top: Double) -> some View {
        let parts = day.parts.filter { $0.cost > 0 }
        let height = day.total / top * Self.height
        return VStack(spacing: 2) {
            ForEach(Array(parts.reversed().enumerated()), id: \.offset) { index, part in
                UnevenRoundedRectangle(
                    topLeadingRadius: index == 0 ? 4 : 0,
                    topTrailingRadius: index == 0 ? 4 : 0
                )
                .fill(UsageSection.colors[part.feature] ?? Theme.muted)
                .frame(height: Swift.max(1, (height - CGFloat(parts.count - 1) * 2) * part.cost / day.total))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .contentShape(.rect)
    }

    static func label(_ date: Date?) -> String {
        date?.webMonthDay ?? ""
    }
}

private struct ChartTooltip: View {
    let day: UsageSummary.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(DailyChart.label(day.day))
                Spacer()
                Text(UsageSummary.money(day.total)).monospacedDigit()
            }
            .appText(.xs, .semibold)
            .foregroundStyle(Theme.foreground)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(day.parts, id: \.feature) { part in
                    HStack(spacing: 6) {
                        Swatch(color: UsageSection.colors[part.feature] ?? Theme.muted, size: 8)
                        Text(part.feature.label).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(part.calls > 0 ? "\(part.calls) · \(UsageSummary.money(part.cost))" : "–").monospacedDigit()
                    }
                    .appText(.xs)
                    .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(12)
        .frame(width: 192)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.12)), radius: 12, y: 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }
}

#Preview("Settings") {
    @Previewable @State var settings = SleepSettings(sleepStart: 23 * 60 + 30, wakeTime: 8 * 60, clock: .twelveHour)
    ScrollView {
        SettingsPage(settings: $settings, usage: UsageSummary(calls: Fixtures.usageCalls, today: Fixtures.referenceNow),
                     calendar: CalendarViewCard(span: .days(3)))
    }
    .background(Theme.background)
    .frame(width: 900, height: 900)
}
