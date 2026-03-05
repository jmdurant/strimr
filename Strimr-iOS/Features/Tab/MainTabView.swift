import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(\.openURL) var openURL
    @Environment(WatchTogetherViewModel.self) var watchTogetherViewModel
    @StateObject var coordinator = MainCoordinator()
    @State var homeViewModel: HomeViewModel
    @State var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                NavigationStack(path: coordinator.pathBinding(for: .home)) {
                    HomeView(
                        viewModel: homeViewModel,
                        onSelectMedia: coordinator.showMediaDetail,
                        onSelectLibrary: { library in
                            coordinator.homePath.append(library)
                        },
                        onSelectLiveTV: {
                            coordinator.homePath.append("liveTV")
                        }
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail,
                        )
                    }
                    .navigationDestination(for: String.self) { value in
                        if value == "liveTV" {
                            LiveTVView()
                        }
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            if coordinator.selectedPlayQueue != nil || LiveActivityManager.shared.hasBackgroundLiveTV {
                Tab("Now Playing", systemImage: "play.circle.fill", value: MainCoordinator.Tab.nowPlaying) {
                    // Content not needed — selecting this tab re-shows the player
                    Color.clear
                }
            }

            if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
                        SeerrDiscoverView(
                            viewModel: SeerrDiscoverViewModel(store: seerrStore),
                            searchViewModel: SeerrSearchViewModel(store: seerrStore),
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )
                        .navigationDestination(for: SeerrMedia.self) { media in
                            SeerrMediaDetailView(
                                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                            )
                        }
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchView(
                        viewModel: SearchViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab("tabs.libraries", systemImage: "rectangle.stack.fill", value: MainCoordinator.Tab.library) {
                NavigationStack(path: coordinator.pathBinding(for: .library)) {
                    LibraryView(
                        viewModel: libraryViewModel,
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail,
                        )
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            TabSection {
                ForEach(navigationLibraries) { library in
                    Tab(
                        library.title,
                        systemImage: library.iconName,
                        value: MainCoordinator.Tab.libraryDetail(library.id),
                    ) {
                        NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.id))) {
                            LibraryDetailView(
                                library: library,
                                onSelectMedia: coordinator.showMediaDetail,
                            )
                            .navigationDestination(for: MainCoordinator.Route.self) {
                                destination(for: $0)
                            }
                        }
                    }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .environmentObject(coordinator)
        .task {
            try? await libraryStore.loadLibraries()
            watchTogetherViewModel.configurePlaybackLauncher(
                PlaybackLauncher(
                    context: plexApiContext,
                    coordinator: coordinator,
                    settingsManager: settingsManager,
                    openURL: { url in openURL(url) },
                ),
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strimr.siri.openLibrary"))) { notification in
            guard let library = notification.userInfo?["library"] as? Library else { return }
            coordinator.tab = .library
            coordinator.libraryPath = NavigationPath()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                coordinator.libraryPath.append(library)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strimr.siri.playQueue"))) { notification in
            guard let playQueue = notification.userInfo?["playQueue"] as? PlayQueueState else { return }
            coordinator.showPlayer(for: playQueue)
        }
        .onChange(of: coordinator.tab) { oldTab, newTab in
            if newTab == .nowPlaying {
                coordinator.tab = oldTab
                if coordinator.selectedPlayQueue != nil {
                    coordinator.resumePlayer()
                } else if LiveActivityManager.shared.hasBackgroundLiveTV {
                    coordinator.resumeLiveTV()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strimr.player.finished"))) { _ in
            coordinator.resetPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("strimr.livetv.finished"))) { _ in
            coordinator.resetLiveTV()
        }
        .onOpenURL { url in
            if url.host == "nowplaying" {
                if coordinator.selectedPlayQueue != nil {
                    coordinator.resumePlayer()
                } else if LiveActivityManager.shared.hasBackgroundLiveTV {
                    coordinator.resumeLiveTV()
                }
            } else if url.host == "library",
                      let libraryId = url.pathComponents.dropFirst().first,
                      let library = libraryStore.libraries.first(where: { $0.id == libraryId })
            {
                coordinator.tab = .library
                coordinator.libraryPath = NavigationPath()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    coordinator.libraryPath.append(library)
                }
            } else if url.host == "livetv" {
                coordinator.tab = .home
                coordinator.homePath = NavigationPath()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    coordinator.homePath.append("liveTV")
                }
            }
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.dismissPlayer) {
            if coordinator.isResumingPlayer,
               let existingVM = LiveActivityManager.shared.activePlayerViewModel,
               LiveActivityManager.shared.hasBackgroundPlayer
            {
                // Reuse existing player (was playing in background)
                PlayerWrapper(viewModel: existingVM)
            } else if let playQueue = coordinator.selectedPlayQueue,
                      let ratingKey = playQueue.selectedRatingKey
            {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        playQueue: playQueue,
                        ratingKey: ratingKey,
                        context: plexApiContext,
                        shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                    ),
                )
            }
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingLiveTV, onDismiss: coordinator.dismissLiveTV) {
            if let url = coordinator.liveTVStreamURL,
               let name = coordinator.liveTVChannelName
            {
                LiveTVPlayerView(streamURL: url, channelName: name, programTitle: coordinator.liveTVProgramTitle, programEndsAt: coordinator.liveTVProgramEndsAt)
            }
        }
    }

    private var navigationLibraries: [Library] {
        let libraryById = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryById[$0] }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    context: plexApiContext,
                ),
                onPlay: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: type)
                    }
                },
                onPlayFromStart: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: type,
                            shouldResumeFromOffset: false,
                        )
                    }
                },
                onShuffle: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: type,
                            shuffle: true,
                        )
                    }
                },
                onSelectMedia: coordinator.showMediaDetail,
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    context: plexApiContext,
                ),
                onSelectMedia: coordinator.showMediaDetail,
                onPlay: { ratingKey in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: .collection)
                    }
                },
                onShuffle: { ratingKey in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: .collection,
                            shuffle: true,
                        )
                    }
                },
            )
        case let .playlistDetail(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(
                    playlist: playlist,
                    context: plexApiContext,
                ),
                onSelectMedia: coordinator.showMediaDetail,
                onPlay: { ratingKey in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: .playlist)
                    }
                },
                onShuffle: { ratingKey in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: .playlist,
                            shuffle: true,
                        )
                    }
                },
            )
        }
    }

    private var playbackLauncher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: coordinator,
            settingsManager: settingsManager,
            openURL: { url in openURL(url) },
        )
    }
}
