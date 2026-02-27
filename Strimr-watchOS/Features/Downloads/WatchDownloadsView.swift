import SwiftUI

struct LocalPlaybackRequest: Identifiable, Hashable {
    let id: String
    let ratingKey: String
    let localURL: URL
    let media: MediaItem
}

struct WatchDownloadsView: View {
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State private var selectedItem: DownloadItem?

    var body: some View {
        Group {
            if downloadManager.visibleItems.isEmpty {
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
                        Button {
                            downloadManager.clearList()
                        } label: {
                            Label("Clear List", systemImage: "xmark.circle")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)

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
        .navigationDestination(item: $selectedItem) { item in
            DownloadPlayerLauncher(item: item)
        }
    }

    private var sortedItems: [DownloadItem] {
        downloadManager.visibleItems.sorted { a, b in
            if a.status.isActive != b.status.isActive {
                return a.status.isActive
            }
            return a.createdAt > b.createdAt
        }
    }

    @ViewBuilder
    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.metadata.type == .track ? "music.note" : "film")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

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
        }
        .padding(.vertical, 4)
    }
}

/// Pushed via navigationDestination so fullScreenCover is on a pushed view
/// (not the TabView root), avoiding the present/dismiss loop.
struct DownloadPlayerLauncher: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(WatchDownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss

    let item: DownloadItem

    @State private var playbackRequest: LocalPlaybackRequest?

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .toolbar(.hidden)
            .onAppear {
                guard playbackRequest == nil else { return }
                if let localURL = downloadManager.localVideoURL(for: item) {
                    playbackRequest = LocalPlaybackRequest(
                        id: item.id,
                        ratingKey: item.ratingKey,
                        localURL: localURL,
                        media: downloadManager.localMediaItem(for: item)
                    )
                } else {
                    dismiss()
                }
            }
            .fullScreenCover(item: $playbackRequest, onDismiss: { dismiss() }) { request in
                WatchPlayerView(
                    playQueue: PlayQueueState(localRatingKey: request.ratingKey),
                    shouldResumeFromOffset: true,
                    localMedia: request.media,
                    localPlaybackURL: request.localURL
                )
                .environment(plexApiContext)
            }
    }
}
