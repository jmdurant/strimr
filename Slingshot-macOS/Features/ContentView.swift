import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        Group {
            switch sessionManager.status {
            case .hydrating:
                ProgressView("loading")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView(
                    viewModel: MacSignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext
                    )
                )
            case .needsProfileSelection:
                ProfileSelectionView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager
                    )
                )
            case .needsServerSelection:
                ServerSelectionView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext
                    )
                )
            case .ready:
                MainView(
                    homeViewModel: HomeViewModel(
                        context: plexApiContext,
                        settingsManager: settingsManager,
                        libraryStore: libraryStore
                    )
                )
            }
        }
    }
}
