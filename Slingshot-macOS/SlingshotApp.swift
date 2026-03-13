import SwiftUI

@main
struct SlingshotApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var watchTogetherViewModel: WatchTogetherViewModel
    @State private var sharePlayViewModel: SharePlayViewModel

    init() {
        let deps = AppDependencies.shared
        _plexApiContext = State(initialValue: deps.plexApiContext)
        _sessionManager = State(initialValue: deps.sessionManager)
        _settingsManager = State(initialValue: deps.settingsManager)
        _libraryStore = State(initialValue: deps.libraryStore)
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: deps.sessionManager,
            context: deps.plexApiContext,
            settingsManager: deps.settingsManager
        ))
        _sharePlayViewModel = State(initialValue: SharePlayViewModel(context: deps.plexApiContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(watchTogetherViewModel)
                .environment(sharePlayViewModel)
                .tint(settingsManager.interface.accentColor.color)
                .preferredColorScheme(settingsManager.interface.appearance.colorScheme)
                .task {
                    sharePlayViewModel.observeSessions()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .init("slingshot.command.playPause"), object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Skip Forward") {
                    NotificationCenter.default.post(name: .init("slingshot.command.skipForward"), object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Skip Back") {
                    NotificationCenter.default.post(name: .init("slingshot.command.skipBack"), object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
        }

        Settings {
            SettingsView()
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(watchTogetherViewModel)
                .tint(settingsManager.interface.accentColor.color)
                .preferredColorScheme(settingsManager.interface.appearance.colorScheme)
        }
    }
}
