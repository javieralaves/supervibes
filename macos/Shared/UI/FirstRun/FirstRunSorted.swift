import SwiftUI

/// Step 2: the plate, sorted (the design's "2 · Sorted"). One card per part of life, each with the projects and
/// practices sorted into it, what helps place them, and the tasks under them; an area's bucket says it holds one-offs
/// that belong to nothing bigger. Clicking anything opens a card to change it: its kind, name and area, and what its
/// kind needs. Each area can take something missed, and Add an area brings in another part of life. A practice nobody
/// said the rhythm of asks How often?, and the plate can't be made until each has one. Once it's made, it's shown as
/// made, with nothing left to change here.
struct FirstRunSorted: View {
    let plate: SortedPlate
    var isSaving = false
    var error: String?
    var isMade = false
    var actions = FirstRunActions()
    @Environment(\.overlays) private var overlays
    @State private var areaButton: CGRect = .zero

    var body: some View {
        FirstRunFlow(
            step: 1,
            eyebrow: "Sorted",
            title: "Your plate, sorted",
            subtitle: isMade
                ? "Projects have a finish line; practices are things you keep up. This is all made; change anything later in the app."
                : "Projects have a finish line; practices are things you keep up. Click anything to change it, and add what’s missing."
        ) {
            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(row) { area in
                                AreaCard(plate: plate, area: area, isMade: isMade, actions: actions)
                                    .frame(maxHeight: .infinity, alignment: .top)
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
            if !isMade {
                AddAreaButton { openAreas() }
                    .modifier(AnchorReader(frame: $areaButton))
            }
            FlowButton(title: "Looks right", primary: true, isBusy: isSaving, isEnabled: plate.needsRhythm.isEmpty, action: actions.save)
        }
    }

    /// The areas in rows of three, so the cards in a row share its height and their adds line up.
    private var rows: [[PlateArea]] {
        stride(from: 0, to: plate.areas.count, by: 3).map { Array(plate.areas[$0..<min($0 + 3, plate.areas.count)]) }
    }

    private func openAreas() {
        let have = Set(plate.areas.map { $0.name.lowercased() })
        let usual = UsualArea.all.filter { !have.contains($0.name.lowercased()) }
        overlays?.showMenu(anchor: areaButton) {
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
    let isMade: Bool
    let actions: FirstRunActions

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
                    ItemRow(plate: plate, item: item, isMade: isMade, actions: actions)
                }
                if area.items.isEmpty {
                    Text("Nothing here yet").font(.app(12)).foregroundStyle(Theme.muted.opacity(0.8))
                        .padding(.horizontal, 8).padding(.vertical, 10)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 8)
            if !isMade {
                AddRow(area: area.name) { title, kind in actions.add(title, kind, area.id) }
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
    let isMade: Bool
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
            .fill(editing ? Theme.foreground(0.045) : isHovered && !isMade ? Theme.wash : .clear)
            .overlay { if editing { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.foreground, lineWidth: 1.5) } }
    }

    private func open(_ selection: SortedSelection, anchor: CGRect) {
        guard !isMade, let edit = plate.edit(for: selection) else { return }
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

/// Add to an area, pinned to its foot: opened in place, a name and what kind it is; Return adds it.
private struct AddRow: View {
    let area: String
    let onAdd: (String, PlateKind) -> Void
    @State private var isAdding = false
    @State private var title = ""
    @State private var kind = PlateKind.project
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            if isAdding {
                TextField("", text: $title)
                    .textFieldStyle(.plain)
                    .font(.app(13))
                    .placeholder(kind == .task ? "A one-off to do" : "Name it", when: title.isEmpty, font: .app(13))
                    .focused($focused)
                    .onSubmit(add)
                    .onExitCommand { close() }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(Theme.card, in: .rect(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.foreground, lineWidth: 1.5))
                HStack(spacing: 4) {
                    ForEach(PlateKind.allCases, id: \.self) { option in
                        Button { kind = option } label: {
                            Text(option.name).font(.app(12, .medium))
                                .foregroundStyle(kind == option ? Theme.background : Theme.muted)
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(kind == option ? Theme.foreground : .clear, in: .rect(cornerRadius: 8))
                                .overlay { if kind != option { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardBorder) } }
                                .contentShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Return to add").font(.app(11.5)).foregroundStyle(Theme.muted)
                }
            } else {
                Button {
                    isAdding = true
                    focused = true
                } label: {
                    HStack(spacing: 6) {
                        Icon.add.image(size: 13)
                        Text("Add to \(area)").font(.app(12.5, .medium))
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).frame(height: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2).padding(.bottom, 2)
    }

    private func add() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return close() }
        onAdd(name, kind)
        title = ""
        focused = true
    }

    private func close() {
        isAdding = false
        title = ""
        kind = .project
    }
}

// MARK: - Editing

/// Changing one thing that was sorted: what kind it is, as three tiles (switching changes what the rest asks for),
/// its name and area, how often for a practice, which project for a task. Remove takes it off the plate.
struct SortedEditCard: View {
    let plate: SortedPlate
    /// The project or practice being changed, which a task can't go under.
    var selected: String?
    @State var edit: SortedEdit
    let onDone: (SortedEdit) -> Void
    let onRemove: () -> Void

    init(plate: SortedPlate, selected: String? = nil, edit: SortedEdit, onDone: @escaping (SortedEdit) -> Void, onRemove: @escaping () -> Void) {
        self.plate = plate
        self.selected = selected
        _edit = State(initialValue: edit)
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
                    TextField("", text: $edit.title)
                        .textFieldStyle(.plain)
                        .font(.app(13.5, .medium))
                        .onSubmit { onDone(edit) }
                        .padding(.horizontal, 12).frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.foreground, lineWidth: 1.5))
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
                Button(action: onRemove) {
                    Text("Remove").font(.app(12.5, .medium)).foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
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
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.app(11.5, .semibold)).foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct AddAreaButton: View {
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Icon.add.image(size: 13)
                Text("Add an area").appText(.sm, .medium)
            }
            .foregroundStyle(isHovered ? Theme.foreground : Theme.muted)
            .padding(.horizontal, 14).frame(height: 36)
            .background(isHovered ? Theme.foreground(0.06) : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
