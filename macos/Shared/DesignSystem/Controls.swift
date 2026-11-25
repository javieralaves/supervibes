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
        .inactive(isBusy)
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
                .compositingGroup()
                .opacity(isBusy ? 0.6 : 1)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .inactive(isBusy)
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

/// The compact "more" button: `h-6 w-6 rounded-full border bg-card text-foreground/70 shadow`.
struct SmallMoreButton: View {
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.more.image(size: 14)
                .foregroundStyle(isHovered || isActive ? Theme.foreground : Theme.foreground(0.7))
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(Theme.card).shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.08)), radius: 1, y: 1)
                }
                .overlay(Circle().strokeBorder(isHovered || isActive ? Theme.lineStrong : Theme.cardBorder))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Options")
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
    var isDisabled = false
    /// The choice in force, of several: a tick on the right.
    var isChecked = false
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.overlays) private var overlays
    @Environment(\.isSubmenu) private var isSubmenu

    var body: some View {
        Button(action: action) {
            MenuRowLabel(icon: icon, title: title, isDestructive: isDestructive, isHighlighted: isHovered && !isDisabled, showsTick: isChecked)
                .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .inactive(isDisabled)
        .onHover { hovering in
            isHovered = hovering
            // On another row of a menu with a submenu open: that submenu closes.
            if hovering, !isSubmenu { overlays?.hoverRow(id: title, row: .zero, submenu: nil) }
        }
    }
}

/// A row that opens a further menu beside its own, on hover or click, with a chevron on the right,
/// like a macOS submenu: a day for a task, its due date, its estimate.
struct SubmenuItem<Submenu: View>: View {
    let icon: Icon
    let title: String
    @ViewBuilder let submenu: () -> Submenu
    @State private var isHovered = false
    @State private var frame = CGRect.zero
    @Environment(\.overlays) private var overlays

    private var isOpen: Bool { overlays?.submenu?.id == title }

    var body: some View {
        Button {
            overlays?.showSubmenu(id: title, row: frame, content: AnyView(submenu()))
        } label: {
            MenuRowLabel(icon: icon, title: title, isHighlighted: isHovered || isOpen, showsChevron: true)
        }
        .buttonStyle(.plain)
        .modifier(AnchorReader(frame: $frame))
        .onHover { hovering in
            isHovered = hovering
            if hovering { overlays?.hoverRow(id: title, row: frame, submenu: AnyView(submenu())) }
        }
    }
}

/// A menu row's look: icon, title, and a chevron for one that opens a submenu.
private struct MenuRowLabel: View {
    let icon: Icon
    let title: String
    var isDestructive = false
    var isHighlighted = false
    var showsChevron = false
    var showsTick = false

    var body: some View {
        HStack(spacing: 10) {
            icon.image(size: 16).foregroundStyle(isDestructive ? Theme.danger : Theme.muted)
            Text(title).appText(.sm, .medium).foregroundStyle(isDestructive ? Theme.danger : Theme.foreground)
            Spacer(minLength: 0)
            if showsChevron {
                Icon.arrowRight.image(size: 14).foregroundStyle(Theme.muted)
            }
            if showsTick {
                Icon.tick.image(size: 16).foregroundStyle(Theme.foreground)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(isHighlighted ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
        .compositingGroup()
        .contentShape(.rect(cornerRadius: 8))
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
                GhostButton(title: "Cancel", action: onCancel).inactive(isBusy)
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
        /// Below `anchor`, its right edge lined up with the anchor's (`align="end"`), or its left
        /// edge with the anchor's (`align="start"`).
        case menu(anchor: CGRect, leading: Bool)
        /// Centred over a dimmed window.
        case dialog
        /// Below `anchor`, right edges lined up, while the pointer is over it: it takes no clicks
        /// and no pointer, so the page under it keeps its hover.
        case hoverCard(anchor: CGRect)
        /// Its top left corner at `point` (where a right-click was), moved up or left to stay in the window.
        case point(CGPoint)
    }

    struct Presented {
        let placement: Placement
        let content: AnyView
        /// Whether clicking outside closes it (not while a dialog is busy).
        var dismissible = true
        /// Who opened it, e.g. a task's id, so that row can stay active while it's open.
        var owner: String?
    }

    private(set) var presented: Presented?

    /// What a right-click can open a menu on, by the frame it last had: see `contextPanel`.
    @ObservationIgnored var contextTargets: [UUID: ContextTarget] = [:]
    /// The menu showing, in the overlay layer: a right-click on it doesn't open what's under it, and
    /// a submenu opens beside it.
    var presentedFrame: CGRect = .zero

    /// A menu opened beside the one showing, from one of its rows.
    struct Submenu {
        /// The row that opened it.
        let id: String
        /// That row's frame in the overlay layer, which the submenu lines up with.
        let row: CGRect
        let content: AnyView
    }

    private(set) var submenu: Submenu?
    /// The submenu, in the overlay layer, so a right-click on it doesn't open what's under it.
    @ObservationIgnored var submenuFrame: CGRect = .zero
    /// The pointer is over the submenu: moving to it across other rows doesn't close it.
    @ObservationIgnored var isOverSubmenu = false {
        didSet { if isOverSubmenu { pendingSubmenu?.cancel() } }
    }
    @ObservationIgnored private var pendingSubmenu: Task<Void, Never>?

    func showMenu(anchor: CGRect, owner: String? = nil, alignLeading: Bool = false, @ViewBuilder content: () -> some View) {
        closeSubmenu()
        presented = Presented(placement: .menu(anchor: anchor, leading: alignLeading), content: AnyView(content()), owner: owner)
    }

    /// A menu at the pointer, from a right-click.
    func showMenu(at point: CGPoint, owner: String? = nil, @ViewBuilder content: () -> some View) {
        closeSubmenu()
        presented = Presented(placement: .point(point), content: AnyView(content()), owner: owner)
    }

    /// Swaps what the menu showing holds, where it is (a pill's day menu moving on to a calendar).
    func replaceMenu(@ViewBuilder content: () -> some View) {
        guard let presented else { return }
        closeSubmenu()
        self.presented = Presented(placement: presented.placement, content: AnyView(content()), owner: presented.owner)
    }

    // MARK: Submenus

    /// Opens a row's submenu beside the menu now (a click on the row).
    func showSubmenu(id: String, row: CGRect, content: AnyView) {
        pendingSubmenu?.cancel()
        submenu = Submenu(id: id, row: row, content: content)
    }

    /// Swaps what the submenu holds, where it is (its day list moving on to a calendar).
    func replaceSubmenu(@ViewBuilder content: () -> some View) {
        guard let submenu else { return }
        self.submenu = Submenu(id: submenu.id, row: submenu.row, content: AnyView(content()))
    }

    func closeSubmenu() {
        pendingSubmenu?.cancel()
        submenu = nil
        isOverSubmenu = false
    }

    /// The pointer came onto a row of the menu: after a moment, that row's submenu opens (or, for a
    /// row without one, the open one closes), unless the pointer has reached the open submenu by
    /// then, crossing other rows on the way, as macOS menus allow.
    func hoverRow(id: String, row: CGRect, submenu content: AnyView?) {
        pendingSubmenu?.cancel()
        if submenu?.id == id { return }
        if submenu == nil, content == nil { return }
        let delay: Duration = submenu == nil ? .milliseconds(60) : .milliseconds(220)
        pendingSubmenu = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, !self.isOverSubmenu else { return }
            if let content {
                self.submenu = Submenu(id: id, row: row, content: content)
            } else {
                self.closeSubmenu()
            }
        }
    }

    /// A right-click (or Control-click) at `point` in the overlay layer: opens the menu of the
    /// innermost target under it. False when there's none, so the click goes on as usual.
    func openContextMenu(at point: CGPoint) -> Bool {
        if let presented {
            if case .dialog = presented.placement { return false }
            // On the menu itself: nothing more to open.
            if presentedFrame.contains(point) { return true }
            if submenu != nil, submenuFrame.contains(point) { return true }
        }
        let hits = contextTargets.values.filter { $0.isEnabled && $0.frame.contains(point) }
        guard let target = hits.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return false }
        target.open(point)
        return true
    }

    func showHoverCard(anchor: CGRect, owner: String, @ViewBuilder content: () -> some View) {
        closeSubmenu()
        presented = Presented(placement: .hoverCard(anchor: anchor), content: AnyView(content()), owner: owner)
    }

    /// Hides the hover card `owner` opened, leaving anything else showing.
    func dismissHoverCard(owner: String) {
        guard let presented, presented.owner == owner, case .hoverCard = presented.placement else { return }
        self.presented = nil
    }

    func showDialog(dismissible: Bool = true, @ViewBuilder content: () -> some View) {
        closeSubmenu()
        presented = Presented(placement: .dialog, content: AnyView(content()), dismissible: dismissible)
    }

    func dismiss() {
        closeSubmenu()
        presented = nil
    }
}

extension EnvironmentValues {
    @Entry var overlays: OverlayCenter? = nil
    /// Inside a submenu: its rows leave it open as the pointer moves over them.
    @Entry var isSubmenu = false
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
    @Environment(\.staticRendering) private var staticRendering

    func body(content: Content) -> some View {
        content
            .environment(\.overlays, center)
            .coordinateSpace(.overlayHost)
            .overlay {
                if let presented = center.presented {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            if isHoverCard(presented) {
                                // Fills the window so the card's guides measure from its corner, and takes no pointer.
                                Color.clear.allowsHitTesting(false)
                            } else {
                                Color.black.opacity(isDialog(presented) ? 0.4 : 0.001)
                                    .contentShape(.rect)
                                    .onTapGesture { if presented.dismissible { center.dismiss() } }
                            }
                            switch presented.placement {
                            case .menu(let anchor, let leading):
                                AnchoredMenu(content: presented.content, anchor: anchor, leading: leading, bounds: geometry.size) { if center.presentedFrame != $0 { center.presentedFrame = $0 } }
                            case .point(let point):
                                PointMenu(content: presented.content, point: point, bounds: geometry.size) { if center.presentedFrame != $0 { center.presentedFrame = $0 } }
                            case .dialog:
                                presented.content
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            case .hoverCard(let anchor):
                                presented.content
                                    .fixedSize()
                                    .alignmentGuide(.leading) { $0[.trailing] - anchor.maxX }
                                    .alignmentGuide(.top) { _ in -(anchor.maxY + 6) }
                                    .allowsHitTesting(false)
                            }
                            if let submenu = center.submenu {
                                SubmenuPlacement(
                                    content: submenu.content, row: submenu.row, menu: center.presentedFrame, bounds: geometry.size,
                                    onFrame: { center.submenuFrame = $0 },
                                    onHover: { center.isOverSubmenu = $0 }
                                )
                                .environment(\.isSubmenu, true)
                                .id(submenu.id)
                            }
                        }
                    }
                    // What's drawn here sits outside `content`'s environment and coordinate space: give it
                    // both, so a menu can close itself or open a submenu, and measure its rows where its
                    // anchors are measured. The layer covers `content` exactly, so the space is the same.
                    .environment(\.overlays, center)
                    .coordinateSpace(.overlayHost)
                    .transition(.opacity)
                }
            }
            .background {
                if !staticRendering { SecondaryClickWatcher(center: center) }
            }
            .animation(staticRendering ? nil : .easeOut(duration: 0.14), value: center.presented != nil)
    }

    private func isDialog(_ presented: OverlayCenter.Presented) -> Bool {
        if case .dialog = presented.placement { return true }
        return false
    }

    private func isHoverCard(_ presented: OverlayCenter.Presented) -> Bool {
        if case .hoverCard = presented.placement { return true }
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

// MARK: - Right-click menus

/*
 * Right-click (a two-finger click, or Control-click) opens the same panel a ⋯ button does, at the
 * pointer. Views that have a menu say so with `contextPanel`, which keeps their frame in the overlay
 * layer up to date; one watcher on the window catches the click, finds the innermost such view under
 * the pointer and opens its menu there. Left clicks and drags never pass through it.
 */

/// A view a right-click can open a menu on: where it is, and how to open its menu.
final class ContextTarget {
    var frame: CGRect = .zero
    var isEnabled = true
    var open: (CGPoint) -> Void = { _ in }
}

extension View {
    /// Right-clicking this view opens `menu` (a `MenuPanel`) at the pointer. `owner` tags the menu as
    /// a ⋯ menu's does, so the view can stay highlighted while it's open.
    func contextPanel(owner: String? = nil, isEnabled: Bool = true, @ViewBuilder _ menu: @escaping () -> some View) -> some View {
        modifier(ContextPanel(owner: owner, isEnabled: isEnabled, menu: { AnyView(menu()) }))
    }
}

private struct ContextPanel: ViewModifier {
    let owner: String?
    let isEnabled: Bool
    let menu: () -> AnyView

    @Environment(\.overlays) private var overlays
    @Environment(\.staticRendering) private var staticRendering
    @State private var id = UUID()
    @State private var target = ContextTarget()

    func body(content: Content) -> some View {
        // Kept current with each render, so the menu opens on the view as it is now.
        let _ = update()
        if staticRendering || overlays == nil {
            content
        } else {
            content
                .onGeometryChange(for: CGRect.self) { proxy in
                    // Only the part that shows: a row scrolled under a header can't be right-clicked.
                    let frame = proxy.frame(in: .overlayHost)
                    guard let visible = proxy.bounds(of: .scrollView) else { return frame }
                    return frame.intersection(visible.offsetBy(dx: frame.minX, dy: frame.minY))
                } action: { target.frame = $0 }
                .onAppear { overlays?.contextTargets[id] = target }
                .onDisappear { overlays?.contextTargets[id] = nil }
        }
    }

    private func update() {
        target.isEnabled = isEnabled
        let owner = owner
        let menu = menu
        target.open = { [weak overlays] point in
            overlays?.showMenu(at: point, owner: owner) { menu() }
        }
    }
}

/// A menu opened from a button: below it, lined up with its left or right edge, or above it where the window
/// ends below, and moved sideways to stay in the window.
private struct AnchoredMenu: View {
    let content: AnyView
    let anchor: CGRect
    let leading: Bool
    let bounds: CGSize
    let onFrame: (CGRect) -> Void

    @State private var size = CGSize.zero
    @Environment(\.staticRendering) private var staticRendering
    private static let margin: CGFloat = 8
    private static let gap: CGFloat = 6

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // Inside the offset, so the frame is where it's drawn, not where it's laid out.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .overlayHost) } action: { onFrame($0) }
            .offset(x: x, y: y)
            // Hidden for the one pass before it's measured, so it never shows in the wrong place.
            .opacity(size == .zero && !staticRendering ? 0 : 1)
    }

    private var x: CGFloat {
        let x = leading ? anchor.minX : anchor.maxX - size.width
        return max(Self.margin, min(x, bounds.width - size.width - Self.margin))
    }

    private var y: CGFloat {
        let below = anchor.maxY + Self.gap
        if below + size.height <= bounds.height - Self.margin { return below }
        let above = anchor.minY - Self.gap - size.height
        if above >= Self.margin { return above }
        // Fits neither way: as low as it can go and still end inside the window.
        return max(Self.margin, bounds.height - size.height - Self.margin)
    }
}

/// A menu opened at the pointer: down and to the right of it, or up or to the left where the window ends.
private struct PointMenu: View {
    let content: AnyView
    let point: CGPoint
    let bounds: CGSize
    let onFrame: (CGRect) -> Void

    @State private var size = CGSize.zero
    private static let margin: CGFloat = 8

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // Inside the offset, so the frame is where it's drawn, not where it's laid out.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .overlayHost) } action: { onFrame($0) }
            .offset(x: x, y: y)
            .opacity(size == .zero ? 0 : 1)
    }

    private var x: CGFloat {
        let right = point.x + 2
        if right + size.width <= bounds.width - Self.margin { return right }
        return max(Self.margin, min(point.x - size.width - 2, bounds.width - size.width - Self.margin))
    }

    private var y: CGFloat {
        let below = point.y + 2
        if below + size.height <= bounds.height - Self.margin { return below }
        return max(Self.margin, min(point.y - size.height - 2, bounds.height - size.height - Self.margin))
    }
}

/// A submenu: beside its menu, to the right or, where the window ends, to the left, its first row
/// level with the row that opened it, and moved up to stay in the window.
private struct SubmenuPlacement: View {
    let content: AnyView
    let row: CGRect
    /// The menu it opened from.
    let menu: CGRect
    let bounds: CGSize
    let onFrame: (CGRect) -> Void
    let onHover: (Bool) -> Void

    @State private var size = CGSize.zero
    private static let margin: CGFloat = 8
    /// How far it overlaps its menu's edge, as a macOS submenu does.
    private static let overlap: CGFloat = 2

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // Inside the offset, so the frame is where it's drawn, not where it's laid out.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .overlayHost) } action: { onFrame($0) }
            .offset(x: x, y: y)
            .opacity(size == .zero ? 0 : 1)
            .onHover(perform: onHover)
    }

    private var x: CGFloat {
        let right = menu.maxX - Self.overlap
        if right + size.width <= bounds.width - Self.margin { return right }
        return max(Self.margin, menu.minX + Self.overlap - size.width)
    }

    /// The panel's padding (6) above its first row, so that row lines up with the one that opened it.
    private var y: CGFloat {
        let top = row.minY - 6
        return max(Self.margin, min(top, bounds.height - size.height - Self.margin))
    }
}

/// Catches right-clicks and Control-clicks in the overlay host's window and hands them to the overlay
/// layer. Anything it doesn't open a menu for goes on as usual.
private struct SecondaryClickWatcher: NSViewRepresentable {
    let center: OverlayCenter

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.center = center
        return view
    }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.center = center
    }

    final class WatcherView: NSView {
        weak var center: OverlayCenter?
        private var monitor: Any?

        // Only watches: it never takes a click itself.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                // Read what's needed here: an NSEvent can't cross into the main actor's closure.
                let location = event.locationInWindow
                let isSecondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                let windowNumber = event.windowNumber
                let handled = MainActor.assumeIsolated {
                    self?.handle(location: location, isSecondary: isSecondary, windowNumber: windowNumber) ?? false
                }
                return handled ? nil : event
            }
        }

        /// True when it opened a menu, which ends the click there.
        private func handle(location: NSPoint, isSecondary: Bool, windowNumber: Int) -> Bool {
            guard isSecondary, let center, let window, window.windowNumber == windowNumber else { return false }
            let local = convert(location, from: nil)
            guard bounds.contains(local) else { return false }
            let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
            return center.openContextMenu(at: point)
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}

// MARK: - Placeholders

extension View {
    /// The web's `placeholder:text-muted/70` for a field: macOS draws a TextField's own prompt in
    /// the system colour, so fields pass an empty prompt and this draws the placeholder instead.
    func placeholder(_ text: String, when isEmpty: Bool, font: Font, color: Color = Theme.muted.opacity(0.7)) -> some View {
        overlay(alignment: .topLeading) {
            if isEmpty {
                Text(text).font(font).foregroundStyle(color).allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Inactive controls

extension View {
    /// Stops a control responding without SwiftUI's own disabled look, which dims a button's text
    /// on top of the fade the design already gives it. Pair it with that fade, applied to the whole
    /// control as one (`compositingGroup()` then `opacity`), like the web's `disabled:opacity-*`.
    func inactive(_ isInactive: Bool) -> some View {
        allowsHitTesting(!isInactive)
            .accessibilityAddTraits(isInactive ? .isStaticText : [])
    }
}
