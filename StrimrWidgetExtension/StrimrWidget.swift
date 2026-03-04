import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct StrimrTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StrimrWidgetEntry {
        StrimrWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (StrimrWidgetEntry) -> Void) {
        completion(StrimrWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StrimrWidgetEntry>) -> Void) {
        let entry = StrimrWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Entry

struct StrimrWidgetEntry: TimelineEntry {
    let date: Date
}

// MARK: - Views

struct StrimrWidgetEntryView: View {
    var entry: StrimrWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Image(systemName: "play.tv.fill")
                .font(.title)
                .widgetAccentable()
                .widgetLabel {
                    Text("Strimr")
                }
        case .accessoryInline:
            Label {
                Text("Strimr")
            } icon: {
                Image(systemName: "play.tv.fill")
            }
        case .accessoryRectangular:
            HStack {
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .widgetAccentable()
                Text("Strimr")
                    .font(.headline)
                    .widgetAccentable()
            }
        @unknown default:
            Image(systemName: "play.tv.fill")
                .widgetAccentable()
        }
    }
}

// MARK: - Widget

@main
struct StrimrWidget: Widget {
    let kind: String = "StrimrWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StrimrTimelineProvider()) { entry in
            StrimrWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Strimr")
        .description("Quick launch Strimr from your watch face.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    StrimrWidget()
} timeline: {
    StrimrWidgetEntry(date: .now)
}
