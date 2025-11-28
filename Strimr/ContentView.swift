import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            switch sessionStore.status {
            case .hydrating:
                ProgressView("Loading…")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .needsServerSelection:
                Text("Server selection placeholder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                Text("App ready placeholder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
