import SwiftUI

/// The Connections page, matching the web app's src/app/(app)/connections: each app, its status,
/// and Connect, or a menu to reconnect or disconnect.
struct ConnectionsPage: View {
    enum Notice: Equatable {
        case connected(String)
        case failed(String)
    }

    let items: [ConnectionItem]
    var notice: Notice?
    /// The app being connected or disconnected right now.
    var busy: ConnectionItem.Provider?
    var onConnect: (ConnectionItem.Provider) -> Void = { _ in }
    var onDisconnect: (ConnectionItem.Provider) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    title: "Connections",
                    lead: "Let Supervibes read activity from the apps where your work happens. Access is read-only, and you decide per goal what counts."
                )

                VStack(spacing: 12) {
                    switch notice {
                    case .connected(let label):
                        Banner(text: "\(label) is connected. Add it as a source on any goal.").padding(.bottom, 12)
                    case .failed(let message):
                        Banner(text: message, tone: .error).padding(.bottom, 12)
                    case nil:
                        EmptyView()
                    }
                    ForEach(items) { item in
                        ConnectionRow(
                            item: item,
                            isBusy: busy == item.provider,
                            onConnect: { onConnect(item.provider) },
                            onDisconnect: { onDisconnect(item.provider) }
                        )
                    }
                }
                .padding(.top, 40)
            }
            .frame(maxWidth: 768, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 80)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

/// `flex items-center gap-4 rounded-2xl border border-card-border bg-card p-5`
private struct ConnectionRow: View {
    let item: ConnectionItem
    let isBusy: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    @Environment(\.overlays) private var overlays
    @State private var menuAnchor = CGRect.zero
    @State private var isMenuOpen = false

    var body: some View {
        HStack(spacing: 16) {
            ProviderMark(provider: item.provider)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.label).appText(.base, .semibold, tracking: -0.01).foregroundStyle(Theme.foreground)
                Text(subtitle).appText(.sm).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }

    private var subtitle: String {
        switch item.state {
        case .notConnected: item.description
        case .connected(let since): "Connected \(since.webDay)"
        case .needsAttention(let message): "Needs attention: \(message ?? "reconnect it.")"
        }
    }

    @ViewBuilder private var trailing: some View {
        if item.isConnected {
            if isBusy {
                ProgressView().controlSize(.small).frame(width: 36, height: 36)
            } else {
                RoundIconButton(icon: .more, isActive: overlays?.presented != nil && isMenuOpen) { openMenu() }
                    .modifier(AnchorReader(frame: $menuAnchor))
                    .accessibilityLabel("\(item.label) options")
            }
        } else if item.configured {
            PrimaryButton(title: isBusy ? "Connecting…" : "Connect", isBusy: isBusy, action: onConnect)
        } else {
            Text("Needs one-time setup").appText(.sm).foregroundStyle(Theme.muted)
        }
    }

    private func openMenu() {
        guard let overlays else { return }
        isMenuOpen = true
        overlays.showMenu(anchor: menuAnchor) {
            MenuPanel {
                MenuItem(icon: .refresh, title: "Reconnect") {
                    overlays.dismiss()
                    onConnect()
                }
                MenuItem(icon: .unlink, title: "Disconnect", isDestructive: true) {
                    overlays.dismiss()
                    confirmDisconnect(overlays)
                }
            }
        }
    }

    private func confirmDisconnect(_ overlays: OverlayCenter) {
        overlays.showDialog {
            ConfirmDialog(
                title: "Disconnect \(item.label)?",
                message: "Supervibes will stop reading from \(item.label). Goal sources that use it will be removed, so progress reads won’t look there anymore. You can connect it again anytime.",
                confirmTitle: "Disconnect",
                onCancel: { overlays.dismiss() },
                onConfirm: {
                    overlays.dismiss()
                    onDisconnect()
                }
            )
        }
    }
}

/// The app's own mark on its tile, like src/components/provider-mark.tsx (`h-10 w-10 rounded-xl`).
struct ProviderMark: View {
    let provider: ConnectionItem.Provider
    var size: CGFloat = 40

    var body: some View {
        let mark = size * 0.55
        Group {
            switch provider {
            case .linear:
                Icon.linearMark.image(size: mark).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color(nsColor: .rgb(0x5e6ad2)))
            case .github:
                Icon.githubMark.image(size: mark).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color(nsColor: .rgb(0x181717)))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3).strokeBorder(.white.opacity(0.1)))
            case .granola:
                Icon.granolaMark.image(size: size)
            }
        }
        .clipShape(.rect(cornerRadius: size * 0.3))
        .accessibilityHidden(true)
    }
}

#Preview("Connections") {
    ConnectionsPage(items: Fixtures.connections, notice: .connected("Linear"))
        .background(Theme.background)
        .frame(width: 900, height: 620)
}
