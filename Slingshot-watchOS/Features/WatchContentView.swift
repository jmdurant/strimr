import SwiftUI

struct WatchContentView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        switch sessionManager.status {
        case .hydrating:
            ProgressView()
        case .signedOut:
            WatchSignInView()
        case .needsProfileSelection:
            WatchProfileSelectionView()
        case .needsServerSelection:
            NavigationStack {
                WatchServerSelectionView()
            }
        case .ready:
            WatchMainTabView()
        }
    }
}
