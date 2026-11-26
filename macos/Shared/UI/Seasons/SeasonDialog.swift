import SwiftUI

/// Renames a season or moves its days: its name, its first and last day (each picked on a calendar), and how many
/// weeks that makes. The server's checks show before anything is sent.
struct SeasonDialog: View {
    @State var input: SeasonInput
    var isSaving = false
    var error: String?
    var onCancel: () -> Void = {}
    var onSave: (SeasonInput) -> Void = { _ in }

    @State private var picking: Edge?
    @FocusState private var nameFocused: Bool

    private enum Edge: Hashable { case start, end }

    private var weeks: Int { Swift.max(1, (CalendarDay.daysBetween(input.startsOn, input.endsOn) + 1 + 6) / 7) }
    private var problem: String? { input.problem }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your season").appText(.base, .semibold).foregroundStyle(Theme.foreground)

            TextField("", text: Binding(get: { input.name }, set: { input.name = String($0.prefix(SeasonInput.maxName)) }))
                .textFieldStyle(.plain)
                .font(.app(17, .semibold))
                .foregroundStyle(Theme.foreground)
                .placeholder("Name it", when: input.name.isEmpty, font: .app(17, .semibold))
                .focused($nameFocused)
                .onSubmit(save)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Theme.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(nameFocused ? Theme.foreground(0.6) : Theme.cardBorder, lineWidth: nameFocused ? 1.5 : 1))
                .padding(.top, 16)

            HStack(spacing: 8) {
                dayField("Starts", day: input.startsOn, edge: .start)
                dayField("Ends", day: input.endsOn, edge: .end)
            }
            .padding(.top, 12)

            Text(problem ?? error ?? "\(weeks) \(weeks == 1 ? "week" : "weeks")")
                .appText(.xs)
                .foregroundStyle(problem != nil || error != nil ? Theme.danger : Theme.muted)
                .padding(.top, 10)

            HStack(spacing: 8) {
                Spacer()
                GhostButton(title: "Cancel", action: onCancel).inactive(isSaving)
                PrimaryButton(title: isSaving ? "Saving…" : "Save", isBusy: isSaving, action: save)
                    .inactive(problem != nil)
                    .opacity(problem != nil ? 0.4 : 1)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 400)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.background)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 16)
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.cardBorder))
        .onExitCommand(perform: onCancel)
    }

    private func dayField(_ label: String, day: String, edge: Edge) -> some View {
        Button { picking = edge } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.app(11, .medium)).foregroundStyle(Theme.muted)
                Text(CalendarDay.weekdayMonthDay(day)).font(.app(14, .medium)).foregroundStyle(Theme.foreground)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(picking == edge ? Theme.foreground(0.6) : Theme.cardBorder))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { picking == edge }, set: { if !$0 { picking = nil } }), arrowEdge: .bottom) {
            DayCalendar(title: label, selected: day) { picked in
                if edge == .start { input.startsOn = picked } else { input.endsOn = picked }
                picking = nil
            }
            .padding(12)
        }
    }

    private func save() {
        guard problem == nil, !isSaving else { return }
        onSave(input)
    }
}

#Preview("Season") {
    SeasonDialog(input: SeasonInput(editing: Fixtures.draftSeason))
        .padding(40)
        .background(Theme.shell)
}
