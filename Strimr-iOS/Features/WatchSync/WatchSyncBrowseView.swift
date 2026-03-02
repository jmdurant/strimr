import SwiftUI

@MainActor
struct WatchSyncBrowseView: View {
    @Environment(WatchSyncManager.self) private var syncManager
    @Environment(PlexAPIContext.self) private var context
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            let musicLibraries = libraryStore.libraries.filter { $0.type == .artist }
            if musicLibraries.isEmpty {
                ContentUnavailableView(
                    "No Music Libraries",
                    systemImage: "music.note",
                    description: Text("No music libraries found on your Plex server.")
                )
            } else {
                ForEach(musicLibraries) { library in
                    NavigationLink {
                        WatchSyncArtistListView(library: library)
                    } label: {
                        Label(library.title, systemImage: "music.note.list")
                    }
                }

                Section {
                    NavigationLink {
                        WatchSyncPlaylistListView()
                    } label: {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Add Music")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
        }
    }
}

// MARK: - Artist List

@MainActor
private struct WatchSyncArtistListView: View {
    @Environment(PlexAPIContext.self) private var context
    let library: Library

    @State private var artists: [PlexItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(artists, id: \.ratingKey) { artist in
                    NavigationLink {
                        WatchSyncAlbumListView(artistRatingKey: artist.ratingKey)
                    } label: {
                        Text(artist.title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(library.title)
        .task {
            await loadArtists()
        }
    }

    private func loadArtists() async {
        guard let sectionId = library.sectionId else { return }
        do {
            let repo = try SectionRepository(context: context)
            let response = try await repo.getSectionsItems(
                sectionId: sectionId,
                params: .init(type: "8")
            )
            artists = response.mediaContainer.metadata ?? []
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Album List

@MainActor
private struct WatchSyncAlbumListView: View {
    @Environment(PlexAPIContext.self) private var context
    @Environment(WatchSyncManager.self) private var syncManager
    let artistRatingKey: String

    @State private var albums: [PlexItem] = []
    @State private var isLoading = true
    @State private var artistName: String = ""

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(albums, id: \.ratingKey) { album in
                    NavigationLink {
                        WatchSyncTrackListView(
                            containerRatingKey: album.ratingKey,
                            containerTitle: album.title,
                            contentType: .album
                        )
                    } label: {
                        VStack(alignment: .leading) {
                            Text(album.title)
                            if let year = album.year {
                                Text(String(year))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(artistName.isEmpty ? "Albums" : artistName)
        .task {
            await loadAlbums()
        }
    }

    private func loadAlbums() async {
        do {
            let repo = try MetadataRepository(context: context)
            let response = try await repo.getMetadataChildren(ratingKey: artistRatingKey)
            albums = (response.mediaContainer.metadata ?? []).filter { $0.type == .album }
            artistName = albums.first?.parentTitle ?? ""
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Playlist List

@MainActor
private struct WatchSyncPlaylistListView: View {
    @Environment(PlexAPIContext.self) private var context

    @State private var playlists: [PlexItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if playlists.isEmpty {
                Text("No audio playlists found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlists, id: \.ratingKey) { playlist in
                    NavigationLink {
                        WatchSyncTrackListView(
                            containerRatingKey: playlist.ratingKey,
                            containerTitle: playlist.title,
                            contentType: .playlist
                        )
                    } label: {
                        Text(playlist.title)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Playlists")
        .task {
            await loadPlaylists()
        }
    }

    private func loadPlaylists() async {
        do {
            let repo = try PlaylistRepository(context: context)
            let response = try await repo.getAllPlaylists(playlistType: "audio")
            playlists = response.mediaContainer.metadata ?? []
            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Track List with Selection

enum WatchSyncContentType {
    case album
    case playlist
}

@MainActor
private struct WatchSyncTrackListView: View {
    @Environment(PlexAPIContext.self) private var context
    @Environment(WatchSyncManager.self) private var syncManager
    @Environment(\.dismiss) private var dismiss

    let containerRatingKey: String
    let containerTitle: String
    let contentType: WatchSyncContentType

    @State private var tracks: [PlexItem] = []
    @State private var selectedRatingKeys: Set<String> = []
    @State private var isLoading = true
    @State private var isSyncing = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Section {
                    Button {
                        if selectedRatingKeys.count == tracks.count {
                            selectedRatingKeys.removeAll()
                        } else {
                            selectedRatingKeys = Set(tracks.map(\.ratingKey))
                        }
                    } label: {
                        Text(selectedRatingKeys.count == tracks.count ? "Deselect All" : "Select All")
                    }
                }

                Section {
                    ForEach(tracks, id: \.ratingKey) { track in
                        Button {
                            toggleSelection(track.ratingKey)
                        } label: {
                            HStack {
                                Image(systemName: selectedRatingKeys.contains(track.ratingKey) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedRatingKeys.contains(track.ratingKey) ? .blue : .secondary)

                                VStack(alignment: .leading) {
                                    Text(track.title)
                                        .foregroundStyle(.primary)
                                    if let artist = track.grandparentTitle {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if let duration = track.duration {
                                    Text(formatDuration(duration))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(containerTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    syncSelected()
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Text("Sync (\(selectedRatingKeys.count))")
                    }
                }
                .disabled(selectedRatingKeys.isEmpty || isSyncing)
            }
        }
        .task {
            await loadTracks()
        }
    }

    private func toggleSelection(_ ratingKey: String) {
        if selectedRatingKeys.contains(ratingKey) {
            selectedRatingKeys.remove(ratingKey)
        } else {
            selectedRatingKeys.insert(ratingKey)
        }
    }

    private func syncSelected() {
        isSyncing = true
        Task {
            for ratingKey in selectedRatingKeys {
                await syncManager.syncTrack(ratingKey: ratingKey)
            }
            isSyncing = false
            dismiss()
        }
    }

    private func loadTracks() async {
        do {
            switch contentType {
            case .album:
                let repo = try MetadataRepository(context: context)
                let response = try await repo.getMetadataChildren(ratingKey: containerRatingKey)
                tracks = (response.mediaContainer.metadata ?? []).filter { $0.type == .track }
            case .playlist:
                let repo = try PlaylistRepository(context: context)
                let response = try await repo.getPlaylistItems(ratingKey: containerRatingKey)
                tracks = (response.mediaContainer.metadata ?? []).filter { $0.type == .track }
            }
            selectedRatingKeys = Set(tracks.map(\.ratingKey))
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
