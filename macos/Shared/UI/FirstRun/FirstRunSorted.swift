import SwiftUI

/// Step 2: the plate, sorted. One card per part of life, each with the projects and practices sorted into it, what
/// helps place them, and the tasks found along the way. A practice nobody said the rhythm of asks How often?, and the
/// plate can't be made until each has one.
struct FirstRunSorted: View {
    let plate: SortedPlate
    var isSaving = false
    var error: String?
    let onSetPerWeek: (String, Int) -> Void
    let onBack: () -> Void
    let onSave: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        FirstRunFlow(
            step: 1,
            eyebrow: "Sorted",
            title: "Your plate, sorted",
            subtitle: "Projects have a finish line; practices are things you keep up. Fix anything that’s off, and fill in the gaps."
        ) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(plate.areas) { area in
                        AreaCard(area: area, onSetPerWeek: onSetPerWeek)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } footer: {
            FlowButton(title: "Back", action: onBack)
            Spacer()
            if let error {
                Text(error).appText(.xs).foregroundStyle(Theme.danger).lineLimit(2).padding(.trailing, 8)
            } else if let first = plate.needsRhythm.first {
                Text("Say how often for \(first.title)").appText(.sm).foregroundStyle(Theme.muted).padding(.trailing, 8)
            }
            FlowButton(title: "Looks right", primary: true, isBusy: isSaving, isEnabled: plate.needsRhythm.isEmpty, action: onSave)
        }
    }
}

private struct AreaCard: View {
    let area: PlateArea
    let onSetPerWeek: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AreaTile(icon: area.icon, size: 28)
                Text(area.name).font(.app(14, .semibold)).foregroundStyle(Theme.foreground)
                Spacer()
                Text("\(area.items.count)").font(.app(12, .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(area.items) { item in
                    ItemRow(item: item, onSetPerWeek: { onSetPerWeek(item.id, $0) })
                }
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
    }
}

private struct ItemRow: View {
    let item: PlateItem
    let onSetPerWeek: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GoalBadge(icon: item.icon, color: item.color, size: .xs, round: item.isPractice)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.app(13, .medium)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(item.isPractice ? "Practice" : "Project")
                    if item.isPractice {
                        Text("·").foregroundStyle(Theme.muted.opacity(0.6))
                        RhythmPicker(perWeek: item.perWeek, onPick: onSetPerWeek)
                    } else if let detail = item.detail {
                        Text("·").foregroundStyle(Theme.muted.opacity(0.6))
                        Text(detail).lineLimit(1)
                    }
                }
                .font(.app(11.5))
                .foregroundStyle(Theme.muted)
                ForEach(item.tasks, id: \.self) { task in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.lineStrong, lineWidth: 1).frame(width: 10, height: 10)
                        Text(task).font(.app(11.5)).foregroundStyle(Theme.foreground(0.75)).lineLimit(1)
                    }
                    .padding(.top, 4)
                }
            }
        }
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
