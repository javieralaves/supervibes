import SwiftUI

/// New goal, matching src/app/(app)/goals/goal-dialog.tsx: a live badge beside the title and what
/// done looks like, a target date, then the colour and a searchable grid of icons.
struct GoalDialog: View {
    @State var input: GoalInput
    /// Today, "YYYY-MM-DD", for the target date's "in 3 weeks".
    var today = CalendarDay.today()
    var onCancel: () -> Void = {}
    var onSave: (GoalInput) -> Void = { _ in }

    @State private var query = ""
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
                Text("New goal").appText(.base, .semibold, tracking: -0.01).foregroundStyle(Theme.foreground)
                Spacer()
                CloseButton(action: onCancel)
            }
            .padding(.top, 20)

            HStack(alignment: .top, spacing: 16) {
                GoalBadge(icon: input.icon, color: input.color, size: .lg)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("What are you working toward?", text: titleBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(20, .semibold))
                        .tracking(-0.02 * 20)
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1...4)
                        .focused($titleFocused)
                        .onSubmit(submit)
                        .padding(.top, 12)
                    TextField("What does done look like?", text: descriptionBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.app(14))
                        .foregroundStyle(Theme.foreground(0.8))
                        .lineLimit(1...6)
                    TargetDateField(date: $input.targetDate, today: today, isPicking: $isPickingDate)
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
                TextField("Search icons", text: $query)
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
            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel", action: onCancel)
                PrimaryButton(title: "Add goal", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
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
                DatePicker(
                    "Target date",
                    selection: Binding(
                        get: { date.flatMap(CalendarDay.date) ?? CalendarDay.date(today) ?? Date() },
                        set: { date = CalendarDay.string($0); isPicking = false }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
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
