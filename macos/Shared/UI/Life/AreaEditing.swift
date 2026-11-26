import SwiftUI

/*
 * The pieces for changing areas, shared by Life, an area's page and a goal's page: a menu row that shows an area,
 * the icon picker (the goals' icons, drawn without a colour, as areas are), the icon as a button that opens it, and
 * a small dialog for making an area from a menu.
 */

/// An area as a row in a menu: its tile and name, with a tick for the one in force.
struct AreaMenuRow: View {
    let name: String
    let icon: String?
    var isChecked = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    AreaTile(icon: icon, size: 20)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
                Text(name).appText(.sm, .medium).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
                if isChecked { Icon.tick.image(size: 16).foregroundStyle(Theme.foreground) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A row in an area menu that isn't an area: "New area…", "No area".
struct AreaMenuAction: View {
    let icon: Icon
    let title: String
    var isChecked = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.image(size: 16).foregroundStyle(Theme.muted).frame(width: 20)
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                if isChecked { Icon.tick.image(size: 16).foregroundStyle(Theme.foreground) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The areas to put a goal in, then New area… and, when it has one, No area.
struct AreaMenu: View {
    let areas: [Area]
    let selected: String?
    let onPick: (String?) -> Void
    var onNewArea: (() -> Void)?

    var body: some View {
        MenuPanel(width: 232) {
            ForEach(areas) { area in
                AreaMenuRow(name: area.name, icon: area.icon, isChecked: area.id == selected) { onPick(area.id) }
            }
            if let onNewArea {
                if !areas.isEmpty { MenuSeparator() }
                AreaMenuAction(icon: .add, title: "New area…", action: onNewArea)
            }
            if selected != nil {
                MenuSeparator()
                AreaMenuAction(icon: .close, title: "No area") { onPick(nil) }
            }
        }
    }
}

/// The icons an area can have, searchable: the goals' icons, in the text colour, the chosen one on a wash.
struct AreaIconPicker: View {
    let selected: String?
    let onPick: (String) -> Void
    @State private var query = ""

    private var groups: [GoalIconGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return GoalPalette.iconGroups }
        return GoalPalette.iconGroups.compactMap { group in
            let icons = group.icons.filter {
                $0.label.lowercased().contains(q) || $0.keywords.contains(q) || group.label.lowercased().contains(q)
            }
            return icons.isEmpty ? nil : GoalIconGroup(label: group.label, icons: icons)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Icon.search.image(size: 14).foregroundStyle(Theme.muted)
                TextField("", text: $query)
                    .placeholder("Search icons", when: query.isEmpty, font: .app(13), color: Theme.muted)
                    .textFieldStyle(.plain)
                    .font(.app(13))
                    .foregroundStyle(Theme.foreground)
                    .accessibilityLabel("Search icons")
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.foreground(0.03), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
            .padding(8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label).appText(.xs, .medium).foregroundStyle(Theme.muted)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                                ForEach(group.icons, id: \.name) { icon in
                                    IconCell(icon: icon, isSelected: icon.name == selected) { onPick(icon.name) }
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("No icons match “\(query)”.").appText(.sm).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 320, height: 320)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.card)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
        .clipShape(.rect(cornerRadius: 12))
    }

    private struct IconCell: View {
        let icon: GoalIconInfo
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                GoalIconImage(name: icon.name, size: 18)
                    .foregroundStyle(isSelected || isHovered ? Theme.foreground : Theme.foreground(0.7))
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Theme.foreground(0.1) : isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                    .overlay { if isSelected { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.lineStrong) } }
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(icon.label)
            .accessibilityLabel(icon.label)
        }
    }
}

/// An area's tile as a button for the icon picker, with a small chevron on its corner to say so. With no icon
/// yet (a new area), a plus in its place.
struct AreaIconButton: View {
    let icon: String?
    var size: CGFloat = 32
    let onPick: (String) -> Void
    @State private var anchor = CGRect.zero
    @Environment(\.overlays) private var overlays

    var body: some View {
        Button {
            overlays?.showMenu(anchor: anchor, alignLeading: true) {
                AreaIconPicker(selected: icon) { picked in
                    overlays?.dismiss()
                    onPick(picked)
                }
            }
        } label: {
            Group {
                if let icon {
                    AreaTile(icon: icon, size: size)
                } else {
                    Icon.add.image(size: (size * 0.5).rounded())
                        .foregroundStyle(Theme.muted)
                        .frame(width: size, height: size)
                        .background(Theme.foreground(0.06), in: .rect(cornerRadius: (size * 0.3).rounded()))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Icon.chevronDown.image(size: 9)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 16, height: 16)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.cardBorder))
                    .offset(x: 4, y: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(AnchorReader(frame: $anchor))
        .help("Change the icon")
        .accessibilityLabel("Icon")
    }
}

/// A small remove button for an area's corner while editing, red while it's being asked about.
struct AreaRemoveButton: View {
    var help = "Remove"
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.close.image(size: 12)
                .foregroundStyle(isHovered ? Theme.danger : Theme.muted)
                .frame(width: 24, height: 24)
                .background(isHovered ? Theme.danger.opacity(0.1) : Theme.foreground(0.06), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Asks before removing an area, in the same words for every area.
@MainActor
func removeAreaDialog(_ name: String, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) -> ConfirmDialog {
    ConfirmDialog(
        title: "Remove \(name)?",
        message: "Its projects, practices and time stay, just without an area. What you wrote about it is removed.",
        confirmTitle: "Remove",
        onCancel: onCancel,
        onConfirm: onConfirm
    )
}

/// Making an area from a menu (a goal's New area…): a name and an icon; the rest is said on its page.
struct NewAreaDialog: View {
    @State var input = AreaInput()
    var onCancel: () -> Void = {}
    /// Saves; returns why not, or nil once it's made.
    var onSave: (AreaInput) async -> String? = { _ in nil }
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New area").appText(.base, .semibold).foregroundStyle(Theme.foreground)
            HStack(spacing: 12) {
                AreaIconButton(icon: input.icon, size: 36) { input.icon = $0 }
                TextField("", text: $input.name)
                    .textFieldStyle(.plain)
                    .font(.app(15, .semibold))
                    .foregroundStyle(Theme.foreground)
                    .placeholder("Name this area", when: input.name.isEmpty, font: .app(15, .semibold))
                    .focused($nameFocused)
                    .onSubmit(save)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(Theme.card, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(nameFocused ? Theme.lineStrong : Theme.cardBorder))
            }
            .padding(.top, 16)
            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger).padding(.top, 10)
            }
            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel", action: onCancel)
                PrimaryButton(title: isSaving ? "Adding…" : "Add area", isBusy: isSaving, action: save)
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
        .onAppear { nameFocused = true }
        .onEscape(perform: onCancel)
    }

    private func save() {
        if let problem = input.problem {
            error = problem
            return
        }
        isSaving = true
        Task {
            error = await onSave(input)
            isSaving = false
        }
    }
}

#Preview("Icon picker") {
    AreaIconPicker(selected: "LaptopIcon") { _ in }.padding(24).background(Theme.shell)
}

#Preview("Area menu") {
    AreaMenu(areas: Fixtures.areas, selected: "madrid", onPick: { _ in }, onNewArea: {}).padding(24).background(Theme.shell)
}

#Preview("New area") {
    NewAreaDialog().padding(24).background(Theme.shell)
}
