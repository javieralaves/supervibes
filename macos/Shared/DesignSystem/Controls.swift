import SwiftUI

/*
 * Buttons, banners, menus and dialogs matching the web app's. Menus and dialogs draw in the
 * window's overlay layer (`OverlayCenter`), so they can sit above everything like the web's
 * Radix portals.
 */

// MARK: - Buttons

/// The main action: `h-10 rounded-xl bg-foreground px-4 text-sm font-semibold text-background`.
struct PrimaryButton: View {
    let title: String
    var icon: Icon?
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.mini).tint(Theme.background)
                } else if let icon {
                    icon.image(size: 16)
                }
                Text(title).appText(.sm, .semibold)
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Theme.foreground, in: .rect(cornerRadius: 12))
            .opacity(isHovered && !isBusy ? 0.9 : 1)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovered = $0 }
    }
}

/// A quiet button: `h-10 rounded-xl px-4 text-sm font-medium hover:bg-wash`.
struct GhostButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, .medium)
                .foregroundStyle(Theme.foreground)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 12))
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A destructive confirm: `h-10 rounded-xl bg-red-600 px-4 text-sm font-semibold text-white`.
struct DangerButton: View {
    let title: String
    var isBusy = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title).appText(.sm, .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Color(nsColor: .rgb(isHovered ? 0xb91c1c : 0xdc2626)), in: .rect(cornerRadius: 12))
                .opacity(isBusy ? 0.6 : 1)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovered = $0 }
    }
}

/// The round "more options" button: `h-9 w-9 rounded-full border bg-card text-foreground/70 shadow`.
struct RoundIconButton: View {
    let icon: Icon
    var isActive = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.image(size: 18)
                .foregroundStyle(isHovered || isActive ? Theme.foreground : Theme.foreground(0.7))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(Theme.card)
                        .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.06)), radius: 1, y: 1)
                        .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.10)), radius: 3, y: 2)
                }
                .overlay(Circle().strokeBorder(isHovered || isActive ? Theme.lineStrong : Theme.cardBorder))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Banner

/// A one-line notice above a list: neutral, or red for errors.
struct Banner: View {
    enum Tone { case neutral, error }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text).appText(.sm)
            .foregroundStyle(tone == .error ? Color.adaptive(light: .rgb(0xb91c1c), dark: .rgb(0xfca5a5)) : Theme.foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tone == .error ? Color(nsColor: .rgb(0xef4444, alpha: 0.07)) : Theme.card,
                in: .rect(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(tone == .error ? Color(nsColor: .rgb(0xef4444, alpha: 0.2)) : Theme.cardBorder)
            )
    }
}

// MARK: - Menus

/// A row in a dropdown: `h-9 rounded-lg px-2.5 text-sm font-medium`, highlighted `bg-wash`;
/// destructive rows are red.
struct MenuItem: View {
    let icon: Icon
    let title: String
    var isDestructive = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.image(size: 16).foregroundStyle(isDestructive ? Theme.danger : Theme.muted)
                Text(title).appText(.sm, .medium).foregroundStyle(isDestructive ? Theme.danger : Theme.foreground)
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

/// The dropdown panel: `rounded-xl border bg-card p-1.5 shadow-[0_12px_32px_-12px_rgb(0_0_0/0.25)]`.
struct MenuPanel<Content: View>: View {
    var width: CGFloat = 192
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(6)
            .frame(width: width)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }
}

// MARK: - Dialog

/// A small confirmation for destructive actions, like the web's ConfirmDialog.
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var busyTitle: String?
    var isBusy = false
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).appText(.base, .semibold).foregroundStyle(Theme.foreground)
            Text(message).appText(.sm).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel", action: onCancel).disabled(isBusy)
                DangerButton(title: isBusy ? (busyTitle ?? confirmTitle) : confirmTitle, isBusy: isBusy, action: onConfirm)
            }
            .padding(.top, 24)
        }
        .padding(24)
        .frame(width: 384)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.background)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
    }
}

// MARK: - Overlay layer

/// Shows menus and dialogs above the app's window content. One at a time, like the web.
@MainActor
@Observable
final class OverlayCenter {
    enum Placement {
        /// Below `anchor`, its right edge lined up with the anchor's (`align="end"`).
        case menu(anchor: CGRect)
        /// Centred over a dimmed window.
        case dialog
    }

    struct Presented {
        let placement: Placement
        let content: AnyView
        /// Whether clicking outside closes it (not while a dialog is busy).
        var dismissible = true
    }

    private(set) var presented: Presented?

    func showMenu(anchor: CGRect, @ViewBuilder content: () -> some View) {
        presented = Presented(placement: .menu(anchor: anchor), content: AnyView(content()))
    }

    func showDialog(dismissible: Bool = true, @ViewBuilder content: () -> some View) {
        presented = Presented(placement: .dialog, content: AnyView(content()), dismissible: dismissible)
    }

    func dismiss() {
        presented = nil
    }
}

extension EnvironmentValues {
    @Entry var overlays: OverlayCenter? = nil
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The space menus are positioned in; set by `overlayHost`.
    static var overlayHost: NamedCoordinateSpace { .named("overlayHost") }
}

extension View {
    /// Makes this view the layer menus and dialogs from `center` draw in.
    func overlayHost(_ center: OverlayCenter) -> some View {
        modifier(OverlayHost(center: center))
    }
}

private struct OverlayHost: ViewModifier {
    let center: OverlayCenter

    func body(content: Content) -> some View {
        content
            .environment(\.overlays, center)
            .coordinateSpace(.overlayHost)
            .overlay {
                if let presented = center.presented {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(isDialog(presented) ? 0.4 : 0.001)
                                .contentShape(.rect)
                                .onTapGesture { if presented.dismissible { center.dismiss() } }
                            switch presented.placement {
                            case .menu(let anchor):
                                presented.content
                                    .fixedSize()
                                    .alignmentGuide(.leading) { $0[.trailing] - anchor.maxX }
                                    .alignmentGuide(.top) { _ in -(anchor.maxY + 6) }
                            case .dialog:
                                presented.content
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.14), value: center.presented != nil)
    }

    private func isDialog(_ presented: OverlayCenter.Presented) -> Bool {
        if case .dialog = presented.placement { return true }
        return false
    }
}

/// Reports a view's frame in the overlay layer, for anchoring a menu to it.
struct AnchorReader: ViewModifier {
    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .overlayHost) } action: { frame = $0 }
    }
}
