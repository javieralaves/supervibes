import SwiftUI

/// Settings' card for notices before sessions: a switch, then any mix of at start, 5 minutes
/// before and 15 minutes before. The choice is kept on this Mac (Shared/Models/SessionNotices.swift).
struct NoticesCard: View {
    let settings: NoticeSettings
    let permission: NoticePermission
    var onChange: (NoticeSettings) -> Void = { _ in }
    var onOpenSystemSettings: () -> Void = {}

    var body: some View {
        Card {
            CardHeader(title: "Session notices", description: "A heads-up before a session starts, so it doesn’t sneak up on you.") {
                Toggle("Notices before sessions", isOn: Binding(
                    get: { settings.isOn },
                    set: { on in
                        var new = settings
                        new.setOn(on)
                        onChange(new)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.foreground)
            }

            LeadPicker(selected: settings.leads) { lead in
                var new = settings
                new.toggle(lead)
                onChange(new)
            }
            .opacity(settings.isOn ? 1 : 0.5)
            .inactive(!settings.isOn)

            if settings.isOn, permission == .denied {
                HStack(spacing: 4) {
                    Text("Notifications are off for Supervibes in System Settings.")
                        .foregroundStyle(Theme.danger)
                    Button("Turn them on", action: onOpenSystemSettings)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.foreground)
                        .underline()
                        .pointerStyle(.link)
                }
                .appText(.sm)
                .padding(.top, 12)
            }
        }
    }
}

/// ToggleGroup's look, but any number can be picked; a tick marks each one that is.
private struct LeadPicker: View {
    let selected: Set<NoticeLead>
    let onToggle: (NoticeLead) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NoticeLead.allCases, id: \.self) { lead in
                Item(label: lead.label, isSelected: selected.contains(lead)) { onToggle(lead) }
            }
        }
        .padding(4)
        .background(Theme.wash, in: .rect(cornerRadius: 12))
        .fixedSize()
    }

    private struct Item: View {
        let label: String
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Icon.tickBold.image(size: 12)
                        .foregroundStyle(isSelected ? Theme.foreground : .clear)
                    Text(label)
                        .foregroundStyle(isSelected || isHovered ? Theme.foreground : Theme.muted)
                }
                .appText(.sm, .medium)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .frame(minHeight: 40)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.card)
                            .shadow(color: Color(nsColor: .rgb(0x0f1114, alpha: 0.08)), radius: 1, y: 1)
                    }
                }
                .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

#Preview("On, 5 min and at start") {
    @Previewable @State var settings = NoticeSettings(isOn: true, leads: [.five, .atStart])
    NoticesCard(settings: settings, permission: .allowed, onChange: { settings = $0 })
        .padding(32).frame(width: 768).background(Theme.background)
}

#Preview("Off") {
    NoticesCard(settings: .defaults, permission: .notAsked)
        .padding(32).frame(width: 768).background(Theme.background)
}

#Preview("Turned off in System Settings") {
    NoticesCard(settings: NoticeSettings(isOn: true, leads: [.fifteen]), permission: .denied)
        .padding(32).frame(width: 768).background(Theme.background)
}
