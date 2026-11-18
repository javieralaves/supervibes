import SwiftUI

/*
 * How goals look: their icon on a tile tinted with their colour, and their status as a coloured
 * dot and word or a strip of days. Matches src/components/goal-badge.tsx, status-pill.tsx and
 * status-trajectory.tsx. The icon and colour lists are generated (GoalPalette.generated.swift).
 */

struct GoalIconGroup: Hashable, Sendable {
    let label: String
    let icons: [GoalIconInfo]
}

struct GoalIconInfo: Hashable, Sendable {
    /// The stored name, e.g. "Rocket01Icon".
    let name: String
    let label: String
    let keywords: String
}

struct GoalColorInfo: Hashable, Sendable {
    let key: String
    let label: String
    let light: String
    let dark: String
}

extension GoalPalette {
    static let allIcons = iconGroups.flatMap(\.icons)

    static func colorInfo(_ key: String) -> GoalColorInfo {
        colors.first { $0.key == key } ?? colors.first { $0.key == defaultColor }!
    }

    /// The goal's colour, light or dark with the appearance.
    static func color(_ key: String) -> Color {
        let info = colorInfo(key)
        return Color.adaptive(light: NSColor(hex: info.light) ?? .gray, dark: NSColor(hex: info.dark) ?? .gray)
    }

    /// `.goal-tint`'s background: the colour at 13% (18% in dark mode).
    static func tintBackground(_ key: String) -> Color {
        let info = colorInfo(key)
        return Color.adaptive(
            light: (NSColor(hex: info.light) ?? .gray).withAlphaComponent(0.13),
            dark: (NSColor(hex: info.dark) ?? .gray).withAlphaComponent(0.18)
        )
    }

    static func iconName(_ name: String) -> String {
        allIcons.contains { $0.name == name } ? name : defaultIcon
    }
}

/// A goal's icon, drawn like the web's (stroke 1.8).
struct GoalIconImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image("Goal-\(GoalPalette.iconName(name))", bundle: Fonts.bundle)
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
    }
}

/// A goal's icon on a tile tinted with its colour.
struct GoalBadge: View {
    enum Size {
        /// `h-6 w-6 rounded-md`, icon 14
        case xs
        /// `h-9 w-9 rounded-lg`, icon 18
        case field
        /// `h-10 w-10 rounded-xl`, icon 20
        case sm
        /// `h-14 w-14 rounded-2xl`, icon 28
        case lg

        var tile: CGFloat { switch self { case .xs: 24; case .field: 36; case .sm: 40; case .lg: 56 } }
        var radius: CGFloat { switch self { case .xs: 6; case .field: 8; case .sm: 12; case .lg: 16 } }
        var icon: CGFloat { switch self { case .xs: 14; case .field: 18; case .sm: 20; case .lg: 28 } }
    }

    let icon: String
    let color: String
    var size: Size = .sm

    var body: some View {
        GoalIconImage(name: icon, size: size.icon)
            .foregroundStyle(GoalPalette.color(color))
            .frame(width: size.tile, height: size.tile)
            .background(GoalPalette.tintBackground(color), in: .rect(cornerRadius: size.radius))
            .animation(.easeOut(duration: 0.15), value: color)
    }
}

// MARK: - Status

enum StatusTone {
    /// Tailwind emerald/amber/red-500, for dots and solid days.
    static func dot(_ status: GoalStatus) -> Color {
        switch status {
        case .onTrack: Color(nsColor: .rgb(0x10b981))
        case .atRisk: Color(nsColor: .rgb(0xf59e0b))
        case .offTrack: Color(nsColor: .rgb(0xef4444))
        case .unclear: Theme.foreground(0.3)
        }
    }

    /// The word's colour: emerald/amber/red-700, or -400 in dark mode.
    static func text(_ status: GoalStatus) -> Color {
        switch status {
        case .onTrack: Color.adaptive(light: .rgb(0x047857), dark: .rgb(0x34d399))
        case .atRisk: Color.adaptive(light: .rgb(0xb45309), dark: .rgb(0xfbbf24))
        case .offTrack: Color.adaptive(light: .rgb(0xb91c1c), dark: .rgb(0xf87171))
        case .unclear: Theme.muted
        }
    }

    /// One day of a trajectory: solid when read that day, lighter when carried, faint when empty.
    static func day(_ day: TrajectoryDay) -> Color {
        guard let status = day.status else { return Theme.foreground(0.06) }
        if status == .unclear { return Theme.foreground(day.carried ? 0.12 : 0.25) }
        return dot(status).opacity(day.carried ? 0.35 : 1)
    }
}

/// A status as a dot and the word in its colour, for dense places like cards.
struct StatusText: View {
    let status: GoalStatus
    let basis: StatusBasis

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(StatusTone.dot(status)).frame(width: 6, height: 6)
            Text(statusLabel(status, basis)).appText(.xs, .medium)
        }
        .foregroundStyle(StatusTone.text(status))
    }
}

/// The last weeks as a thin strip, one cell a day, oldest on the left: `flex h-1.5 gap-px`.
struct TrajectoryStrip: View {
    let days: [TrajectoryDay]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                UnevenRoundedRectangle(
                    topLeadingRadius: index == 0 ? 3 : 0,
                    bottomLeadingRadius: index == 0 ? 3 : 0,
                    bottomTrailingRadius: index == days.count - 1 ? 3 : 0,
                    topTrailingRadius: index == days.count - 1 ? 3 : 0
                )
                .fill(StatusTone.day(day))
            }
        }
        .frame(height: 6)
        .accessibilityLabel(days.contains { $0.status != nil } ? "Status over the last weeks" : "No status yet")
    }
}

/// A status as a small pill: `rounded-full px-2 py-0.5 text-xs font-medium` on a tint of its colour.
struct StatusPill: View {
    let status: GoalStatus
    let basis: StatusBasis

    private var background: Color {
        switch status {
        case .onTrack: Color(nsColor: .rgb(0x10b981, alpha: 0.10))
        case .atRisk: Color(nsColor: .rgb(0xf59e0b, alpha: 0.12))
        case .offTrack: Color(nsColor: .rgb(0xef4444, alpha: 0.10))
        case .unclear: Theme.foreground(0.06)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(StatusTone.dot(status)).frame(width: 6, height: 6)
            Text(statusLabel(status, basis)).appText(.xs, .medium)
        }
        .foregroundStyle(StatusTone.text(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(background, in: .capsule)
        .help(basisLabel(basis))
    }
}

/// What a status is measured against, for a tooltip.
func basisLabel(_ basis: StatusBasis) -> String {
    switch basis {
    case .target: "Judged against the target date"
    case .week: "Judged against this week’s objective"
    case .momentum: "Judged on momentum"
    }
}

/// The last weeks one cell a day (`flex h-3 gap-[3px]`), today ringed, each day's status and why on hover.
struct TrajectoryDays: View {
    let days: [TrajectoryDay]
    let today: String
    @State private var hovered: Int?

    private static let cardWidth: CGFloat = 224
    /// Room above the strip for the card, which sits at the bottom of it.
    private static let cardRoom: CGFloat = 400

    /// `hovered` opens with that day's card showing, for snapshot tests.
    init(days: [TrajectoryDay], today: String, hovered: Int? = nil) {
        self.days = days
        self.today = today
        _hovered = State(initialValue: hovered)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                RoundedRectangle(cornerRadius: 3)
                    .fill(StatusTone.day(day))
                    .overlay {
                        if day.day == today {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.foreground(0.4))
                                .padding(-2)
                        }
                    }
                    .contentShape(.rect)
                    .onHover { inside in
                        if inside { hovered = index } else if hovered == index { hovered = nil }
                    }
            }
        }
        .frame(height: 12)
        .overlay(alignment: .topLeading) {
            // Positioned with offsets from the strip's own size: above the hovered day, and near
            // either end lined up with that end so it stays inside the page.
            GeometryReader { geometry in
                if let hovered, days.indices.contains(hovered) {
                    let width = geometry.size.width
                    let center = (CGFloat(hovered) + 0.5) * width / CGFloat(days.count)
                    let x = hovered < 4 ? 0 : hovered >= days.count - 4 ? width - Self.cardWidth : center - Self.cardWidth / 2
                    // The card at the bottom of a tall box that ends 8pt above the strip, so it sits above
                    // the day whatever its height, with nothing measured.
                    DayCard(day: days[hovered], today: today)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.cardWidth, height: Self.cardRoom, alignment: .bottomLeading)
                        .offset(x: x, y: -Self.cardRoom - 8)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityLabel("Status over the last weeks")
    }

    /// `w-56 rounded-lg border bg-card px-2.5 py-2 shadow`
    private struct DayCard: View {
        let day: TrajectoryDay
        let today: String

        var body: some View {
            let formatted = CalendarDay.format(day.day, today: today)
            let when = CalendarDay.relativeLabel(day.day, today: today)
            VStack(alignment: .leading, spacing: 2) {
                Text(when == formatted ? formatted : "\(formatted) · \(when)")
                    .font(.app(11)).foregroundStyle(Theme.muted)
                Group {
                    if let status = day.status, let basis = day.basis {
                        Text("\(statusLabel(status, basis))\(Text(day.carried ? " · no read this day" : "").foregroundStyle(Theme.muted).fontWeight(.regular))")
                    } else {
                        Text("No status yet")
                    }
                }
                .appText(.xs, .medium).foregroundStyle(Theme.foreground)
                if let reason = day.reason {
                    Text(reason).appText(.xs).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 224, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.card)
                    .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.25)), radius: 12, y: 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
        }
    }
}
