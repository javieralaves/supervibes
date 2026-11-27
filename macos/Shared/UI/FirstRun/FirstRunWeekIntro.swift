import SwiftUI

/// The way into Your week (the design's FsWeekIntro): quieter than the welcome, with the steps row still up top since
/// it's the same flow. It says what's next and why, shows the next screen in miniature so it looks familiar when it
/// comes, and the three things the week asks: what's already booked, time for projects, a rhythm for practices.
struct FirstRunWeekIntro: View {
    /// "Nov 30 – Dec 6".
    let weekLabel: String
    /// The route's row of steps; the week is its last.
    var steps: [String] = FirstRunChoice.week.steps
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FirstRunSteps(current: steps.count - 1, steps: steps)
            VStack(spacing: 0) {
                Text("Your week · \(weekLabel)").font(.app(13, .medium)).foregroundStyle(Theme.muted)
                Text("Now, make room for it")
                    .font(.app(32, .semibold)).tracking(-0.03 * 32)
                    .foregroundStyle(Theme.foreground)
                    .padding(.top, 4)
                Text("What matters only moves once it has time. So next is your week: what’s already booked, and where what matters fits around it, starting with the one ahead.")
                    .font(.app(15.2)).lineSpacing(3.5)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                WeekAheadArt().padding(.top, 36)

                HStack(alignment: .top, spacing: 28) {
                    point(mark: AnyView(Icon.calendar.image(size: 15).foregroundStyle(Theme.foreground)
                        .frame(width: 26, height: 26).background(Theme.card, in: .rect(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder))),
                          title: "What’s already booked",
                          line: "Your Google Calendar as it is. Say which of it is already time for what matters.")
                    point(mark: AnyView(GoalBadge(icon: "Rocket01Icon", color: "violet", size: .xs)),
                          title: "Time for your projects",
                          line: "Drag them into your week, to work on or to set time aside.")
                    point(mark: AnyView(GoalBadge(icon: "RunningShoesIcon", color: "green", size: .xs, round: true)),
                          title: "A rhythm for practices",
                          line: "Each time you put one in counts toward how often you want it.")
                }
                .padding(.top, 32)

                VStack(spacing: 10) {
                    FlowButton(title: "Plan my week", primary: true, action: onStart)
                    HStack(spacing: 4) {
                        Icon.clock.image(size: 13)
                        Text("About 3 min").font(.app(12.5, .medium))
                    }
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 40)
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 48)
        }
        .background(Theme.background)
    }

    private func point(mark: AnyView, title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            mark
            Text(title).font(.app(13.5, .semibold)).tracking(-0.13).foregroundStyle(Theme.foreground).padding(.top, 12)
            Text(line).font(.app(12.5)).lineSpacing(2).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The next screen in miniature: the plate in a column, the week beside it with the calendar's events in grey, holds
/// faded to time to fill, a couple of runs, and a session for a project lifted as if just dropped in.
private struct WeekAheadArt: View {
    private enum Tone { case event, open, violet, amber, green }
    private let blocks: [(day: Int, top: CGFloat, height: CGFloat, tone: Tone, lift: Bool)] = [
        (0, 8, 9, .event, false), (1, 8, 9, .event, false), (2, 8, 9, .event, false), (3, 8, 9, .event, false), (4, 8, 9, .event, false),
        (0, 96, 24, .event, false), (1, 22, 32, .event, false), (2, 60, 16, .event, false), (3, 22, 38, .event, false),
        (4, 70, 22, .event, false), (5, 66, 48, .event, false), (6, 124, 16, .event, false),
        (2, 22, 32, .open, false), (4, 22, 32, .open, false), (2, 96, 28, .amber, false),
        (1, 136, 16, .green, false), (3, 136, 16, .green, false), (0, 22, 34, .violet, true),
    ]
    private let plate = [("Rocket01Icon", "violet", false), ("UserGroupIcon", "sky", false), ("Sofa01Icon", "amber", false),
                         ("Money03Icon", "slate", false), ("PenTool01Icon", "pink", false)]

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Theme.foreground(0.25)).frame(width: 36, height: 4).padding(.bottom, 2)
                ForEach(Array(plate.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        GoalBadge(icon: item.0, color: item.1, size: .micro)
                        Capsule().fill(Theme.foreground(0.12)).frame(height: 4)
                    }
                }
                Capsule().fill(Theme.foreground(0.25)).frame(width: 36, height: 4).padding(.top, 4)
                ForEach(Array([("RunningShoesIcon", "green"), ("LanguageSkillIcon", "indigo")].enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        GoalBadge(icon: item.0, color: item.1, size: .micro, round: true)
                        Capsule().fill(Theme.foreground(0.12)).frame(width: 40, height: 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(width: 118)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { day in
                    VStack(spacing: 0) {
                        Capsule().fill(Theme.foreground(0.2)).frame(width: 20, height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6).frame(height: 18)
                        ZStack(alignment: .top) {
                            ForEach(Array(blocks.filter { $0.day == day }.enumerated()), id: \.offset) { _, block in
                                blockView(block.tone, lift: block.lift)
                                    .frame(height: block.height)
                                    .padding(.horizontal, 4)
                                    .offset(y: block.top)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                    }
                    .overlay(alignment: .leading) { if day > 0 { Rectangle().fill(Theme.cardBorder).frame(width: 1) } }
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        }
        .padding(10)
        .frame(height: 200)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card)
                .shadow(color: .black.opacity(0.12), radius: 20, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    @ViewBuilder private func blockView(_ tone: Tone, lift: Bool) -> some View {
        switch tone {
        case .event: RoundedRectangle(cornerRadius: 4).fill(Theme.foreground(0.06))
        case .open: RoundedRectangle(cornerRadius: 4).fill(.clear).background(Hatch(color: Theme.foreground(0.08), spacing: 5).clipShape(.rect(cornerRadius: 4)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.foreground(0.07)))
        case .violet, .amber, .green:
            let key = tone == .violet ? "violet" : tone == .amber ? "amber" : "green"
            HStack(spacing: 0) {
                Capsule().fill(GoalPalette.color(key)).frame(width: 2).padding(.vertical, 3).padding(.leading, 3)
                Spacer(minLength: 0)
            }
            .background(GoalPalette.tintBackground(key), in: .rect(cornerRadius: 4))
            .shadow(color: lift ? GoalPalette.color(key).opacity(0.45) : .clear, radius: 6, y: 5)
            .offset(y: lift ? -2 : 0)
        }
    }
}
