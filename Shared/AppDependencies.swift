import Foundation
import Observation

@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let plexApiContext: PlexAPIContext
    let sessionManager: SessionManager
    let libraryStore: LibraryStore
    let settingsManager: SettingsManager

    private init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        plexApiContext = context
        libraryStore = store
        sessionManager = SessionManager(context: context, libraryStore: store)
        settingsManager = SettingsManager()
    }
}
