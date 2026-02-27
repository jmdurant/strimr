import SwiftUI

struct WatchPlaylistDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(WatchDownloadManager.self) private var downloadManager

    let playlist: PlaylistMediaItem

    @State private var viewModel: PlaylistDetailViewModel?
    @State private var presentedPlayQueue: PlayQueueState?
    @State private var isDownloadingAll = false

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                if let count = viewModel.elementsCountText {
                                    Text(count)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let duration = viewModel.durationText {
                                    Text(duration)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                Task { await playPlaylist(shuffle: false) }
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                Task { await playPlaylist(shuffle: true) }
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                Task { await downloadAll() }
                            } label: {
                                Label(
                                    isDownloadingAll ? "Downloading…" : "Download All",
                                    systemImage: "arrow.down.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isDownloadingAll)
                        }

                        Section {
                            ForEach(viewModel.items) { item in
                                HStack(spacing: 0) {
                                    WatchMediaRow(item: item)
                                    if let mediaItem = item.playableItem {
                                        Spacer()
                                        playlistItemDownloadIcon(mediaItem)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(playlist.title)
        .navigationDestination(for: PlayableMediaItem.self) { media in
            WatchMediaDetailView(media: media)
        }
        .fullScreenCover(item: $presentedPlayQueue) { queue in
            WatchPlayerView(playQueue: queue, shouldResumeFromOffset: false)
                .environment(plexApiContext)
        }
        .task {
            let vm = PlaylistDetailViewModel(playlist: playlist, context: plexApiContext)
            viewModel = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func playlistItemDownloadIcon(_ item: MediaItem) -> some View {
        if let status = downloadManager.downloadStatus(for: item.id) {
            switch status.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .downloading:
                ProgressView()
                    .scaleEffect(0.6)
            case .queued:
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        } else {
            Button {
                Task { await enqueueItem(item) }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func enqueueItem(_ item: MediaItem) async {
        if item.type == .track {
            await downloadManager.enqueueTrack(ratingKey: item.id, context: plexApiContext)
        } else {
            await downloadManager.enqueueItem(ratingKey: item.id, context: plexApiContext)
        }
    }

    private func downloadAll() async {
        guard let items = viewModel?.items else { return }
        isDownloadingAll = true
        for item in items {
            guard let mediaItem = item.playableItem else { continue }
            await enqueueItem(mediaItem)
        }
        isDownloadingAll = false
    }

    private func playPlaylist(shuffle: Bool) async {
        let queueType = playlist.playlistType == "audio" ? "audio" : "video"
        do {
            let manager = try PlayQueueManager(context: plexApiContext)
            let queue = try await manager.createQueue(
                for: playlist.id,
                itemType: .playlist,
                type: queueType,
                continuous: true,
                shuffle: shuffle
            )
            presentedPlayQueue = queue
        } catch {
            debugPrint("Failed to play playlist:", error)
        }
    }
}
