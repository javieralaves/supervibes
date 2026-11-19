import SwiftUI

/// Settings' "During sessions" card (Shared/Models/SessionRoutine.swift): turn on Do Not Disturb,
/// quit apps, and run your own Shortcuts, as a session starts and undone once it's over. Kept on
/// this Mac, like session notices.
struct SessionRoutineCard: View {
    let routine: SessionRoutine
    /// The Shortcuts on this Mac; nil while they're being listed.
    let shortcuts: [String]?
    /// Apps open now, offered in "Add app".
    var openApps: [SessionRoutine.App] = []
    var onChange: (SessionRoutine) -> Void = { _ in }
    var onAddFocusShortcut: () -> Void = {}
    var onChooseApp: () -> Void = {}
    var onOpenShortcuts: () -> Void = {}
    var onOpenFocusSettings: () -> Void = {}

    var body: some View {
        Card {
            CardHeader(
                title: "During sessions",
                description: "What Supervibes does as a session starts, undone once it’s over. Sessions close together count as one."
            )

            VStack(alignment: .leading, spacing: 0) {
                doNotDisturb
                Divider().overlay(Theme.cardBorder).padding(.vertical, 20)
                apps
                Divider().overlay(Theme.cardBorder).padding(.vertical, 20)
                ownShortcuts
            }
        }
    }

    // MARK: Do Not Disturb

    private var focusAdded: (on: Bool, off: Bool)? {
        shortcuts.map { ($0.contains(SessionRoutine.focusOn), $0.contains(SessionRoutine.focusOff)) }
    }

    private var doNotDisturb: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowHeader(title: "Turn on Do Not Disturb", detail: "Silences notifications until the session’s over.") {
                Switch(label: "Turn on Do Not Disturb", isOn: routine.doNotDisturb) { on in
                    var new = routine
                    new.doNotDisturb = on
                    onChange(new)
                }
            }

            if routine.doNotDisturb, let added = focusAdded {
                if added.on && added.off {
                    Note {
                        Text("Allow Supervibes in Do Not Disturb to keep getting session notices.")
                        LinkButton("Focus settings", action: onOpenFocusSettings)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Apps can’t switch Do Not Disturb themselves, so Supervibes does it with two small Shortcuts. Add each one in Shortcuts, then come back.")
                            .appText(.sm).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        SmallOutlineButton(
                            icon: .add,
                            title: added.on ? "Add the second Shortcut (2 of 2)" : "Add the first Shortcut (1 of 2)",
                            action: onAddFocusShortcut
                        )
                    }
                }
            }
        }
    }

    // MARK: Apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowHeader(title: "Quit apps", detail: "Quits them as a session starts, so they can’t pull you away.") {
                addAppMenu
            }

            if !routine.quitApps.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(routine.quitApps) { app in
                        AppChip(name: app.name) {
                            var new = routine
                            new.quitApps.removeAll { $0.bundleId == app.bundleId }
                            onChange(new)
                        }
                    }
                }

                Toggle(isOn: Binding(
                    get: { routine.reopenApps },
                    set: { var new = routine; new.reopenApps = $0; onChange(new) }
                )) {
                    Text("Reopen them once it’s over").appText(.sm).foregroundStyle(Theme.foreground)
                }
                .toggleStyle(.checkbox)
                .tint(Theme.foreground)
            }
        }
    }

    private var addAppMenu: some View {
        let offered = openApps.filter { app in !routine.quitApps.contains { $0.bundleId == app.bundleId } }
        return Menu {
            if !offered.isEmpty {
                Section("Open now") {
                    ForEach(offered) { app in
                        Button(app.name) {
                            var new = routine
                            new.quitApps.append(app)
                            onChange(new)
                        }
                    }
                }
            }
            Button("Choose from Applications…", action: onChooseApp)
        } label: {
            HStack(spacing: 6) {
                Icon.add.image(size: 14)
                Text("Add app").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Own Shortcuts

    private var ownShortcuts: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowHeader(title: "Run your own Shortcuts", detail: "For anything else: music, lights, opening what you need.") {
                EmptyView()
            }

            HStack(alignment: .top, spacing: 12) {
                picker("When a session starts", \.start)
                picker("When it’s over", \.end)
            }

            if shortcuts?.filter({ $0 != SessionRoutine.focusOn && $0 != SessionRoutine.focusOff }).isEmpty == true {
                Note {
                    Text("You don’t have any of your own yet.")
                    LinkButton("Make one in Shortcuts", action: onOpenShortcuts)
                }
            }
        }
    }

    private func picker(_ label: String, _ keyPath: WritableKeyPath<SessionRoutine, String?>) -> some View {
        let chosen = routine[keyPath: keyPath]
        // The ready-made ones are run by the switch above, so they aren't offered here.
        let own = (shortcuts ?? []).filter { $0 != SessionRoutine.focusOn && $0 != SessionRoutine.focusOff }
        // "" is none. A picked Shortcut that's since been renamed or deleted stays listed, marked.
        var options = [""] + own
        if let chosen, !options.contains(chosen) { options.append(chosen) }
        return SelectField(
            label: label,
            selection: Binding(
                get: { chosen ?? "" },
                set: { name in
                    var new = routine
                    new[keyPath: keyPath] = name.isEmpty ? nil : name
                    onChange(new)
                }
            ),
            options: options,
            title: { name in
                if name.isEmpty { return "None" }
                if let shortcuts, !shortcuts.contains(name) { return "\(name) (not found)" }
                return name
            }
        )
    }
}

// MARK: - Pieces

/// A row's title and detail, with its control on the right.
private struct RowHeader<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appText(.sm, .medium).foregroundStyle(Theme.foreground)
                Text(detail).appText(.sm).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control
        }
    }
}

private struct Switch: View {
    let label: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: { onChange($0) }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.foreground)
    }
}

/// A line of muted text with an inline action.
private struct Note<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) { content }
            .appText(.sm)
            .foregroundStyle(Theme.muted)
    }
}

/// An underlined inline action.
private struct LinkButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.foreground)
            .underline()
            .pointerStyle(.link)
            .fixedSize()
    }
}

private struct SmallOutlineButton: View {
    let icon: Icon
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon.image(size: 14)
                Text(title).appText(.sm, .medium)
            }
            .foregroundStyle(Theme.foreground)
            .padding(.horizontal, 12)
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
        .fixedSize()
    }
}

/// An app to quit, with a way to take it off the list.
private struct AppChip: View {
    let name: String
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name).appText(.sm, .medium).foregroundStyle(Theme.foreground)
            Button(action: onRemove) {
                Icon.close.image(size: 12)
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityLabel("Stop quitting \(name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(Theme.wash, in: .rect(cornerRadius: 8))
    }
}

#Preview("Set up") {
    SessionRoutineCard(
        routine: SessionRoutine(doNotDisturb: true, quitApps: [.init(bundleId: "com.tinyspeck.slackmacgap", name: "Slack"), .init(bundleId: "com.apple.mail", name: "Mail")], start: "Start playlist"),
        shortcuts: [SessionRoutine.focusOn, SessionRoutine.focusOff, "Start playlist"]
    )
    .padding(32).frame(width: 768).background(Theme.background)
}

#Preview("Do Not Disturb, Shortcuts still to add") {
    @Previewable @State var routine = SessionRoutine(doNotDisturb: true)
    SessionRoutineCard(routine: routine, shortcuts: [], onChange: { routine = $0 })
        .padding(32).frame(width: 768).background(Theme.background)
}

#Preview("Nothing picked") {
    SessionRoutineCard(routine: .defaults, shortcuts: [])
        .padding(32).frame(width: 768).background(Theme.background)
}
