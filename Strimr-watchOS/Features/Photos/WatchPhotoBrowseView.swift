import SwiftUI

struct WatchPhotoBrowseView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let library: Library

    @State private var viewModel: PhotoBrowseViewModel?

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
                        "No Albums",
                        systemImage: "photo.on.rectangle",
                        description: Text("No photo albums found in this library")
                    )
                } else {
                    List {
                        ForEach(viewModel.items) { album in
                            NavigationLink(value: album) {
                                albumRow(album)
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
        .navigationDestination(for: MediaItem.self) { album in
            WatchPhotoAlbumView(album: album)
        }
        .task {
            guard let sectionId = library.sectionId else { return }
            let vm = PhotoBrowseViewModel(
                level: .albums(sectionId: sectionId),
                context: plexApiContext
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func albumRow(_ album: MediaItem) -> some View {
        HStack(spacing: 8) {
            if let thumbURL = thumbURL(for: album) {
                PlexAsyncImage(url: thumbURL) {
                    Rectangle().fill(.quaternary)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipped()
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.caption)
                    .lineLimit(2)
                if let secondary = album.secondaryLabel {
                    Text(secondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func thumbURL(for item: MediaItem) -> URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext),
              let path = item.thumbPath else { return nil }
        return imageRepository.transcodeImageURL(path: path, width: 160, height: 160)
    }
}

// MARK: - Photo Album View

struct WatchPhotoAlbumView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let album: MediaItem

    @State private var viewModel: PhotoBrowseViewModel?
    @State private var isShowingPhoto = false
    @State private var selectedPhotoIndex = 0
    @State private var presentedPlayQueue: PlayQueueState?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo",
                        description: Text("No photos found in this album")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    handleTap(item: item, index: index)
                                } label: {
                                    photoThumbnail(item)
                                        .overlay(alignment: .bottomTrailing) {
                                            if item.type == .clip {
                                                Image(systemName: "video.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.white)
                                                    .padding(4)
                                                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                                    .padding(4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(album.title)
        .fullScreenCover(isPresented: $isShowingPhoto) {
            if let viewModel {
                WatchPhotoDetailView(
                    photos: viewModel.items.filter { $0.type != .clip },
                    selectedIndex: selectedPhotoIndex
                )
                .environment(plexApiContext)
            }
        }
        .fullScreenCover(item: $presentedPlayQueue) { queue in
            WatchPlayerView(playQueue: queue, shouldResumeFromOffset: false)
                .environment(plexApiContext)
        }
        .task {
            let vm = PhotoBrowseViewModel(
                level: .photos(albumKey: album.id),
                context: plexApiContext
            )
            viewModel = vm
            await vm.load()
        }
    }

    private func handleTap(item: MediaItem, index: Int) {
        if item.type == .clip {
            Task { await playClip(item) }
        } else {
            let photos = viewModel?.items.filter { $0.type != .clip } ?? []
            if let photoIndex = photos.firstIndex(where: { $0.id == item.id }) {
                selectedPhotoIndex = photoIndex
            }
            isShowingPhoto = true
        }
    }

    private func playClip(_ clip: MediaItem) async {
        let launcher = WatchPlaybackLauncher(context: plexApiContext)
        do {
            let queue = try await launcher.createPlayQueue(
                ratingKey: clip.id,
                type: .clip
            )
            presentedPlayQueue = queue
        } catch {
            debugPrint("Failed to play clip:", error)
        }
    }

    private func photoThumbnail(_ item: MediaItem) -> some View {
        Group {
            if let thumbURL = thumbURL(for: item) {
                PlexAsyncImage(url: thumbURL) {
                    Rectangle().fill(.quaternary)
                }
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(4)
            }
        }
    }

    private func thumbURL(for item: MediaItem) -> URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext),
              let path = item.thumbPath else { return nil }
        return imageRepository.transcodeImageURL(path: path, width: 160, height: 160)
    }
}
