import SwiftUI
import WidgetKit

struct LibraryWidgetEntry: TimelineEntry {
    let date: Date
    let libraries: [WidgetLibraryItem]
    let hasLiveTV: Bool
}

struct LibraryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LibraryWidgetEntry {
        LibraryWidgetEntry(
            date: .now,
            libraries: [
                WidgetLibraryItem(id: "1", title: "Movies", type: "movie", sectionId: 1),
                WidgetLibraryItem(id: "2", title: "TV Shows", type: "show", sectionId: 2),
                WidgetLibraryItem(id: "3", title: "Music", type: "artist", sectionId: 3),
            ],
            hasLiveTV: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LibraryWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LibraryWidgetEntry>) -> Void) {
        let data = WidgetData.read()
        let entry = LibraryWidgetEntry(
            date: .now,
            libraries: data?.libraries ?? [],
            hasLiveTV: data?.hasLiveTV ?? false
        )
        // Refresh every 30 minutes
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
        completion(timeline)
    }
}

// MARK: - Small Widget (single rotating slide, kept for small size)

struct LibraryWidgetSmallView: View {
    let entry: LibraryWidgetEntry

    var body: some View {
        if let library = entry.libraries.first {
            Link(destination: library.deepLinkURL) {
                ZStack(alignment: .bottomLeading) {
                    gradient(for: library.type)

                    VStack(alignment: .leading, spacing: 4) {
                        Spacer()
                        Image(systemName: library.iconName)
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(library.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.blue.opacity(0.7), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Strimr")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Medium Widget (grid of all libraries)

struct LibraryWidgetMediumView: View {
    let entry: LibraryWidgetEntry

    private var items: [(id: String, title: String, icon: String, type: String, url: URL)] {
        var result = entry.libraries.map {
            (id: $0.id, title: $0.title, icon: $0.iconName, type: $0.type, url: $0.deepLinkURL)
        }
        if entry.hasLiveTV {
            result.append((id: "livetv", title: "Live TV", icon: "tv", type: "livetv", url: WidgetData.liveTVDeepLink))
        }
        return result
    }

    var body: some View {
        if items.isEmpty {
            fallbackView
        } else {
            gridView
        }
    }

    private var gridView: some View {
        let columns = min(items.count, 4)
        let rows = items.count > 4 ? 2 : 1

        return GeometryReader { geo in
            let cellWidth = geo.size.width / CGFloat(columns)
            let cellHeight = geo.size.height / CGFloat(rows)

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        let startIndex = row * columns
                        let endIndex = min(startIndex + columns, items.count)
                        ForEach(startIndex..<endIndex, id: \.self) { index in
                            let item = items[index]
                            Link(destination: item.url) {
                                gridCell(item: item)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                        // Fill remaining space if row is incomplete
                        if endIndex - startIndex < columns {
                            Spacer()
                                .frame(width: cellWidth * CGFloat(columns - (endIndex - startIndex)))
                        }
                    }
                }
            }
        }
    }

    private func gridCell(item: (id: String, title: String, icon: String, type: String, url: URL)) -> some View {
        ZStack {
            gradient(for: item.type)

            VStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var fallbackView: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.7), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Strimr")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Open to get started")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Shared gradient helper

private func gradient(for type: String) -> some View {
    let colors: [Color] = switch type {
    case "movie":
        [.blue.opacity(0.8), .cyan.opacity(0.6)]
    case "show":
        [.orange.opacity(0.8), .red.opacity(0.6)]
    case "artist":
        [.green.opacity(0.8), .teal.opacity(0.6)]
    case "photo":
        [.pink.opacity(0.8), .purple.opacity(0.6)]
    case "livetv":
        [.indigo, .purple.opacity(0.8)]
    default:
        [.blue.opacity(0.7), .purple.opacity(0.6)]
    }

    return LinearGradient(
        colors: colors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Widget Definition

struct LibraryWidget: Widget {
    let kind = "LibraryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LibraryWidgetProvider()) { entry in
            Group {
                switch WidgetFamily.systemMedium {
                default:
                    LibraryWidgetMediumView(entry: entry)
                }
            }
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
        .configurationDisplayName("Libraries")
        .description("Quick access to your Plex libraries")
        .supportedFamilies([.systemMedium])
    }
}
