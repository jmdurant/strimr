import SwiftUI

struct WatchMusicBrowseView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let library: Library

    @State private var viewModel: MusicBrowseViewModel?
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
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No Artists",
                        systemImage: "music.mic",
                        description: Text("No music found in this library")
                    )
                } else {
                    List {
                        NavigationLink(value: MusicPlaylistsDestination(library: library)) {
                            Label("Playlists", systemImage: "music.note.list")
                        }

                        ForEach(viewModel.items) { artist in
                            NavigationLink(value: artist) {
                                artistRow(artist)
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
        .navigationTitle(library.title)
        .navigationDestination(for: MediaItem.self) { artist in
            WatchMusicAlbumsView(artist: artist)
        }
        .navigationDestination(for: MusicPlaylistsDestination.self) { dest in
            WatchPlaylistsView(library: dest.library, playlistType: "audio")
        }
        .task {
            guard let sectionId = library.sectionId else { return }
            let vm = MusicBrowseViewModel(
                level: .artists(sectionId: sectionId),
                context: plexApiContext
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func artistRow(_ artist: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(artist.title)
                .font(.caption)
                .lineLimit(2)
            if let secondary = artist.secondaryLabel {
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MusicPlaylistsDestination: Hashable {
    let library: Library
}

// MARK: - Album List

struct WatchMusicAlbumsView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let artist: MediaItem

    @State private var viewModel: MusicBrowseViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No Albums",
                        systemImage: "square.stack",
                        description: Text("No albums found")
                    )
                } else {
                    List(viewModel.items) { album in
                        NavigationLink(value: album) {
                            albumRow(album)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(artist.title)
        .navigationDestination(for: MediaItem.self) { album in
            WatchMusicTracksView(album: album)
        }
        .task {
            let vm = MusicBrowseViewModel(
                level: .albums(artistKey: artist.id),
                context: plexApiContext
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func albumRow(_ album: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(album.title)
                .font(.caption)
                .lineLimit(2)
            HStack(spacing: 4) {
                if let year = album.year {
                    Text(String(year))
                }
                if let leafCount = album.leafCount {
                    Text("\(leafCount) tracks")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Track List

struct WatchMusicTracksView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let album: MediaItem

    @State private var viewModel: MusicBrowseViewModel?
    @State private var presentedPlayQueue: PlayQueueState?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No Tracks",
                        systemImage: "music.note",
                        description: Text("No tracks found")
                    )
                } else {
                    List {
                        Button {
                            Task { await playAlbum(shuffle: false) }
                        } label: {
                            Label("Play All", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }

                        Button {
                            Task { await playAlbum(shuffle: true) }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(viewModel.items) { track in
                            Button {
                                Task { await playTrack(track) }
                            } label: {
                                trackRow(track)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(album.title)
        .fullScreenCover(item: $presentedPlayQueue) { queue in
            WatchPlayerView(playQueue: queue, shouldResumeFromOffset: false)
                .environment(plexApiContext)
        }
        .task {
            let vm = MusicBrowseViewModel(
                level: .tracks(albumKey: album.id),
                context: plexApiContext
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func trackRow(_ track: MediaItem) -> some View {
        HStack(spacing: 8) {
            if let index = track.index {
                Text("\(index)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.caption)
                    .lineLimit(1)
                if let duration = track.duration {
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func playTrack(_ track: MediaItem) async {
        let launcher = WatchPlaybackLauncher(context: plexApiContext)
        do {
            let queue = try await launcher.createPlayQueue(
                ratingKey: track.id,
                type: .track
            )
            presentedPlayQueue = queue
        } catch {
            debugPrint("Failed to play track:", error)
        }
    }

    private func playAlbum(shuffle: Bool) async {
        let launcher = WatchPlaybackLauncher(context: plexApiContext)
        do {
            let queue = try await launcher.createPlayQueue(
                ratingKey: album.id,
                type: .album,
                shuffle: shuffle
            )
            presentedPlayQueue = queue
        } catch {
            debugPrint("Failed to play album:", error)
        }
    }
}
