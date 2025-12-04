import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let context = PlexAPIContext()
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .preferredColorScheme(.dark)
        }
    }
}
