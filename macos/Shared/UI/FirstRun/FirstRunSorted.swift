import SwiftUI

/// Step 2: the plate, sorted (the design's "2 · Sorted"). One card per part of life, each with the projects and
/// practices sorted into it, what helps place them, and the tasks under them; an area's bucket says it holds one-offs
/// that belong to nothing bigger. Clicking anything opens a card to change it: its kind, name and area, and what its
/// kind needs. Each area can take something missed, and the dashed card after the areas brings in another part of life. A practice nobody
/// said the rhythm of asks How often?, and the plate can't be made until each has one. Changed after it's made, Looks
/// right replaces what was made.
struct FirstRunSorted: View {
    let plate: SortedPlate
    var isSaving = false
    var error: String?
    var actions = FirstRunActions()
    /// An area's add row to start open, with what's typed in it: for snapshots and previews.
    var adding: AddDraft?
    @Environment(\.overlays) private var overlays
    @State private var areaButton: CGRect = .zero

    var body: some View {
        FirstRunFlow(
            step: 1,
            eyebrow: "Sorted",
            title: "Your plate, sorted",
            subtitle: "Projects have a finish line; practices are things you keep up. Click anything to change it, and add what’s missing."
        ) {
            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row, id: \.self) { cell in
                                switch cell {
                                case .area(let area):
                                    AreaCard(plate: plate, area: area, actions: actions, adding: adding?.areaId == area.id ? adding : nil)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                case .add:
                                    // Alone on its row it keeps an empty area's height; beside areas it takes theirs.
                                    AddAreaCard(examples: usual.prefix(3).map(\.name), anchor: $areaButton) { openAreas() }
                                        .frame(minHeight: row.count == 1 ? 150 : nil)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.gridCellUnsizedAxes([.vertical]) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: actions.back)
            Spacer()
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).lineLimit(2).padding(.trailing, 8)
            } else if let first = plate.needsRhythm.first {
                Text("Say how often for \(first.title)").appText(.sm).foregroundStyle(Theme.muted).padding(.trailing, 8)
            }
            FlowButton(title: "Looks right", primary: true, isBusy: isSaving, isEnabled: plate.needsRhythm.isEmpty, action: actions.save)
        }
    }

    private enum Cell: Hashable {
        case area(PlateArea)
        case add
    }

    /// The areas in rows of three, then the card to add one, so the cards in a row share its height and their adds
    /// line up.
    private var rows: [[Cell]] {
        let cells = plate.areas.map(Cell.area) + [.add]
        return stride(from: 0, to: cells.count, by: 3).map { Array(cells[$0..<min($0 + 3, cells.count)]) }
    }

    /// The usual parts of life not on the plate yet.
    private var usual: [UsualArea] {
        let have = Set(plate.areas.map { $0.name.lowercased() })
        return UsualArea.all.filter { !have.contains($0.name.lowercased()) }
    }

    private func openAreas() {
        overlays?.showMenu(anchor: areaButton, alignLeading: true) {
            AddAreaMenu(usual: Array(usual.prefix(4))) { name, icon in
                actions.addArea(name, icon)
                overlays?.dismiss()
            }
        }
    }
}

// MARK: - Area cards

private struct AreaCard: View {
    let plate: SortedPlate
    let area: PlateArea
    let actions: FirstRunActions
    var adding: AddDraft?
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AreaTile(icon: area.icon, size: 28)
                Text(area.name).font(.app(14, .semibold)).foregroundStyle(Theme.foreground)
                Spacer()
                Text("\(area.items.count)").font(.app(12, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(area.items) { item in
                    ItemRow(plate: plate, item: item, actions: actions)
                }
                if area.items.isEmpty {
                    Text("Nothing here yet").font(.app(12)).foregroundStyle(Theme.muted.opacity(0.8))
                        .padding(.horizontal, 8).padding(.vertical, 10)
                }
            }
            .padding(.top, 4)
            .animation(staticRendering ? nil : .smooth(duration: 0.3), value: area.items)

            Spacer(minLength: 8)
            AddRow(area: area.name, bucket: area.items.first(where: \.isBucket)?.title ?? SortedPlate.bucketName(for: area.name),
                   draft: adding) { title, kind in
                actions.add(title, kind, area.id)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

/// A project or practice, and the tasks under it, each a click from its editing card.
private struct ItemRow: View {
    let plate: SortedPlate
    let item: PlateItem
    let actions: FirstRunActions
    @Environment(\.overlays) private var overlays
    @State private var frame: CGRect = .zero
    @State private var taskFrames: [Int: CGRect] = [:]
    @State private var isHovered = false

    private var isEditing: Bool { overlays?.presented?.owner == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
                    .scaleEffect(28.0 / 24.0).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.app(13.5, .medium)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        if item.isBucket {
                            Icon.plan.image(size: 11)
                            Text("One-offs that belong to nothing bigger").lineLimit(1)
                        } else {
                            Text(item.isPractice ? "Practice" : "Project")
                            if item.isPractice {
                                Text("·").foregroundStyle(Theme.muted.opacity(0.6))
                                RhythmPicker(perWeek: item.perWeek) { actions.setPerWeek(item.id, $0) }
                            } else if let detail = item.detail {
                                Text("·").foregroundStyle(Theme.muted.opacity(0.6))
                                Text(detail).lineLimit(1)
                            }
                        }
                    }
                    .font(.app(11.5))
                    .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(rowBackground(isEditing))
            .contentShape(.rect(cornerRadius: 12))
            .onHover { isHovered = $0 }
            .onTapGesture { open(.item(item.id), anchor: frame) }
            .modifier(AnchorReader(frame: $frame))

            ForEach(Array(item.tasks.enumerated()), id: \.offset) { index, task in
                TaskRow(task: task, isEditing: overlays?.presented?.owner == "\(item.id)#\(index)") {
                    open(.task(itemId: item.id, index: index), anchor: taskFrames[index] ?? frame)
                }
                .padding(.leading, 38)
                .modifier(AnchorReader(frame: Binding(get: { taskFrames[index] ?? .zero }, set: { taskFrames[index] = $0 })))
            }
        }
    }

    private func rowBackground(_ editing: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(editing ? Theme.foreground(0.045) : isHovered ? Theme.wash : .clear)
            .overlay { if editing { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground, lineWidth: 1.5) } }
    }

    private func open(_ selection: SortedSelection, anchor: CGRect) {
        guard let edit = plate.edit(for: selection) else { return }
        let owner: String = switch selection {
        case .item(let id): id
        case .task(let id, let index): "\(id)#\(index)"
        }
        overlays?.showMenu(anchor: anchor, owner: owner, alignLeading: true) {
            SortedEditCard(plate: plate, selected: { if case .item(let id) = selection { id } else { nil } }(), edit: edit) { done in
                actions.applyEdit(done, selection)
                overlays?.dismiss()
            } onRemove: {
                actions.remove(selection)
                overlays?.dismiss()
            }
        }
    }
}

private struct TaskRow: View {
    let task: String
    let isEditing: Bool
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.lineStrong, lineWidth: 1).frame(width: 11, height: 11)
            Text(task).font(.app(12)).foregroundStyle(Theme.foreground(0.75)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isEditing ? Theme.foreground(0.045) : isHovered ? Theme.wash : .clear)
                .overlay { if isEditing { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground, lineWidth: 1.5) } }
        }
        .contentShape(.rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
    }
}

/// An add row open in an area, with what's typed: for snapshots and previews.
struct AddDraft: Hashable {
    let areaId: String
    var kind = PlateKind.project
    var title = ""
}

/// Add to an area, pinned to its foot. Opened, it's the row-to-be: a badge that guesses the icon from the words as
/// they're typed (round for a practice, a box for a task), the name, and a line saying what it'll be and, for a
/// one-off, where it goes. Under it, what kind it is, and a Return keycap once something's typed: Return adds it and
/// stays open for the next; Escape, or clicking away with nothing typed, closes it.
private struct AddRow: View {
    let area: String
    /// Where a one-off goes: the area's bucket.
    let bucket: String
    let onAdd: (String, PlateKind) -> Void
    @State private var isAdding: Bool
    @State private var title: String
    @State private var kind: PlateKind
    @FocusState private var focused: Bool
    @Environment(\.staticRendering) private var staticRendering

    init(area: String, bucket: String, draft: AddDraft? = nil, onAdd: @escaping (String, PlateKind) -> Void) {
        self.area = area
        self.bucket = bucket
        self.onAdd = onAdd
        _isAdding = State(initialValue: draft != nil)
        _title = State(initialValue: draft?.title ?? "")
        _kind = State(initialValue: draft?.kind ?? .project)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            if isAdding {
                composer
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            } else {
                AddToButton(area: area) {
                    isAdding = true
                    focused = true
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 2).padding(.bottom, 2)
        .animation(staticRendering ? nil : .smooth(duration: 0.22), value: isAdding)
        .onChange(of: focused) {
            // Clicking away with nothing typed puts it away; a beat's grace for clicks inside it that hand focus back.
            guard !focused else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                if !focused && trimmed.isEmpty { close() }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                AddPreviewBadge(kind: kind, title: trimmed)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.app(13.5, .medium))
                        .foregroundStyle(Theme.foreground)
                        .placeholder(placeholder, when: title.isEmpty, font: .app(13.5, .medium), color: Theme.muted.opacity(0.8))
                        .focused($focused)
                        .onSubmit(add)
                        .onExitCommand { close() }
                    HStack(spacing: 5) {
                        Text(kind.name)
                        Text("·").foregroundStyle(Theme.muted.opacity(0.6))
                        Text(line).lineLimit(1)
                    }
                    .font(.app(11.5))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 8).padding(.top, 9).padding(.bottom, 10)

            HStack(spacing: 8) {
                KindSwitch(kind: $kind) { focused = true }
                Spacer(minLength: 4)
                if !trimmed.isEmpty { KeyHint(key: "↩").help("Return adds it") }
            }
            .padding(.horizontal, 6).padding(.bottom, 6)
        }
        .background {
            RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong))
        .animation(staticRendering ? nil : .smooth(duration: 0.2), value: kind)
    }

    private var placeholder: String {
        switch kind {
        case .project: "Name a project"
        case .practice: "Name a practice"
        case .task: "Name a one-off"
        }
    }

    private var line: String {
        switch kind {
        case .project: "Has a finish line"
        case .practice: "You’ll say how often"
        case .task: "Goes in \(bucket)"
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return close() }
        onAdd(trimmed, kind)
        title = ""
        focused = true
    }

    private func close() {
        isAdding = false
        title = ""
        kind = .project
    }
}

/// The add row's badge: for a project or practice, the icon its words suggest (or the kind's while there are none), in
/// ink on a wash, square or round as the kind is; for a task, the empty box a task wears.
private struct AddPreviewBadge: View {
    let kind: PlateKind
    let title: String

    private var icon: String? {
        guard kind != .task, !title.isEmpty else { return nil }
        let guess = QuestSuggestion(kind: kind == .practice ? .practice : .project, title: title, line: "", perWeek: nil).icon
        return guess == GoalPalette.defaultIcon ? nil : guess
    }

    var body: some View {
        ZStack {
            if kind == .task {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.lineStrong, lineWidth: 1.5).frame(width: 13, height: 13)
            } else if let icon {
                GoalIconImage(name: icon, size: 15).id(icon).transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                (kind == .practice ? Icon.repeats : Icon.flag).image(size: 14).transition(.opacity)
            }
        }
        .foregroundStyle(Theme.foreground(0.6))
        .frame(width: 28, height: 28)
        .background(Theme.foreground(kind == .task ? 0 : 0.06), in: kind == .practice ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 8)))
        .animation(.smooth(duration: 0.2), value: icon)
    }
}

/// Project, practice or task, as a small segmented switch: each its icon and name, the chosen one raised.
private struct KindSwitch: View {
    @Binding var kind: PlateKind
    let onPick: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PlateKind.allCases, id: \.self) { option in
                Item(kind: option, isOn: kind == option) {
                    kind = option
                    onPick()
                }
            }
        }
        .padding(2)
        .background(Theme.wash, in: .rect(cornerRadius: 9))
        .fixedSize()
    }

    private struct Item: View {
        let kind: PlateKind
        let isOn: Bool
        let action: () -> Void
        @State private var isHovered = false

        private var icon: Icon {
            switch kind {
            case .project: .flag
            case .practice: .repeats
            case .task: .plan
            }
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    icon.image(size: 12)
                    Text(kind.name).font(.app(11.5, .medium))
                }
                .foregroundStyle(isOn || isHovered ? Theme.foreground : Theme.muted)
                .padding(.horizontal, 8).frame(height: 24)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 7).fill(Theme.card)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder))
                    }
                }
                .contentShape(.rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

/// A key to press, as a small keycap.
private struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key).font(.app(11, .medium))
            .foregroundStyle(Theme.muted)
            .frame(width: 22, height: 22)
            .background(Theme.foreground(0.05), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
            .fixedSize()
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

/// The way in: a plus and "Add to Work", darkening on hover.
private struct AddToButton: View {
    let area: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.add.image(size: 13)
                Text("Add to \(area)").font(.app(12.5, .medium))
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 8).frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Editing

/// Changing one thing that was sorted: what kind it is, as three tiles (switching changes what the rest asks for),
/// its look and name, its area, how often for a practice, which project for a task. Remove takes it off the plate.
struct SortedEditCard: View {
    let plate: SortedPlate
    /// The project or practice being changed, which a task can't go under.
    var selected: String?
    @State var edit: SortedEdit
    /// The icon and colour choices, open under the name.
    @State private var pickingLook: Bool
    @Environment(\.staticRendering) private var staticRendering
    let onDone: (SortedEdit) -> Void
    let onRemove: () -> Void

    init(plate: SortedPlate, selected: String? = nil, edit: SortedEdit, pickingLook: Bool = false,
         onDone: @escaping (SortedEdit) -> Void, onRemove: @escaping () -> Void) {
        self.plate = plate
        self.selected = selected
        _edit = State(initialValue: edit)
        _pickingLook = State(initialValue: pickingLook)
        self.onDone = onDone
        self.onRemove = onRemove
    }

    private var area: PlateArea? { plate.areas.first { $0.id == edit.areaId } }
    private var homes: [(id: String, title: String)] { plate.homes(in: edit.areaId, excluding: selected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(PlateKind.allCases, id: \.self) { kind in
                    KindTile(kind: kind, isOn: edit.kind == kind) {
                        edit.kind = kind
                        if kind == .practice, edit.perWeek == nil { edit.perWeek = 3 }
                        if kind == .task, edit.under == nil || !homes.contains(where: { $0.id == edit.under }) {
                            edit.under = homes.first?.id
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    HStack(spacing: 8) {
                        if let look {
                            LookButton(icon: look.icon, color: look.color, round: edit.kind == .practice, isOpen: pickingLook) {
                                pickingLook.toggle()
                            }
                        }
                        TextField("", text: $edit.title)
                            .textFieldStyle(.plain)
                            .font(.app(13.5, .medium))
                            .onSubmit { onDone(edit) }
                            .padding(.horizontal, 12).frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.foreground, lineWidth: 1.5))
                    }
                    if pickingLook, look != nil {
                        LookPicker(icon: $edit.icon, color: $edit.color)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    field("Area") {
                        PickerChip(icon: area?.icon, label: area?.name ?? "") {
                            ForEach(plate.areas) { option in
                                Button(option.name) {
                                    edit.areaId = option.id
                                    if edit.kind == .task { edit.under = plate.homes(in: option.id, excluding: selected).first?.id }
                                }
                            }
                        }
                    }
                    switch edit.kind {
                    case .practice:
                        field("How often") {
                            PickerChip(label: (edit.perWeek ?? 3) == 1 ? "Once a week" : "\(edit.perWeek ?? 3) times a week") {
                                ForEach(1...7, id: \.self) { count in
                                    Button(count == 1 ? "Once a week" : "\(count) times a week") { edit.perWeek = count }
                                }
                            }
                        }
                    case .task:
                        field("Under") {
                            PickerChip(label: homes.first { $0.id == edit.under }?.title ?? homes.first?.title ?? "") {
                                ForEach(homes, id: \.id) { home in
                                    Button(home.title) { edit.under = home.id }
                                }
                            }
                        }
                    case .project:
                        EmptyView()
                    }
                }
            }
            .padding(.top, 16)

            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.top, 16)
            HStack {
                RemoveButton(action: onRemove)
                Spacer()
                FlowButton(title: "Done", primary: true, isEnabled: !edit.title.trimmingCharacters(in: .whitespaces).isEmpty) { onDone(edit) }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 340)
        .background {
            RoundedRectangle(cornerRadius: 16).fill(Theme.card).shadow(color: .black.opacity(0.2), radius: 24, y: 18)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
        .animation(staticRendering ? nil : .smooth(duration: 0.25), value: pickingLook)
        .onChange(of: edit.kind) { if edit.kind == .task { pickingLook = false } }
    }

    /// The look to show and change: a project's or practice's, not a task's.
    private var look: (icon: String, color: String)? {
        guard edit.kind != .task, let icon = edit.icon, let color = edit.color else { return nil }
        return (icon, color)
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.app(11.5, .semibold)).foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The badge beside the name, as a button: opens the icon and colour choices, a small chevron on its corner saying so.
private struct LookButton: View {
    let icon: String
    let color: String
    let round: Bool
    let isOpen: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            GoalBadge(icon: icon, color: color, size: .field, round: round)
                .overlay(alignment: .bottomTrailing) {
                    Icon.chevronDown.image(size: 8)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 14, height: 14)
                        .background(Theme.card, in: .circle)
                        .overlay(Circle().strokeBorder(Theme.cardBorder))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .offset(x: 4, y: 4)
                }
                .scaleEffect(isHovered && !isOpen ? 1.04 : 1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("Change icon and colour")
    }
}

/// The colours, then the icons, searchable, in the chosen colour.
private struct LookPicker: View {
    @Binding var icon: String?
    @Binding var color: String?
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(GoalPalette.colors, id: \.key) { info in
                    Button { color = info.key } label: {
                        Circle().fill(GoalPalette.color(info.key))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay { if color == info.key { Circle().strokeBorder(Theme.foreground(0.7), lineWidth: 1.5) } }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(info.label)
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 6) {
                Icon.search.image(size: 12).foregroundStyle(Theme.muted)
                TextField("", text: $query)
                    .textFieldStyle(.plain)
                    .font(.app(12.5))
                    .foregroundStyle(Theme.foreground)
                    .placeholder("Search icons", when: query.isEmpty, font: .app(12.5), color: Theme.muted)
                    .accessibilityLabel("Search icons")
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(Theme.foreground(0.03), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.label).font(.app(11, .medium)).foregroundStyle(Theme.muted)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 2) {
                                ForEach(group.icons, id: \.name) { info in
                                    IconChoice(name: info.name, label: info.label, color: color ?? "slate", isOn: info.name == icon) {
                                        icon = info.name
                                    }
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("No icons match “\(query)”.").font(.app(12)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: 150)
        }
        .padding(10)
        .background(Theme.foreground(0.025), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder))
    }

    private struct IconChoice: View {
        let name: String
        let label: String
        let color: String
        let isOn: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                GoalIconImage(name: name, size: 16)
                    .foregroundStyle(isOn ? GoalPalette.color(color) : isHovered ? Theme.foreground : Theme.foreground(0.65))
                    .frame(maxWidth: .infinity).frame(height: 32)
                    .background(isOn ? GoalPalette.color(color).opacity(0.14) : isHovered ? Theme.wash : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(label)
            .accessibilityLabel(label)
        }
    }
}

/// Takes it off the plate: muted until hovered, then red.
private struct RemoveButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon.delete.image(size: 13)
                Text("Remove").font(.app(12.5, .medium))
            }
            .foregroundStyle(isHovered ? Theme.danger : Theme.muted)
            .padding(.horizontal, 8).frame(height: 30)
            .background(isHovered ? Theme.danger.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.leading, -8)
        .onHover { isHovered = $0 }
    }
}

/// One of the three kinds: its icon, its name and what it means; ringed in ink when it's the one.
private struct KindTile: View {
    let kind: PlateKind
    let isOn: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 8) {
                KindMark(kind: kind, isOn: isOn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.name).font(.app(12.5, .semibold)).foregroundStyle(isOn ? Theme.foreground : Theme.foreground(0.7))
                    Text(kind.line).font(.app(11)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? Theme.card : Theme.foreground(0.03), in: .rect(cornerRadius: 12))
            .overlay { if isOn { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground, lineWidth: 1.5) } }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// A value to pick from a menu, drawn as a field: an icon if it has one, the value, and a chevron.
private struct PickerChip<Items: View>: View {
    var icon: String?
    let label: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 8) {
                if let icon { GoalIconImage(name: icon, size: 14).foregroundStyle(Theme.muted) }
                Text(label).font(.app(13)).foregroundStyle(Theme.foreground).lineLimit(1)
                Spacer(minLength: 0)
                Icon.chevronDown.image(size: 11).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 9))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

// MARK: - Adding an area

/// Another part of life, as a card-to-be in the grid: dashed, a plus, and a few usual areas not here yet. Clicking it
/// opens the choices against the card's edge.
private struct AddAreaCard: View {
    let examples: [String]
    @Binding var anchor: CGRect
    let onOpen: () -> Void
    @State private var isHovered = false

    private var line: String {
        switch examples.count {
        case 0: "Another part of your life"
        case 1: "Like \(examples[0])"
        case 2: "Like \(examples[0]) or \(examples[1])"
        default: "Like \(examples[0]), \(examples[1]) or \(examples[2])"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 10) {
                Icon.add.image(size: 15)
                    .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
                    .frame(width: 32, height: 32)
                    .background(Theme.foreground(isHovered ? 0.08 : 0.05), in: .circle)
                VStack(spacing: 3) {
                    Text("Add an area").font(.app(14, .semibold))
                        .foregroundStyle(isHovered ? Theme.foreground : Theme.foreground(0.75))
                    Text(line).font(.app(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.foreground(isHovered ? 0.025 : 0), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isHovered ? Theme.lineStrong : Theme.foreground(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .modifier(AnchorReader(frame: $anchor))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Another part of life: the usual ones not here yet, each with what it covers, or one named.
struct AddAreaMenu: View {
    let usual: [UsualArea]
    let onAdd: (String, String) -> Void
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        MenuPanel(width: 290) {
            if !usual.isEmpty {
                Text("Areas you don’t have yet").font(.app(11, .medium)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 4)
                ForEach(usual, id: \.name) { area in
                    AreaOption(icon: area.icon, name: area.name, line: area.line) { onAdd(area.name, area.icon) }
                }
                Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
            }
            if naming {
                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.app(12.5))
                    .placeholder("Name it", when: name.isEmpty, font: .app(12.5))
                    .onSubmit { onAdd(name, "Target02Icon") }
                    .padding(.horizontal, 8).frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.foreground, lineWidth: 1.5))
                    .padding(.horizontal, 4).padding(.bottom, 2)
            } else {
                AreaOption(icon: nil, name: "Name your own", line: nil) { naming = true }
            }
        }
    }
}

private struct AreaOption: View {
    let icon: String?
    let name: String
    let line: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let icon { GoalIconImage(name: icon, size: 13) } else { Icon.edit.image(size: 12) }
                }
                .foregroundStyle(Theme.muted)
                .frame(width: 24, height: 24)
                .background(Theme.foreground(0.05), in: .rect(cornerRadius: 7))
                Text(name).font(.app(12.5, .medium)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 4)
                if let line { Text(line).font(.app(11)).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(isHovered ? Theme.foreground(0.045) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// How often a practice happens: its rhythm, or a dashed How often? until it's said.
private struct RhythmPicker: View {
    let perWeek: Int?
    let onPick: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(1...7, id: \.self) { count in
                Button(count == 1 ? "Once a week" : "\(count) times a week") { onPick(count) }
            }
        } label: {
            if let perWeek {
                Text(perWeek == 1 ? "once a week" : "\(perWeek) times a week")
                    .font(.app(11.5)).foregroundStyle(Theme.muted)
            } else {
                Text("How often?")
                    .font(.app(11, .medium)).foregroundStyle(Theme.foreground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Theme.foreground(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
