import SwiftUI

/// New goal or Edit goal, matching src/app/(app)/goals/goal-dialog.tsx: a live badge beside the
/// title and what done looks like, a target date, then the colour and a searchable grid of icons.
struct GoalDialog: View {
    enum Mode { case create, edit }

    @State var input: GoalInput
    var mode: Mode = .create
    /// Today, "YYYY-MM-DD", for the target date's "in 3 weeks".
    var today = CalendarDay.today()
    /// The person's areas, to place the goal in one; with none, there's no Area field.
    var areas: [Area] = []
    var onCancel: () -> Void = {}
    var onSave: (GoalInput) -> Void = { _ in }
    /// Editing only: deletes the goal, after an inline "for good?".
    var onDelete: (() -> Void)?

    @State private var query = ""
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var isPickingDate = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    colors
                    icons
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            footer
        }
        .frame(width: 480, height: 640)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.background)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
        .clipShape(.rect(cornerRadius: 20))
        .onAppear { titleFocused = true }
        .onExitCommand(perform: onCancel)
    }

    // MARK: Header: title, live badge, what done looks like, target date

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(mode == .create ? "New goal" : "Edit goal")
                    .appText(.base, .semibold, tracking: -0.01).foregroundStyle(Theme.foreground)
                Spacer()
                CloseButton(action: onCancel)
            }
            .padding(.top, 20)

            HStack(alignment: .top, spacing: 16) {
                GoalBadge(icon: input.icon, color: input.color, size: .lg)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("", text: titleBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(20, .semibold))
                        .tracking(-0.02 * 20)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1...4)
                        .placeholder("What are you working toward?", when: input.title.isEmpty, font: .app(20, .semibold))
                        .accessibilityLabel("Title")
                        .focused($titleFocused)
                        .onSubmit(submit)
                        .padding(.top, 12)
                    TextField("", text: descriptionBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(14))
                        .foregroundStyle(Theme.foreground(0.8))
                        .lineLimit(1...6)
                        .placeholder("What does done look like?", when: input.description.isEmpty, font: .app(14))
                        .accessibilityLabel("Description")
                    HStack(spacing: 8) {
                        if !areas.isEmpty {
                            AreaField(areaId: $input.areaId, areas: areas)
                        }
                        TargetDateField(date: $input.targetDate, today: today, isPicking: $isPickingDate)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Colour

    private var colors: some View {
        HStack(spacing: 10) {
            ForEach(GoalPalette.colors, id: \.key) { color in
                ColorSwatch(info: color, isSelected: input.color == color.key) { input.color = color.key }
            }
        }
    }

    // MARK: Icons

    private var icons: some View {
        let groups = matchingGroups
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Icon.search.image(size: 16).foregroundStyle(Theme.muted)
                TextField("", text: $query)
                    .placeholder("Search icons", when: query.isEmpty, font: .app(14), color: Theme.muted)
                    .accessibilityLabel("Search icons")
                    .textFieldStyle(.plain)
                    .font(.app(14))
                    .foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Theme.foreground(0.03), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))

            ForEach(groups, id: \.label) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.label).appText(.xs, .medium).foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                        ForEach(group.icons, id: \.name) { icon in
                            IconChoice(
                                icon: icon,
                                color: input.color,
                                isSelected: input.icon == icon.name
                            ) { input.icon = icon.name }
                        }
                    }
                }
            }
            if groups.isEmpty {
                Text("No icons match “\(query)”.")
                    .appText(.sm).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }
    }

    private var matchingGroups: [GoalIconGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return GoalPalette.iconGroups }
        return GoalPalette.iconGroups.compactMap { group in
            let icons = group.icons.filter {
                $0.label.lowercased().contains(q) || $0.keywords.contains(q) || group.label.lowercased().contains(q)
            }
            return icons.isEmpty ? nil : GoalIconGroup(label: group.label, icons: icons)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error {
                Text(error).appText(.sm).foregroundStyle(Theme.danger)
            }
            if confirmingDelete, let onDelete {
                HStack(spacing: 12) {
                    Text("Delete this goal for good?").appText(.sm).foregroundStyle(Theme.foreground)
                    Spacer()
                    GhostButton(title: "Keep") { confirmingDelete = false }
                    DangerButton(title: "Delete", action: onDelete)
                }
            } else {
                HStack(spacing: 8) {
                    if mode == .edit, onDelete != nil {
                        DeleteButton { confirmingDelete = true }
                    }
                    Spacer()
                    GhostButton(title: "Cancel", action: onCancel)
                    PrimaryButton(title: mode == .create ? "Add goal" : "Save", action: submit)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: Editing

    /// New lines aren't allowed in the title; Return saves instead.
    private var titleBinding: Binding<String> {
        Binding(
            get: { input.title },
            set: {
                input.title = String($0.replacingOccurrences(of: "\n", with: " ").prefix(GoalInput.maxTitle))
                error = nil
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { input.description },
            set: {
                input.description = String($0.prefix(GoalInput.maxDescription))
                error = nil
            }
        )
    }

    private func submit() {
        if let problem = input.problem {
            error = problem
            return
        }
        onSave(input)
    }
}

/// `-ml-2 h-10 rounded-xl px-3 text-sm font-medium text-red-600 hover:bg-red-500/10`
private struct DeleteButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.delete.image(size: 16)
                Text("Delete").appText(.sm, .medium)
            }
            .foregroundStyle(Theme.danger)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(isHovered ? Color(nsColor: .rgb(0xef4444, alpha: 0.1)) : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.leading, -8)
    }
}

/// `h-9 w-9 rounded-full text-muted hover:bg-foreground/[.06]`
private struct CloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Icon.close.image(size: 18)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .frame(width: 36, height: 36)
                .background(isHovered ? Theme.foreground(0.06) : .clear, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .padding(.trailing, -8)
        .accessibilityLabel("Close")
    }
}

/// A pill that opens a date picker: "Add target date", or "Target Dec 18 · in 4 weeks" and a clear button.
/// The goal's area, before its target date: the area's icon and name, or "No area", opening a list of the areas
/// beside it (a popover, since the dialog is the window's one overlay).
private struct AreaField: View {
    @Binding var areaId: String?
    let areas: [Area]
    @State private var isPicking = false
    @State private var isHovered = false

    private var area: Area? { areas.first { $0.id == areaId } }

    var body: some View {
        Button { isPicking = true } label: {
            HStack(spacing: 6) {
                if let area {
                    GoalIconImage(name: area.icon, size: 14)
                    Text(area.name).foregroundStyle(Theme.foreground)
                } else {
                    Text("No area")
                }
                Icon.chevronDown.image(size: 12)
            }
            .appText(.xs, .medium)
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .overlay(Capsule().strokeBorder(isHovered || isPicking ? Theme.foreground(0.2) : Theme.cardBorder))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Area")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(areas) { area in
                    AreaMenuRow(name: area.name, icon: area.icon, isChecked: area.id == areaId) {
                        areaId = area.id
                        isPicking = false
                    }
                }
                MenuSeparator()
                AreaMenuAction(icon: .close, title: "No area", isChecked: areaId == nil) {
                    areaId = nil
                    isPicking = false
                }
            }
            .padding(6)
            .frame(width: 232)
        }
    }
}

private struct TargetDateField: View {
    @Binding var date: String?
    let today: String
    @Binding var isPicking: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Button { isPicking = true } label: {
                HStack(spacing: 6) {
                    Icon.calendarSmall.image(size: 14)
                    if let date {
                        let relative = CalendarDay.relative(CalendarDay.daysUntil(date, today: today))
                        Text("Target \(CalendarDay.format(date, today: today))\(Text(" · \(relative)").foregroundStyle(Theme.muted))")
                            .foregroundStyle(Theme.foreground)
                    } else {
                        Text("Add target date")
                    }
                }
                .appText(.xs, .medium)
                .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().strokeBorder(isHovered ? Theme.foreground(0.2) : Theme.cardBorder))
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                DayCalendar(title: "Target date", selected: date ?? today) { day in
                    date = day
                    isPicking = false
                }
                .padding(12)
            }

            if date != nil {
                Button { date = nil } label: {
                    Icon.close.image(size: 14).foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear target date")
            }
        }
    }
}

/// A colour to pick: `h-8 w-8 rounded-full`, ringed and ticked when chosen.
private struct ColorSwatch: View {
    let info: GoalColorInfo
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(GoalPalette.color(info.key))
                if isSelected {
                    Icon.tick.image(size: 16).foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .padding(2)
            .overlay {
                if isSelected { Circle().strokeBorder(Theme.foreground(0.7), lineWidth: 2) }
            }
            .scaleEffect(isHovered ? 1.1 : 1)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel(info.label)
    }
}

/// An icon in the grid: tinted with the goal's colour when chosen.
private struct IconChoice: View {
    let icon: GoalIconInfo
    let color: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // `aspect-square rounded-xl`: the tile fills its grid column and stays square, with the
            // icon centred in it (the tile, not the icon, sets the size).
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? GoalPalette.tintBackground(color) : isHovered ? Theme.foreground(0.06) : .clear)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GoalIconImage(name: icon.name, size: 22)
                        .foregroundStyle(isSelected ? GoalPalette.color(color) : isHovered ? Theme.foreground : Theme.foreground(0.7))
                }
                .overlay {
                    if isSelected { RoundedRectangle(cornerRadius: 12).strokeBorder(GoalPalette.color(color)) }
                }
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(icon.label)
        .accessibilityLabel(icon.label)
    }
}

#Preview("Edit goal") {
    GoalDialog(
        input: GoalInput(title: "Run a half marathon", description: "Finish under two hours.",
                         targetDate: "2027-04-12", icon: "Rocket01Icon", color: "sky"),
        today: "2026-11-18"
    )
    .padding(24)
    .background(Theme.shell)
}

#Preview("New goal") {
    GoalDialog(input: GoalInput(), today: "2026-11-18").padding(24).background(Theme.shell)
}
