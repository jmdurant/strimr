import SwiftUI

struct MainTabTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @StateObject private var coordinator = MainCoordinator()
    @State private var selectedMedia: MediaItem?

    var body: some View {
        TabView(selection: $coordinator.tab) {
            NavigationStack {
                HomeTVView(
                    viewModel: HomeViewModel(context: plexApiContext),
                    onSelectMedia: showMediaDetail
                )
            }
            .tabItem { Label("tabs.home", systemImage: "house.fill") }
            .tag(MainCoordinator.Tab.home)

            NavigationStack {
                SearchTVView(
                    viewModel: SearchViewModel(context: plexApiContext),
                    onSelectMedia: showMediaDetail
                )
            }
            .tabItem { Label("tabs.search", systemImage: "magnifyingglass") }
            .tag(MainCoordinator.Tab.search)

            NavigationStack {
                ZStack {
                    Color("Background")
                        .ignoresSafeArea()

                    LibraryTVView(
                        viewModel: LibraryViewModel(context: plexApiContext),
                        onSelectMedia: showMediaDetail
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: showMediaDetail
                        )
                    }
                }
            }
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }
            .tag(MainCoordinator.Tab.library)

            NavigationStack {
                MoreTVView()
                    .navigationDestination(for: MoreTVRoute.self) { route in
                        switch route {
                        case .settings:
                            SettingsView()
                        }
                    }
            }
            .tabItem { Label("tabs.more", systemImage: "ellipsis.circle") }
            .tag(MainCoordinator.Tab.more)
        }
        .fullScreenCover(item: $selectedMedia) { media in
            MediaDetailTVView(
                viewModel: MediaDetailViewModel(media: media, context: plexApiContext),
                onSelectMedia: showMediaDetail
            )
        }
    }

    private func showMediaDetail(_ media: MediaItem) {
        selectedMedia = media
    }
}
