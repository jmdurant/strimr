import SwiftUI

struct WatchPlaylistDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let playlist: PlaylistMediaItem

    @State private var viewModel: PlaylistDetailViewModel?
    @State private var presentedPlayQueue: PlayQueueState?

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
                        }

                        Section {
                            ForEach(viewModel.items) { item in
                                WatchMediaRow(item: item)
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

    private func playPlaylist(shuffle: Bool) async {
        let launcher = WatchPlaybackLauncher(context: plexApiContext)
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
