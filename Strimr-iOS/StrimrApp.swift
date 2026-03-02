import SwiftUI

@main
struct StrimrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var watchTogetherViewModel: WatchTogetherViewModel

    init() {
        let deps = AppDependencies.shared
        let downloadManager = DownloadManager(settingsManager: deps.settingsManager)
        _plexApiContext = State(initialValue: deps.plexApiContext)
        _sessionManager = State(initialValue: deps.sessionManager)
        _settingsManager = State(initialValue: deps.settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: deps.libraryStore)
        _seerrStore = State(initialValue: SeerrStore())
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: deps.sessionManager,
            context: deps.plexApiContext,
        ))

        PhoneSessionManager.shared.activate(sessionManager: deps.sessionManager)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(downloadManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(watchTogetherViewModel)
                .preferredColorScheme(.dark)
                .onChange(of: sessionManager.status, initial: true) { _, newStatus in
                    if newStatus == .ready,
                       let token = sessionManager.authToken
                    {
                        PhoneSessionManager.shared.sendAuthToken(
                            token,
                            serverIdentifier: sessionManager.plexServer?.clientIdentifier
                        )
                    }
                }
        }
    }
}
