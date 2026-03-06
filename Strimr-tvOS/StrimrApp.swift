import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mediaFocusModel: MediaFocusModel
    @State private var seerrStore: SeerrStore
    @State private var seerrFocusModel: SeerrFocusModel
    @State private var watchTogetherViewModel: WatchTogetherViewModel

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        let settings = SettingsManager()
        _settingsManager = State(initialValue: settings)
        _libraryStore = State(initialValue: store)
        _mediaFocusModel = State(initialValue: MediaFocusModel())
        _seerrStore = State(initialValue: SeerrStore())
        _seerrFocusModel = State(initialValue: SeerrFocusModel())
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: sessionManager,
            context: context,
            settingsManager: settings,
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(mediaFocusModel)
                .environment(seerrStore)
                .environment(seerrFocusModel)
                .environment(watchTogetherViewModel)
                .tint(settingsManager.interface.accentColor.color)
                .preferredColorScheme(settingsManager.interface.appearance.colorScheme)
        }
    }
}
