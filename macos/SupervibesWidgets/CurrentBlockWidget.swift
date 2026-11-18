import SwiftUI
import WidgetKit

@main
struct SupervibesWidgets: WidgetBundle {
    var body: some Widget {
        CurrentBlockWidget()
    }
}

struct CurrentBlockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentBlock", provider: BlockTimelineProvider()) { entry in
            CurrentBlockWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Current block")
        .description("What you're working on now, and how long is left.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BlockEntry: TimelineEntry {
    let date: Date
    let current: Block?
}

/// Runs on fixtures until the app shares real data with the widget through an App Group.
struct BlockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlockEntry {
        entry(at: Fixtures.referenceNow, anchor: Fixtures.referenceNow)
    }

    func getSnapshot(in context: Context, completion: @escaping (BlockEntry) -> Void) {
        let now = Date()
        completion(entry(at: now, anchor: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlockEntry>) -> Void) {
        let now = Date()
        let entries = (0..<12).map { step in
            entry(at: now.addingTimeInterval(Double(step) * 5 * 60), anchor: now)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, anchor: Date) -> BlockEntry {
        let current = Fixtures.blocks(around: anchor).first { $0.isHappening(at: date) }
        return BlockEntry(date: date, current: current)
    }
}

struct CurrentBlockWidgetView: View {
    let entry: BlockEntry

    var body: some View {
        if let current = entry.current {
            CurrentBlockView(block: current, now: entry.date)
        } else {
            NoBlockView()
        }
    }
}
