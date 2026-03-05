import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("settings.title", systemImage: "gearshape.fill")
                }

                NavigationLink {
                    DownloadsView()
                } label: {
                    Label("downloads.title", systemImage: "arrow.down.circle.fill")
                }

                NavigationLink {
                    WatchTogetherView()
                } label: {
                    Label("watchTogether.title", systemImage: "person.2.fill")
                }

                NavigationLink {
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager,
                        ),
                    )
                } label: {
                    Label("common.actions.switchProfile", systemImage: "person.2.circle")
                }

                NavigationLink {
                    SelectServerView(
                        viewModel: ServerSelectionViewModel(
                            sessionManager: sessionManager,
                            context: plexApiContext,
                        ),
                    )
                } label: {
                    Label("common.actions.switchServer", systemImage: "server.rack")
                }

                Button {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("common.actions.logOut", systemImage: "arrow.backward.circle")
                }
                .buttonStyle(.plain)
                .tint(.red)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("tabs.more")
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
    }
}
