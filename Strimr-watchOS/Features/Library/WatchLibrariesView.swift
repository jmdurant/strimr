import SwiftUI

enum OfflineContentType: String, Hashable {
    case movie
    case episode
    case track

    var label: String {
        switch self {
        case .movie: "Movies"
        case .episode: "TV Shows"
        case .track: "Music"
        }
    }

    var icon: String {
        switch self {
        case .movie: "film"
        case .episode: "tv"
        case .track: "music.note"
        }
    }
}

struct WatchLibrariesView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State private var viewModel: LibraryViewModel?
    @State private var hasLiveTV = false
    @State private var showLiveTV = false

    private var isOffline: Bool {
        settingsManager.settings.interface.offlineMode
    }

    var body: some View {
        Group {
            if isOffline {
                offlineContent
            } else {
                onlineContent
            }
        }
        .navigationTitle("Libraries")
        .navigationDestination(for: Library.self) { library in
            if library.type == .artist {
                WatchMusicBrowseView(library: library)
            } else if library.type == .photo {
                WatchPhotoBrowseView(library: library)
            } else {
                WatchLibraryDetailView(library: library)
            }
        }
        .navigationDestination(for: OfflineContentType.self) { contentType in
            WatchOfflineLibraryView(contentType: contentType)
        }
        .navigationDestination(isPresented: $showLiveTV) {
            WatchLiveTVView()
        }
        .task {
            guard !isOffline else { return }
            let vm = LibraryViewModel(context: plexApiContext, libraryStore: libraryStore)
            viewModel = vm
            await vm.load()
            await checkLiveTV()
        }
    }

    // MARK: - Online

    @ViewBuilder
    private var onlineContent: some View {
        if let viewModel {
            if viewModel.isLoading && viewModel.libraries.isEmpty {
                ProgressView()
            } else if viewModel.libraries.isEmpty && !hasLiveTV {
                ContentUnavailableView(
                    "No Libraries",
                    systemImage: "books.vertical",
                    description: Text(viewModel.errorMessage ?? "No libraries found")
                )
            } else {
                List {
                    ForEach(viewModel.libraries) { library in
                        NavigationLink(value: library) {
                            Label(library.title, systemImage: library.iconName)
                        }
                    }

                    if hasLiveTV {
                        Button {
                            showLiveTV = true
                        } label: {
                            Label("Live TV", systemImage: "tv.and.mediabox")
                        }
                    }
                }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Offline

    private var completedDownloads: [DownloadItem] {
        downloadManager.items.filter { $0.status == .completed }
    }

    private var offlineContentTypes: [OfflineContentType] {
        var types: [OfflineContentType] = []
        if completedDownloads.contains(where: { $0.metadata.type == .movie }) {
            types.append(.movie)
        }
        if completedDownloads.contains(where: { $0.metadata.type == .episode }) {
            types.append(.episode)
        }
        if completedDownloads.contains(where: { $0.metadata.type == .track }) {
            types.append(.track)
        }
        return types
    }

    @ViewBuilder
    private var offlineContent: some View {
        if offlineContentTypes.isEmpty {
            ContentUnavailableView(
                "No Downloads",
                systemImage: "arrow.down.circle",
                description: Text("Download content to view it offline.")
            )
        } else {
            List {
                ForEach(offlineContentTypes, id: \.self) { contentType in
                    NavigationLink(value: contentType) {
                        Label(contentType.label, systemImage: contentType.icon)
                    }
                }
            }
        }
    }

    private func checkLiveTV() async {
        do {
            let repo = try LiveTVRepository(context: plexApiContext)
            let response = try await repo.getDVRs()
            hasLiveTV = response.mediaContainer.dvr?.first != nil
        } catch {
            hasLiveTV = false
        }
    }
}
