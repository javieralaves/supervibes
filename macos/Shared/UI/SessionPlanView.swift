import SwiftUI

/// What the session you're in is for, under the current block in the menu bar: your aim, the
/// prepared agenda (folded to a few lines), and the tasks it draws on, which you can check off.
struct SessionPlanView: View {
    let block: Block
    var error: String?
    var onSetTaskDone: (_ taskId: String, _ done: Bool) -> Void = { _, _ in }

    @State private var isExpanded = false

    /// Whether there's anything to show.
    static func hasPlan(_ block: Block) -> Bool {
        block.aim != nil || block.agenda != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let aim = block.aim {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Aim")
                    Text(aim)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let agenda = block.agenda {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("Agenda")
                    Text(agenda.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    // About four lines at this width; shorter agendas show whole.
                    if agenda.text.count > 180 {
                        Button(isExpanded ? "Show less" : "Show more") { isExpanded.toggle() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }

                if !agenda.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Named as in the calendar's block panel.
                        SectionLabel("Related tasks")
                        ForEach(agenda.tasks) { task in
                            TaskRow(task: task) { onSetTaskDone(task.id, !task.done) }
                        }
                    }
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct TaskRow: View {
    let task: SessionAgenda.Item
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.callout)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(TaskItem.minutesLabel(task.minutes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.done ? "Reopen \(task.title)" : "Mark \(task.title) done")
    }
}
