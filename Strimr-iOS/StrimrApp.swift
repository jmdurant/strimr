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
    @State private var watchSyncManager: WatchSyncManager

    init() {
        let deps = AppDependencies.shared
        let downloadManager = DownloadManager(settingsManager: deps.settingsManager)
        let syncManager = WatchSyncManager(context: deps.plexApiContext, downloadManager: downloadManager)
        _plexApiContext = State(initialValue: deps.plexApiContext)
        _sessionManager = State(initialValue: deps.sessionManager)
        _settingsManager = State(initialValue: deps.settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: deps.libraryStore)
        _seerrStore = State(initialValue: SeerrStore())
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: deps.sessionManager,
            context: deps.plexApiContext,
            settingsManager: deps.settingsManager,
        ))
        _watchSyncManager = State(initialValue: syncManager)

        PhoneSessionManager.shared.activate(sessionManager: deps.sessionManager)
        PhoneSessionManager.shared.syncManager = syncManager
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
                .environment(watchSyncManager)
                .tint(settingsManager.interface.accentColor.color)
                .preferredColorScheme(settingsManager.interface.appearance.colorScheme)
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
