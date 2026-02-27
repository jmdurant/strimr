import SwiftUI

struct WatchPlaylistsView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let library: Library
    let playlistType: String

    @State private var viewModel: LibraryPlaylistsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No Playlists",
                        systemImage: "music.note.list",
                        description: Text("No playlists found")
                    )
                } else {
                    List {
                        ForEach(viewModel.items) { item in
                            if case let .playlist(playlist) = item {
                                NavigationLink(value: playlist) {
                                    playlistRow(playlist)
                                }
                            }
                        }

                        if !viewModel.items.isEmpty {
                            Color.clear
                                .frame(height: 1)
                                .onAppear { Task { await viewModel.loadMore() } }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Playlists")
        .navigationDestination(for: PlaylistMediaItem.self) { playlist in
            WatchPlaylistDetailView(playlist: playlist)
        }
        .task {
            let vm = LibraryPlaylistsViewModel(
                library: library,
                context: plexApiContext,
                playlistType: playlistType
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func playlistRow(_ playlist: PlaylistMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.title)
                .font(.caption)
                .lineLimit(2)
            HStack(spacing: 4) {
                if let count = playlist.leafCount {
                    Text("\(count) items")
                }
                if let duration = playlist.duration {
                    let seconds = TimeInterval(duration) / 1000
                    Text(seconds.mediaDurationText())
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
