import SwiftUI

struct WatchAddToPlaylistView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss

    let ratingKey: String
    let playlistType: String

    @State private var playlists: [PlaylistMediaItem] = []
    @State private var isLoading = true
    @State private var isCreatingNew = false
    @State private var newPlaylistName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List {
                        Section {
                            Button {
                                isCreatingNew = true
                            } label: {
                                Label("New Playlist", systemImage: "plus")
                            }
                        }

                        if !playlists.isEmpty {
                            Section {
                                ForEach(playlists) { playlist in
                                    Button {
                                        Task { await addToPlaylist(playlist) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let count = playlist.leafCount {
                                                Text("\(count) items")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .disabled(isSaving)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationDestination(isPresented: $isCreatingNew) {
                createPlaylistView
            }
            .task {
                await loadPlaylists()
            }
        }
    }

    private var createPlaylistView: some View {
        Form {
            TextField("Playlist Name", text: $newPlaylistName)

            Button {
                Task { await createPlaylist() }
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Create")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        }
        .navigationTitle("New Playlist")
    }

    private func loadPlaylists() async {
        do {
            let repo = try PlaylistRepository(context: plexApiContext)
            let response = try await repo.getAllPlaylists(playlistType: playlistType)
            playlists = (response.mediaContainer.metadata ?? [])
                .compactMap { PlaylistMediaItem(plexItem: $0) }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func addToPlaylist(_ playlist: PlaylistMediaItem) async {
        isSaving = true
        do {
            let repo = try PlaylistRepository(context: plexApiContext)
            try await repo.addItem(toPlaylist: playlist.id, ratingKey: ratingKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func createPlaylist() async {
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true
        do {
            let repo = try PlaylistRepository(context: plexApiContext)
            _ = try await repo.createPlaylist(title: name, type: playlistType, ratingKey: ratingKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
