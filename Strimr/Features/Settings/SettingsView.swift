import SwiftUI

@MainActor
struct SettingsView: View {
    var body: some View {
        ContentUnavailableView("Settings", systemImage: "gearshape.fill", description: Text("Settings will be available here soon."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
