import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct SlingshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SlingshotWidgetEntry {
        SlingshotWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SlingshotWidgetEntry) -> Void) {
        completion(SlingshotWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SlingshotWidgetEntry>) -> Void) {
        let entry = SlingshotWidgetEntry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - Entry

struct SlingshotWidgetEntry: TimelineEntry {
    let date: Date
}

// MARK: - Views

struct SlingshotWidgetEntryView: View {
    var entry: SlingshotWidgetEntry
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
                    Text("Slingshot")
                }
        case .accessoryInline:
            Label {
                Text("Slingshot")
            } icon: {
                Image(systemName: "play.tv.fill")
            }
        case .accessoryRectangular:
            HStack {
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .widgetAccentable()
                Text("Slingshot")
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
struct SlingshotWidget: Widget {
    let kind: String = "SlingshotWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SlingshotTimelineProvider()) { entry in
            SlingshotWidgetEntryView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Slingshot")
        .description("Quick launch Slingshot from your watch face.")
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
    SlingshotWidget()
} timeline: {
    SlingshotWidgetEntry(date: .now)
}
