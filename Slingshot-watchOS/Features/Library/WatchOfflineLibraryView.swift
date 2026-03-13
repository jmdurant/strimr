import SwiftUI

struct WatchOfflineLibraryView: View {
    @Environment(WatchDownloadManager.self) private var downloadManager

    let contentType: OfflineContentType

    @State private var selectedItem: DownloadItem?

    private var completedDownloads: [DownloadItem] {
        downloadManager.items.filter {
            $0.status == .completed && $0.metadata.type == plexType
        }
    }

    private var plexType: PlexItemType {
        switch contentType {
        case .movie: .movie
        case .episode: .episode
        case .track: .track
        }
    }

    var body: some View {
        Group {
            if completedDownloads.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("No downloaded \(contentType.label.lowercased()) found.")
                )
            } else {
                List {
                    switch contentType {
                    case .movie:
                        movieList
                    case .episode:
                        episodeList
                    case .track:
                        trackList
                    }
                }
            }
        }
        .navigationTitle(contentType.label)
        .navigationDestination(item: $selectedItem) { item in
            DownloadPlayerLauncher(item: item)
        }
    }

    // MARK: - Movies

    @ViewBuilder
    private var movieList: some View {
        ForEach(completedDownloads.sorted { ($0.metadata.title) < ($1.metadata.title) }) { item in
            Button { selectedItem = item } label: {
                WatchOfflineMediaRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodeList: some View {
        let grouped = Dictionary(grouping: completedDownloads) {
            $0.metadata.grandparentTitle ?? "Unknown Show"
        }
        ForEach(grouped.keys.sorted(), id: \.self) { showName in
            Section(showName) {
                let episodes = (grouped[showName] ?? []).sorted {
                    let s0 = $0.metadata.parentIndex ?? 0
                    let e0 = $0.metadata.index ?? 0
                    let s1 = $1.metadata.parentIndex ?? 0
                    let e1 = $1.metadata.index ?? 0
                    return (s0, e0) < (s1, e1)
                }
                ForEach(episodes) { item in
                    Button { selectedItem = item } label: {
                        WatchOfflineMediaRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Tracks

    @ViewBuilder
    private var trackList: some View {
        let byArtist = Dictionary(grouping: completedDownloads) {
            $0.metadata.grandparentTitle ?? "Unknown Artist"
        }
        ForEach(byArtist.keys.sorted(), id: \.self) { artist in
            let artistTracks = byArtist[artist] ?? []
            let byAlbum = Dictionary(grouping: artistTracks) {
                $0.metadata.parentTitle ?? "Unknown Album"
            }
            ForEach(byAlbum.keys.sorted(), id: \.self) { album in
                Section("\(artist) — \(album)") {
                    let tracks = (byAlbum[album] ?? []).sorted {
                        ($0.metadata.index ?? 0) < ($1.metadata.index ?? 0)
                    }
                    ForEach(tracks) { item in
                        Button { selectedItem = item } label: {
                            WatchOfflineMediaRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Shared Offline Row

struct WatchOfflineMediaRow: View {
    @Environment(WatchDownloadManager.self) private var downloadManager

    let item: DownloadItem

    private var posterHeight: CGFloat {
        item.metadata.type == .track ? 40 : 56
    }

    private var placeholderIcon: String {
        switch item.metadata.type {
        case .track: "music.note"
        case .movie: "film"
        default: "tv"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            PlexAsyncImage(url: downloadManager.localPosterURL(for: item)) {
                Rectangle().fill(.quaternary)
                    .overlay {
                        Image(systemName: placeholderIcon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: 40, height: posterHeight)
            .clipped()
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.metadata.title)
                    .font(.caption)
                    .lineLimit(2)

                if let subtitle = item.metadata.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
