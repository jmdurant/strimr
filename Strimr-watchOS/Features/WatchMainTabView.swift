import SwiftUI

struct WatchMainTabView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WatchHomeView(
                    viewModel: HomeViewModel(
                        context: plexApiContext,
                        settingsManager: settingsManager,
                        libraryStore: libraryStore
                    )
                )
            }
            .tag(0)

            NavigationStack {
                WatchLibrariesView()
            }
            .tag(1)

            NavigationStack {
                WatchSearchView()
            }
            .tag(2)

            NavigationStack {
                WatchDownloadsView()
            }
            .tag(3)

            NavigationStack {
                WatchSettingsView()
            }
            .tag(4)
        }
    }
}
