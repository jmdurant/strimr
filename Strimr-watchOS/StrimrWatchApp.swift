import SwiftUI

@main
struct StrimrWatchApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var downloadManager: WatchDownloadManager

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
        _downloadManager = State(initialValue: WatchDownloadManager())

        WatchSessionManager.shared.activate()
        WatchSessionManager.shared.onTokenReceived = { _ in
            Task { @MainActor in
                await sessionManager.hydrate()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(downloadManager)
        }
    }
}
