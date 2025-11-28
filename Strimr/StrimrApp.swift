import SwiftUI

@main
struct StrimrApp: App {
    @StateObject private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionStore)
                .preferredColorScheme(.dark)
        }
    }
}
