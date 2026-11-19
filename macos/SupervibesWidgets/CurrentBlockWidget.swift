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
    var next: Block?
    var signedIn = true
}

/// Today's blocks as the app last shared them (Shared/Models/WidgetShare.swift), laid out around
/// each block's start and end. The gallery's preview shows sample data.
struct BlockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BlockEntry {
        sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (BlockEntry) -> Void) {
        if context.isPreview {
            completion(sample())
        } else {
            completion(timeline(from: Date()).entries.first ?? BlockEntry(date: Date(), current: nil))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BlockEntry>) -> Void) {
        completion(timeline(from: Date()))
    }

    private func timeline(from now: Date) -> Timeline<BlockEntry> {
        guard let today = WidgetShare.read() else {
            // Nothing shared yet: the app hasn't run since installing, or isn't signed in.
            return Timeline(entries: [BlockEntry(date: now, current: nil, signedIn: false)], policy: .after(now.addingTimeInterval(15 * 60)))
        }
        let entries = WidgetTimeline.moments(blocks: today.blocks, from: now).map {
            BlockEntry(date: $0.date, current: $0.current, next: $0.next, signedIn: today.signedIn)
        }
        // Plan again in an hour; the app also asks for a reload whenever today's blocks change.
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600)))
    }

    private func sample() -> BlockEntry {
        let now = Fixtures.referenceNow
        let blocks = Fixtures.blocks(around: now)
        return BlockEntry(date: now, current: blocks.first { $0.isHappening(at: now) }, next: blocks.first { $0.start > now })
    }
}

struct CurrentBlockWidgetView: View {
    let entry: BlockEntry

    var body: some View {
        if let current = entry.current {
            CurrentBlockView(block: current, now: entry.date)
        } else {
            NoBlockView(next: entry.next, signedIn: entry.signedIn)
        }
    }
}
