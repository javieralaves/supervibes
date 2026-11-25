import SwiftUI

/*
 * The app's left rail: the main sections, and the account menu at the bottom. It sits on the
 * shell colour, beside the app's window.
 */

/// One of the rail's sections.
struct RailItem: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: Icon

    /// Life, the home page: the goals, then the areas they sit in.
    static let life = RailItem(id: "life", label: "Life", icon: .compass)
    /// Planning a day across goals.
    static let plan = RailItem(id: "plan", label: "Plan", icon: .plan)
    static let calendar = RailItem(id: "calendar", label: "Calendar", icon: .calendar)
    static let connections = RailItem(id: "connections", label: "Connections", icon: .plug)
    static let all = [life, plan, calendar, connections]
}

/// The person shown at the bottom of the rail and in its menu.
struct RailAccount: Hashable {
    let name: String
    let email: String
    let imageURL: URL?

    /// "Javier" from "Javier Alaves", as the web greeting uses it.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

struct Rail: View {
    var active: RailItem?
    var account: RailAccount?
    var isMenuOpen = false
    /// Space at the top for the window's traffic lights.
    var topInset: CGFloat = 0
    var onSelect: (RailItem) -> Void = { _ in }
    var onAccount: () -> Void = {}

    static let width: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            ForEach(RailItem.all) { item in
                RailButton(item: item, isActive: item == active) { onSelect(item) }
            }
            Spacer(minLength: 0)
            Button(action: onAccount) {
                Avatar(name: account?.name ?? " ", imageURL: account?.imageURL)
                    .overlay {
                        if isMenuOpen {
                            Circle().strokeBorder(Theme.foreground(0.2), lineWidth: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account: \(account?.name ?? "")")
        }
        .padding(.top, topInset + 12)
        .padding(.bottom, 12)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
    }
}

/// `h-10 w-10 rounded-xl`; active `bg-foreground/[.08] text-foreground`, else `text-muted`,
/// hover `bg-wash text-foreground`, with the label in a tooltip to the right.
private struct RailButton: View {
    let item: RailItem
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            item.icon.image(size: 20)
                .foregroundStyle(isActive || isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 40, height: 40)
                .background(
                    isActive ? Theme.foreground(0.08) : isHovered ? Theme.wash : .clear,
                    in: .rect(cornerRadius: 12)
                )
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .leading) {
            if isHovered {
                RailTooltip(text: item.label)
                    .fixedSize()
                    .offset(x: 40 + 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(item.label)
    }
}

/// `rounded-lg bg-foreground px-2.5 py-1 text-xs font-medium text-background shadow-sm`
private struct RailTooltip: View {
    let text: String

    var body: some View {
        Text(text).appText(.xs, .medium)
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.foreground)
                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            }
    }
}

/// The account menu, opening to the right of the avatar: who's signed in, Settings, Sign out.
/// `w-64 rounded-xl border bg-card p-1.5 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)]`
struct AccountMenu: View {
    let account: RailAccount?
    var onSettings: () -> Void = {}
    var onSignOut: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Avatar(name: account?.name ?? " ", imageURL: account?.imageURL)
                VStack(alignment: .leading, spacing: 0) {
                    Text(account?.name ?? "").appText(.sm, .semibold).foregroundStyle(Theme.foreground)
                    Text(account?.email ?? "").appText(.xs).foregroundStyle(Theme.muted)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 6)

            MenuRow(icon: .settings, label: "Settings", action: onSettings)
            MenuRow(icon: .logout, label: "Sign out", action: onSignOut)
        }
        .padding(6)
        .frame(width: 256)
        .background {
            // The shadow sits on the panel only, so the text stays crisp.
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }

    /// `h-9 rounded-lg px-2.5 text-sm font-medium`, highlighted `bg-wash`.
    private struct MenuRow: View {
        let icon: Icon
        let label: String
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    icon.image(size: 16).foregroundStyle(Theme.muted)
                    Text(label).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

/// The app's window beside the rail: inset from the edges by 8, rounded, on the page colour.
/// `my-2 mr-2 rounded-xl border border-card-border bg-background shadow-[0_1px_3px_rgb(15_17_20/0.05)]`
struct AppWindowFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
            .background {
                // On a shape behind the window, not the window itself, so page text stays crisp.
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.background)
                    .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.05)), radius: 1.5, y: 1)
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
    }
}

/// The whole window as it opens, on Life: rail, frame and backdrop.
#Preview("Window") {
    HStack(spacing: 0) {
        Rail(active: .life, account: RailAccount(name: "Javi", email: "you@example.com", imageURL: nil), topInset: 28)
        AppWindowFrame {
            ZStack {
                Backdrop()
                LifeHome(firstName: "Javier", goals: Fixtures.lifeGoals, today: "2026-11-18", weeks: Fixtures.goalWeeks,
                         areas: Fixtures.areas, now: Fixtures.referenceNow, actions: GoalCardActions(setObjective: { _ in }))
            }
        }
    }
    .background(Theme.shell)
    .frame(width: 1280, height: 820)
}
