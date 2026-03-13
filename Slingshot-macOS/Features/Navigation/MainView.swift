import SwiftUI
import os

enum MacRoute: Hashable {
    case mediaDetail(PlayableMediaItem)
    case collectionDetail(CollectionMediaItem)
    case playlistDetail(PlaylistMediaItem)
}

struct MainView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(WatchTogetherViewModel.self) private var watchTogetherViewModel
    @State var homeViewModel: HomeViewModel
    @State private var selection: SidebarItem? = .home
    @State private var navigationPath = NavigationPath()
    @State private var activePlayerViewModel: PlayerViewModel?
    @State private var shouldResume = true

    enum SidebarItem: Hashable {
        case home
        case search
        case liveTV
        case watchTogether
        case library(String)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Main") {
                    Label("tabs.home", systemImage: "house.fill")
                        .tag(SidebarItem.home)
                    Label("tabs.search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                }

                Section("Libraries") {
                    ForEach(libraryStore.libraries) { library in
                        Label(library.title, systemImage: library.iconName)
                            .tag(SidebarItem.library(library.id))
                    }
                }

                if libraryStore.hasLiveTV {
                    Section("Live TV") {
                        Label("Live TV", systemImage: "tv")
                            .tag(SidebarItem.liveTV)
                    }
                }

                Section("Watch Together") {
                    Label("Watch Together", systemImage: "person.2.fill")
                        .tag(SidebarItem.watchTogether)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            NavigationStack(path: $navigationPath) {
                detailView
                    .navigationDestination(for: MacRoute.self) { route in
                        destination(for: route)
                    }
            }
        }
        .onChange(of: selection) { _, _ in
            navigationPath = NavigationPath()
        }
        .task {
            try? await libraryStore.loadLibraries()
        }
        .sheet(isPresented: Binding(
            get: { activePlayerViewModel != nil },
            set: { if !$0 { activePlayerViewModel = nil } }
        )) {
            if let vm = activePlayerViewModel {
                PlayerView(viewModel: vm)
                    .frame(width: 960, height: 540)
                    .environment(plexApiContext)
                    .environment(settingsManager)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .home, .none:
            HomeView(
                viewModel: homeViewModel,
                onSelectMedia: { navigate(to: $0) },
                onSelectLibrary: { library in
                    selection = .library(library.id)
                },
                onSelectLiveTV: {
                    selection = .liveTV
                }
            )
        case .search:
            SearchView(
                viewModel: SearchViewModel(context: plexApiContext),
                onSelectMedia: { navigate(to: $0) }
            )
        case .liveTV:
            LiveTVView { _, _, _, _ in }
        case .watchTogether:
            WatchTogetherView()
        case let .library(libraryId):
            if let library = libraryStore.libraries.first(where: { $0.id == libraryId }) {
                LibraryDetailView(
                    library: library,
                    onSelectMedia: { navigate(to: $0) }
                )
                .id(libraryId)
            } else {
                ContentUnavailableView("Library not found", systemImage: "rectangle.stack.fill")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MacRoute) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    context: plexApiContext
                ),
                onPlay: { ratingKey, type in
                    Task { await play(ratingKey: ratingKey, type: type) }
                },
                onPlayFromStart: { ratingKey, type in
                    Task { await play(ratingKey: ratingKey, type: type, resume: false) }
                },
                onSelectMedia: { navigate(to: $0) }
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    context: plexApiContext
                ),
                onSelectMedia: { navigate(to: $0) },
                onPlay: { ratingKey in
                    Task { await play(ratingKey: ratingKey, type: .collection) }
                },
                onShuffle: { ratingKey in
                    Task { await play(ratingKey: ratingKey, type: .collection, shuffle: true) }
                }
            )
        case let .playlistDetail(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(
                    playlist: playlist,
                    context: plexApiContext
                ),
                onSelectMedia: { navigate(to: $0) },
                onPlay: { ratingKey in
                    Task { await play(ratingKey: ratingKey, type: .playlist) }
                },
                onShuffle: { ratingKey in
                    Task { await play(ratingKey: ratingKey, type: .playlist, shuffle: true) }
                }
            )
        }
    }

    private func navigate(to media: MediaDisplayItem) {
        switch media {
        case let .playable(item):
            guard let playable = PlayableMediaItem(mediaItem: item) else { return }
            navigationPath.append(MacRoute.mediaDetail(playable))
        case let .collection(collection):
            navigationPath.append(MacRoute.collectionDetail(collection))
        case let .playlist(playlist):
            navigationPath.append(MacRoute.playlistDetail(playlist))
        }
    }

    private func play(
        ratingKey: String,
        type: PlexItemType,
        shuffle: Bool = false,
        resume: Bool = true
    ) async {
        do {
            let manager = try PlayQueueManager(context: plexApiContext)
            let playQueue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                type: type.isAudio ? "audio" : "video",
                continuous: type == .episode || type == .show || type == .season
                    || type == .track || type == .album || type == .artist,
                shuffle: shuffle
            )
            guard playQueue.selectedRatingKey != nil else { return }
            let vm = PlayerViewModel(
                playQueue: playQueue,
                ratingKey: playQueue.selectedRatingKey!,
                context: plexApiContext,
                shouldResumeFromOffset: resume
            )
            vm.settingsManager = settingsManager
            NSLog("[Slingshot] Player created — ratingKey: %@", playQueue.selectedRatingKey!)
            activePlayerViewModel = vm
        } catch {
            AppLogger.player.error("Failed to create play queue: \(error)")
        }
    }
}
