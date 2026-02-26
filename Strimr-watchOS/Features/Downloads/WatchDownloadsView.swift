import SwiftUI

struct WatchDownloadsView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State private var selectedItem: DownloadItem?

    var body: some View {
        Group {
            if downloadManager.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Downloads")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        storageSection

                        ForEach(sortedItems) { item in
                            Button {
                                if item.isPlayable {
                                    selectedItem = item
                                }
                            } label: {
                                downloadRow(item)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    downloadManager.delete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("Downloads")
        .fullScreenCover(item: $selectedItem) { item in
            if let localURL = downloadManager.localVideoURL(for: item) {
                WatchPlayerView(
                    playQueue: PlayQueueState(localRatingKey: item.ratingKey),
                    shouldResumeFromOffset: false,
                    localMedia: downloadManager.localMediaItem(for: item),
                    localPlaybackURL: localURL
                )
                .environment(plexApiContext)
            }
        }
    }

    private var sortedItems: [DownloadItem] {
        downloadManager.items.sorted { a, b in
            if a.status.isActive != b.status.isActive {
                return a.status.isActive
            }
            return a.createdAt > b.createdAt
        }
    }

    private var storageSection: some View {
        let summary = downloadManager.storageSummary
        let downloadsText = ByteCountFormatter.string(
            fromByteCount: summary.downloadsBytes,
            countStyle: .file
        )
        let availableText = ByteCountFormatter.string(
            fromByteCount: summary.availableBytes,
            countStyle: .file
        )
        return Text("\(downloadsText) used · \(availableText) available")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func downloadRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.metadata.title)
                .font(.caption)
                .lineLimit(2)

            if let subtitle = item.metadata.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            switch item.status {
            case .queued:
                Text("Queued")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .downloading:
                HStack(spacing: 6) {
                    ProgressView(value: item.progress)
                        .tint(.accentColor)
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .completed:
                if let fileSize = item.metadata.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .failed:
                Text("Failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
